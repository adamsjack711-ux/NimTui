## Terminal chess built with loom — the custom-widget stress test: the
## board is one hand-rolled widget (render + key + mouse methods) riding
## the framework's focus, hit-testing and dirty-repaint machinery.
##
## Hot-seat two-player. Full legal move generation: castling, en passant,
## auto-queen promotion, check/checkmate/stalemate detection. Click or
## drag pieces with the mouse (press selects, drag shows a landing-square
## hover, release drops), or drive the cursor with arrows + enter.
##
##   nim c -d:release examples/chess.nim && ./bin/chess

import std/[sequtils, strutils]
import loom

# ---- engine ------------------------------------------------------------------

type
  PKind = enum pNone, pPawn, pKnight, pBishop, pRook, pQueen, pKing
  PColor = enum cWhite, cBlack

  Piece = object
    kind: PKind
    color: PColor

  Position = object
    board: array[64, Piece]          # a1 = 0, h8 = 63
    turn: PColor
    castle: array[PColor, tuple[k, q: bool]]
    ep: int                          # en-passant target square, -1 = none
    lastFrom, lastTo: int
    taken: array[PColor, seq[PKind]] # pieces of that color off the board

  Game = ref object
    pos: Position
    hist: seq[Position]
    moves: seq[string]
    sel, cursor, hover: int          # squares; -1 = none
    flipped: bool

proc fileOf(sq: int): int = sq mod 8
proc rankOf(sq: int): int = sq div 8
proc opp(c: PColor): PColor = (if c == cWhite: cBlack else: cWhite)
proc sqName(sq: int): string =
  $chr(ord('a') + fileOf(sq)) & $chr(ord('1') + rankOf(sq))

const glyphs: array[PKind, string] = ["", "♟", "♞", "♝", "♜", "♛", "♚"]

proc startPos(): Position =
  const back = [pRook, pKnight, pBishop, pQueen, pKing, pBishop, pKnight, pRook]
  for f in 0 .. 7:
    result.board[f] = Piece(kind: back[f], color: cWhite)
    result.board[8 + f] = Piece(kind: pPawn, color: cWhite)
    result.board[48 + f] = Piece(kind: pPawn, color: cBlack)
    result.board[56 + f] = Piece(kind: back[f], color: cBlack)
  result.turn = cWhite
  result.castle = [(k: true, q: true), (k: true, q: true)]
  result.ep = -1
  result.lastFrom = -1
  result.lastTo = -1

proc pseudoTargets(p: Position, frm: int, attacksOnly = false): seq[int] =
  ## Moves by piece rules alone. With `attacksOnly`, squares the piece
  ## attacks (pawn diagonals regardless of occupancy, no pushes).
  let pc = p.board[frm]
  let f = fileOf(frm)
  let r = rankOf(frm)

  template tryStep(df, dr: int) =
    let nf = f + df
    let nr = r + dr
    if nf in 0 .. 7 and nr in 0 .. 7:
      let t = nr * 8 + nf
      if attacksOnly or p.board[t].kind == pNone or p.board[t].color != pc.color:
        result.add t

  template slide(df, dr: int) =
    var nf = f + df
    var nr = r + dr
    while nf in 0 .. 7 and nr in 0 .. 7:
      let t = nr * 8 + nf
      if p.board[t].kind == pNone:
        result.add t
      else:
        if attacksOnly or p.board[t].color != pc.color:
          result.add t
        break
      nf += df
      nr += dr

  case pc.kind
  of pNone:
    discard
  of pPawn:
    let dr = if pc.color == cWhite: 1 else: -1
    if not attacksOnly:
      let one = frm + dr * 8
      if one in 0 .. 63 and p.board[one].kind == pNone:
        result.add one
        let startR = if pc.color == cWhite: 1 else: 6
        if r == startR and p.board[frm + dr * 16].kind == pNone:
          result.add frm + dr * 16
    for df in [-1, 1]:
      if f + df in 0 .. 7:
        let t = frm + dr * 8 + df
        if t in 0 .. 63:
          if attacksOnly:
            result.add t
          elif p.board[t].kind != pNone and p.board[t].color != pc.color:
            result.add t
          elif t == p.ep:
            result.add t
  of pKnight:
    for (df, dr) in [(1, 2), (2, 1), (2, -1), (1, -2),
                     (-1, -2), (-2, -1), (-2, 1), (-1, 2)]:
      tryStep(df, dr)
  of pBishop:
    for (df, dr) in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
      slide(df, dr)
  of pRook:
    for (df, dr) in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
      slide(df, dr)
  of pQueen:
    for (df, dr) in [(1, 1), (1, -1), (-1, 1), (-1, -1),
                     (1, 0), (-1, 0), (0, 1), (0, -1)]:
      slide(df, dr)
  of pKing:
    for (df, dr) in [(1, 1), (1, 0), (1, -1), (0, 1),
                     (0, -1), (-1, 1), (-1, 0), (-1, -1)]:
      tryStep(df, dr)

