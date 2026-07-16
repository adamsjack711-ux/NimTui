## Double-bufferable cell grid. Widgets draw into a `Buffer`; the terminal
## layer diffs consecutive buffers and emits minimal ANSI output.
##
## Cells are compact: one `Rune` + style, no per-cell heap allocation.
## Wide glyphs (CJK, emoji) occupy two cells — the head holds the rune and
## the following cell holds the `contRune` sentinel.

import std/unicode
import geometry, style

const contRune* = Rune(0)   ## continuation cell of a wide glyph

type
  Cell* = object
    ch*: Rune
    style*: Style

  Buffer* = object
    w*, h*: int
    cells*: seq[Cell]

  BorderKind* = enum
    bkNone, bkSingle, bkRounded, bkDouble, bkThick

proc `==`*(a, b: Cell): bool =
  a.ch == b.ch and a.style == b.style

proc runeWidth*(r: Rune): int =
  ## Display width of a rune: 2 for East Asian wide/fullwidth and emoji,
  ## 1 otherwise. Combining marks are treated as width 1 (roadmap).
  let c = r.int32
  if c < 0x1100: return 1
  if (c >= 0x1100 and c <= 0x115F) or c == 0x2329 or c == 0x232A or
     (c >= 0x2E80 and c <= 0x303E) or (c >= 0x3041 and c <= 0x33FF) or
     (c >= 0x3400 and c <= 0x4DBF) or (c >= 0x4E00 and c <= 0x9FFF) or
     (c >= 0xA000 and c <= 0xA4CF) or (c >= 0xAC00 and c <= 0xD7A3) or
     (c >= 0xF900 and c <= 0xFAFF) or (c >= 0xFE10 and c <= 0xFE19) or
     (c >= 0xFE30 and c <= 0xFE6F) or (c >= 0xFF00 and c <= 0xFF60) or
     (c >= 0xFFE0 and c <= 0xFFE6) or (c >= 0x1F300 and c <= 0x1FAFF) or
     (c >= 0x20000 and c <= 0x3FFFD):
    return 2
  1

proc strWidth*(s: string): int =
  ## Display width of a string in terminal columns.
  for r in s.runes:
    result += runeWidth(r)

proc newBuffer*(w, h: int): Buffer =
  result = Buffer(w: max(0, w), h: max(0, h))
  result.cells = newSeq[Cell](result.w * result.h)
  for c in result.cells.mitems:
    c.ch = Rune(' ')

proc `[]`*(b: Buffer, x, y: int): Cell =
  if x < 0 or y < 0 or x >= b.w or y >= b.h:
    Cell(ch: Rune(' '))
  else:
    b.cells[y * b.w + x]

proc `[]=`*(b: var Buffer, x, y: int, c: Cell) =
  if x < 0 or y < 0 or x >= b.w or y >= b.h:
    return
  b.cells[y * b.w + x] = c

proc setCell(b: var Buffer, x, y: int, r: Rune, st: Style) =
  ## Single-cell write that keeps wide-glyph pairs coherent: overwriting
  ## a head blanks its continuation and vice versa.
  if x < 0 or y < 0 or x >= b.w or y >= b.h:
    return
  let i = y * b.w + x
  if b.cells[i].ch == contRune and x > 0 and runeWidth(b.cells[i - 1].ch) == 2:
    b.cells[i - 1].ch = Rune(' ')
  if runeWidth(b.cells[i].ch) == 2 and x + 1 < b.w and b.cells[i + 1].ch == contRune:
    b.cells[i + 1].ch = Rune(' ')
  # a wide rune can't fit in the last column
  let rr = if runeWidth(r) == 2 and x == b.w - 1: Rune(' ') else: r
  b.cells[i] = Cell(ch: rr, style: st)

proc put*(b: var Buffer, x, y: int, ch: string, st: Style = Style()) =
  var r = Rune(' ')
  for first in ch.runes:
    r = first
    break
  b.setCell(x, y, r, st)