proc attacked(p: Position, sq: int, by: PColor): bool =
  for i in 0 .. 63:
    if p.board[i].kind != pNone and p.board[i].color == by and
       sq in p.pseudoTargets(i, attacksOnly = true):
      return true

proc kingSq(p: Position, c: PColor): int =
  for i in 0 .. 63:
    if p.board[i].kind == pKing and p.board[i].color == c:
      return i
  -1

proc inCheck(p: Position, c: PColor): bool =
  attacked(p, p.kingSq(c), opp(c))

proc rawApply(p: var Position, frm, to: int) =
  ## Mutate the position: capture (incl. en passant), castle rook hop,
  ## auto-queen promotion, rights and ep bookkeeping, side to move.
  let pc = p.board[frm]
  var capSq = to
  if pc.kind == pPawn and to == p.ep and p.board[to].kind == pNone:
    capSq = to + (if pc.color == cWhite: -8 else: 8)
  let cap = p.board[capSq]
  if cap.kind != pNone:
    p.taken[cap.color].add cap.kind
    p.board[capSq] = Piece()
  p.board[to] = pc
  p.board[frm] = Piece()
  p.ep = -1
  case pc.kind
  of pPawn:
    if abs(to - frm) == 16:
      p.ep = (frm + to) div 2
    elif rankOf(to) == (if pc.color == cWhite: 7 else: 0):
      p.board[to].kind = pQueen
  of pKing:
    p.castle[pc.color] = (k: false, q: false)
    if to - frm == 2:          # O-O: rook h -> f
      p.board[frm + 1] = p.board[frm + 3]
      p.board[frm + 3] = Piece()
    elif frm - to == 2:        # O-O-O: rook a -> d
      p.board[frm - 1] = p.board[frm - 4]
      p.board[frm - 4] = Piece()
  else:
    discard
  if frm == 0 or capSq == 0: p.castle[cWhite].q = false
  if frm == 7 or capSq == 7: p.castle[cWhite].k = false
  if frm == 56 or capSq == 56: p.castle[cBlack].q = false
  if frm == 63 or capSq == 63: p.castle[cBlack].k = false
  p.lastFrom = frm
  p.lastTo = to
  p.turn = opp(p.turn)

proc legalTargets(p: Position, frm: int): seq[int] =
  let pc = p.board[frm]
  if pc.kind == pNone or pc.color != p.turn:
    return
  for t in p.pseudoTargets(frm):
    var nxt = p
    rawApply(nxt, frm, t)
    if not attacked(nxt, nxt.kingSq(pc.color), opp(pc.color)):
      result.add t
  # castling: king on its home square, rights intact, path empty and safe
  if pc.kind == pKing and fileOf(frm) == 4 and
     rankOf(frm) == (if pc.color == cWhite: 0 else: 7) and
     not attacked(p, frm, opp(pc.color)):
    let e = opp(pc.color)
    if p.castle[pc.color].k and p.board[frm + 1].kind == pNone and
       p.board[frm + 2].kind == pNone and
       not attacked(p, frm + 1, e) and not attacked(p, frm + 2, e):
      result.add frm + 2
    if p.castle[pc.color].q and p.board[frm - 1].kind == pNone and
       p.board[frm - 2].kind == pNone and p.board[frm - 3].kind == pNone and
       not attacked(p, frm - 1, e) and not attacked(p, frm - 2, e):
      result.add frm - 2

proc hasLegal(p: Position): bool =
  for i in 0 .. 63:
    if p.board[i].kind != pNone and p.board[i].color == p.turn and
       p.legalTargets(i).len > 0:
      return true

proc makeMove(g: Game, frm, to: int) =
  let before = g.pos
  g.hist.add before
  let pc = before.board[frm]
  let isCastle = pc.kind == pKing and abs(to - frm) == 2
  let isCap = before.board[to].kind != pNone or
              (pc.kind == pPawn and to == before.ep)
  rawApply(g.pos, frm, to)
  var nota =
    if isCastle:
      (if to > frm: "O-O" else: "O-O-O")
    else:
      glyphs[pc.kind] & sqName(frm) & (if isCap: "×" else: "–") & sqName(to)
  if pc.kind == pPawn and g.pos.board[to].kind == pQueen:
    nota.add "=♛"
  if g.pos.inCheck(g.pos.turn):
    nota.add (if g.pos.hasLegal: "+" else: "#")
  g.moves.add nota
  g.sel = -1
  g.hover = -1
  g.cursor = to

proc activate(g: Game, sq: int) =
  ## Select-or-move, shared by enter/space and mouse press.
  let pc = g.pos.board[sq]
  if g.sel < 0:
    if pc.kind != pNone and pc.color == g.pos.turn:
      g.sel = sq
  elif sq == g.sel:
    g.sel = -1
  elif sq in g.pos.legalTargets(g.sel):
    g.makeMove(g.sel, sq)
  elif pc.kind != pNone and pc.color == g.pos.turn:
    g.sel = sq

proc statusText(g: Game): string =
  let mover = if g.pos.turn == cWhite: "white" else: "black"
  if not g.pos.hasLegal:
    if g.pos.inCheck(g.pos.turn):
      "checkmate — " & (if g.pos.turn == cWhite: "black" else: "white") & " wins"
    else:
      "stalemate — draw"
  elif g.pos.inCheck(g.pos.turn):
    mover & " to move — check!"
  else:
    mover & " to move"

# ---- the board widget ----------------------------------------------------------

const
  sqW = 4
  sqH = 2
  labelW = 2
  boardCols = labelW + 8 * sqW      # 34
  boardRows = 8 * sqH + 1           # 17: squares + file labels

  bgLight = c256(137)
  bgDark = c256(94)
  bgLast = c256(143)                # from/to of the previous move
  bgCapture = c256(131)             # legal target holding an enemy piece
  bgHover = c256(110)               # drag landing square
  bgSel = c256(68)
  bgCursor = c256(117)
  bgCheck = c256(160)
  fgWhitePc = c256(231)
  fgBlackPc = c256(16)

type BoardWidget = ref object of Widget
  g: Game

proc boardWidget(g: Game): BoardWidget =
  BoardWidget(g: g, widthSpec: fixed(boardCols), heightSpec: fixed(boardRows),
              focusable: true, autofocus: true, id: "board")

method minSize(b: BoardWidget, avail: Size): Size =
  size(boardCols, boardRows)