proc write*(b: var Buffer, x, y: int, s: string, st: Style = Style(),
            maxW = int.high): int =
  ## Write a line of text starting at (x, y). Wide runes take two cells;
  ## a wide rune that doesn't fully fit is dropped. Stops at the buffer
  ## edge, at `maxW` columns, or at a newline. Returns columns advanced.
  var cx = x
  for r in s.runes:
    if r == Rune('\n'): break
    let rw = runeWidth(r)
    if rw == 0: continue
    if cx - x + rw > maxW or cx + rw > b.w: break
    if rw == 2:
      # continuation first, then head — setCell's pair-clearing would
      # otherwise blank the head we just wrote
      b.setCell(cx + 1, y, contRune, st)
      b.setCell(cx, y, r, st)
    else:
      b.setCell(cx, y, r, st)
    cx += rw
  cx - x

proc fillRect*(b: var Buffer, r: Rect, ch = " ", st: Style = Style()) =
  var fill = Rune(' ')
  for first in ch.runes:
    fill = first
    break
  for y in r.y ..< r.bottom:
    for x in r.x ..< r.right:
      b.setCell(x, y, fill, st)

const borderChars: array[BorderKind, array[6, string]] = [
  ["", "", "", "", "", ""],                 # bkNone
  ["┌", "┐", "└", "┘", "─", "│"],           # bkSingle
  ["╭", "╮", "╰", "╯", "─", "│"],           # bkRounded
  ["╔", "╗", "╚", "╝", "═", "║"],           # bkDouble
  ["┏", "┓", "┗", "┛", "━", "┃"],           # bkThick
]

proc drawBorder*(b: var Buffer, r: Rect, kind: BorderKind, st: Style = Style()) =
  if kind == bkNone or r.w < 2 or r.h < 2: return
  let ch = borderChars[kind]
  b.put(r.x, r.y, ch[0], st)
  b.put(r.right - 1, r.y, ch[1], st)
  b.put(r.x, r.bottom - 1, ch[2], st)
  b.put(r.right - 1, r.bottom - 1, ch[3], st)
  for x in r.x + 1 ..< r.right - 1:
    b.put(x, r.y, ch[4], st)
    b.put(x, r.bottom - 1, ch[4], st)
  for y in r.y + 1 ..< r.bottom - 1:
    b.put(r.x, y, ch[5], st)
    b.put(r.right - 1, y, ch[5], st)

proc dump*(b: Buffer): string =
  ## Plain-text snapshot (no styling) — used by tests and `renderToString`.
  ## Wide glyphs appear once (their continuation cells are skipped).
  for y in 0 ..< b.h:
    if y > 0: result.add "\n"
    for x in 0 ..< b.w:
      let c = b.cells[y * b.w + x]
      if c.ch == contRune: continue
      result.add c.ch.toUTF8

proc attrMap*(b: Buffer, attr: Attr): string =
  ## Grid of '#' where `attr` is set and '.' elsewhere — style-aware
  ## snapshot assertions for tests.
  for y in 0 ..< b.h:
    if y > 0: result.add "\n"
    for x in 0 ..< b.w:
      result.add (if attr in b.cells[y * b.w + x].style.attrs: '#' else: '.')

proc diffToAnsi*(prev, next: Buffer): string =
  ## Minimal ANSI update transforming the screen showing `prev` into
  ## `next`. If dimensions differ the whole screen is cleared and redrawn.
  ## Wide glyphs are emitted once; their continuation cells are skipped
  ## (the terminal cursor advances two columns on its own).
  let full = prev.w != next.w or prev.h != next.h
  var lastStyle: Style
  var haveStyle = false
  if full:
    result.add "\e[0m\e[2J"
  for y in 0 ..< next.h:
    var x = 0
    while x < next.w:
      if not full and next[x, y] == prev[x, y]:
        inc x
        continue
      # start of a changed run; if it begins on a continuation cell, back
      # up so the wide head is re-emitted too
      var sx = x
      if next[sx, y].ch == contRune and sx > 0 and
         runeWidth(next[sx - 1, y].ch) == 2:
        dec sx
      result.add "\e[" & $(y + 1) & ";" & $(sx + 1) & "H"
      var cx = sx
      var force = true
      while cx < next.w and
            (force or full or next[cx, y] != prev[cx, y] or
             next[cx, y].ch == contRune):
        force = false
        let c = next[cx, y]
        if c.ch == contRune:
          inc cx   # head already moved the terminal cursor past this cell
          continue
        if not haveStyle or c.style != lastStyle:
          result.add c.style.sgr
          lastStyle = c.style
          haveStyle = true
        result.add c.ch.toUTF8
        inc cx
      x = max(cx, x + 1)