method render(b: BoardWidget, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  let g = b.g
  let focused = ctx.focused == b
  let legal = if g.sel >= 0: g.pos.legalTargets(g.sel) else: @[]
  let checkSq = if g.pos.inCheck(g.pos.turn): g.pos.kingSq(g.pos.turn) else: -1
  for row in 0 .. 7:
    let rk = if g.flipped: row else: 7 - row
    let y0 = area.y + row * sqH
    if y0 + sqH > area.bottom: break
    discard buf.write(area.x, y0 + (sqH - 1) div 2,
                      $chr(ord('1') + rk), theme().dim, 1)
    for col in 0 .. 7:
      let fl = if g.flipped: 7 - col else: col
      let sq = rk * 8 + fl
      let x0 = area.x + labelW + col * sqW
      if x0 + sqW > area.right: continue
      let pc = g.pos.board[sq]
      var bg = if (rk + fl) mod 2 == 1: bgLight else: bgDark
      if sq == g.pos.lastFrom or sq == g.pos.lastTo: bg = bgLast
      if sq == checkSq: bg = bgCheck
      if sq in legal and pc.kind != pNone: bg = bgCapture
      if sq == g.hover and sq in legal: bg = bgHover
      if sq == g.sel: bg = bgSel
      if focused and sq == g.cursor: bg = bgCursor
      fillRect(buf, rect(x0, y0, sqW, sqH), " ", Style(bg: bg))
      let cy = y0 + (sqH - 1) div 2
      if pc.kind != pNone:
        buf.put(x0 + 1, cy, glyphs[pc.kind], Style(
          fg: (if pc.color == cWhite: fgWhitePc else: fgBlackPc),
          bg: bg,
          attrs: (if pc.color == cWhite: {aBold} else: {})))
      elif sq in legal:
        buf.put(x0 + 1, cy, "•", Style(fg: fgBlackPc, bg: bg))
  let ly = area.y + 8 * sqH
  if ly < area.bottom:
    for col in 0 .. 7:
      let fl = if g.flipped: 7 - col else: col
      discard buf.write(area.x + labelW + col * sqW + 1, ly,
                        $chr(ord('a') + fl), theme().dim, 1)

method handleKey(b: BoardWidget, k: Key): bool =
  let g = b.g
  var f = fileOf(g.cursor)
  var r = rankOf(g.cursor)
  let d = if g.flipped: -1 else: 1   # visual direction -> board direction
  case k.kind
  of kUp: r = clamp(r + d, 0, 7)
  of kDown: r = clamp(r - d, 0, 7)
  of kLeft: f = clamp(f - d, 0, 7)
  of kRight: f = clamp(f + d, 0, 7)
  of kEnter:
    g.activate(g.cursor)
    return true
  of kChar:
    if k.isChar(" "):
      g.activate(g.cursor)
      return true
    return false
  else:
    return false
  g.cursor = r * 8 + f
  true

proc squareAt(g: Game, dx, dy: int): int =
  let bx = dx - labelW
  if bx < 0 or dy < 0: return -1
  let col = bx div sqW
  let row = dy div sqH
  if col > 7 or row > 7: return -1
  let rk = if g.flipped: row else: 7 - row
  let fl = if g.flipped: 7 - col else: col
  rk * 8 + fl

method handleMouse(b: BoardWidget, m: Mouse, area: Rect): bool =
  let g = b.g
  let sq = g.squareAt(m.x - area.x, m.y - area.y)
  case m.kind
  of mPress:
    if m.btn != mbLeft or sq < 0: return false
    g.cursor = sq
    g.activate(sq)
    g.hover = -1
    true
  of mDrag:
    if sq < 0: return false
    g.cursor = sq
    if g.sel >= 0:
      g.hover = sq
    true
  of mRelease:
    if sq >= 0 and g.sel >= 0 and sq != g.sel and
       sq in g.pos.legalTargets(g.sel):
      g.makeMove(g.sel, sq)
    g.hover = -1
    true
  else:
    false

# ---- view --------------------------------------------------------------------

var game = Game(pos: startPos(), sel: -1, cursor: 12, hover: -1)  # cursor on e2

proc takenRow(g: Game, c: PColor): string =
  let ts = g.pos.taken[c]
  if ts.len == 0: "—" else: ts.mapIt(glyphs[it]).join(" ")

proc moveRows(g: Game): seq[string] =
  var i = 0
  while i < g.moves.len:
    var row = alignLeft($(i div 2 + 1) & ".", 4) & alignLeft(g.moves[i], 12)
    if i + 1 < g.moves.len:
      row.add g.moves[i + 1]
    result.add row
    i += 2

const
  hintKey = Style(fg: clBrightYellow)
  hintDim = Style(fg: clBrightBlack)

proc view(): Widget =
  tui:
    vbox:
      hbox:
        vbox(width = fixed(boardCols + 2)):
          panel(title = "chess", height = fixed(boardRows + 2)):
            boardWidget(game)
          spacer()
        vbox:
          panel(title = "game", height = fixed(8)):
            text(statusText(game), style = Style(attrs: {aBold}))
            text("")
            spans([("white took  ", hintDim), (takenRow(game, cBlack), Style())])
            spans([("black took  ", hintDim), (takenRow(game, cWhite), Style())])
            text("")
            if game.sel >= 0:
              text("selected " & sqName(game.sel) & " — dots mark legal moves",
                   style = hintDim)
            else:
              text("cursor " & sqName(game.cursor), style = hintDim)
          panel(title = "moves"):
            list(moveRows(game))
      hbox(height = fixed(1)):
        spans([(" click/drag ", hintKey), ("move", hintDim), ("  ↑↓←→ ", hintKey),
               ("cursor", hintDim), ("  enter ", hintKey), ("select", hintDim),
               ("  u ", hintKey), ("undo", hintDim), ("  f ", hintKey),
               ("flip", hintDim), ("  r ", hintKey), ("reset", hintDim),
               ("  t ", hintKey), ("theme", hintDim), ("  q ", hintKey),
               ("quit", hintDim)])

# ---- wiring ------------------------------------------------------------------

proc main() =
  let app = newApp(view, mouse = true)
  var mouseOn = true
  const themes = [themeDefault, themeNeon, themeMono]
  var themeIdx = 0

  app.onKey(proc (k: Key): bool =
    if k.isChar("q"):
      app.quit()
      true
    elif k.isChar("u"):
      if game.hist.len > 0:
        game.pos = game.hist[^1]
        game.hist.setLen game.hist.len - 1
        game.moves.setLen game.moves.len - 1
        game.sel = -1
        game.hover = -1
      true
    elif k.isChar("r"):
      game.pos = startPos()
      game.hist = @[]
      game.moves = @[]
      game.sel = -1
      game.hover = -1
      true
    elif k.isChar("f"):
      game.flipped = not game.flipped
      true
    elif k.isChar("t"):
      themeIdx = (themeIdx + 1) mod themes.len
      setTheme(themes[themeIdx])
      true
    elif k.isChar("m"):
      mouseOn = not mouseOn
      app.setMouse(mouseOn)
      true
    else:
      false)

  app.run()

main()
