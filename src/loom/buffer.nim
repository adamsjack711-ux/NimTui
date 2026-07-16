## Double-bufferable cell grid. Widgets draw into a `Buffer`; the terminal
## layer diffs consecutive buffers and emits minimal ANSI output.

import std/unicode
import geometry, style

type
  Cell* = object
    ch*: string   ## one grapheme as UTF-8; "" renders as a space
    style*: Style

  Buffer* = object
    w*, h*: int
    cells*: seq[Cell]

  BorderKind* = enum
    bkNone, bkSingle, bkRounded, bkDouble, bkThick

proc `==`*(a, b: Cell): bool =
  a.ch == b.ch and a.style == b.style

proc newBuffer*(w, h: int): Buffer =
  result = Buffer(w: max(0, w), h: max(0, h))
  result.cells = newSeq[Cell](result.w * result.h)
  for c in result.cells.mitems:
    c.ch = " "

proc `[]`*(b: Buffer, x, y: int): Cell =
  if x < 0 or y < 0 or x >= b.w or y >= b.h:
    Cell(ch: " ")
  else:
    b.cells[y * b.w + x]

proc `[]=`*(b: var Buffer, x, y: int, c: Cell) =
  if x < 0 or y < 0 or x >= b.w or y >= b.h:
    return
  b.cells[y * b.w + x] = c

proc put*(b: var Buffer, x, y: int, ch: string, st: Style = Style()) =
  b[x, y] = Cell(ch: ch, style: st)

proc write*(b: var Buffer, x, y: int, s: string, st: Style = Style(),
            maxW = int.high): int =
  ## Write a line of text starting at (x, y), one rune per cell.
  ## Stops at the buffer edge, at `maxW` cells, or at a newline.
  ## Returns the number of cells written.
  var cx = x
  for r in s.runes:
    if r == Rune('\n'): break
    if cx - x >= maxW or cx >= b.w: break
    if cx >= 0 and y >= 0 and y < b.h:
      b.cells[y * b.w + cx] = Cell(ch: r.toUTF8, style: st)
    inc cx
  cx - x

proc fillRect*(b: var Buffer, r: Rect, ch = " ", st: Style = Style()) =
  for y in r.y ..< r.bottom:
    for x in r.x ..< r.right:
      b[x, y] = Cell(ch: ch, style: st)

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
  for y in 0 ..< b.h:
    if y > 0: result.add "\n"
    for x in 0 ..< b.w:
      let c = b.cells[y * b.w + x]
      result.add (if c.ch.len == 0: " " else: c.ch)

proc diffToAnsi*(prev, next: Buffer): string =
  ## Minimal ANSI update transforming the screen showing `prev` into `next`.
  ## If dimensions differ the whole screen is cleared and redrawn.
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
      result.add "\e[" & $(y + 1) & ";" & $(x + 1) & "H"
      while x < next.w and (full or next[x, y] != prev[x, y]):
        let c = next[x, y]
        if not haveStyle or c.style != lastStyle:
          result.add c.style.sgr
          lastStyle = c.style
          haveStyle = true
        result.add (if c.ch.len == 0: " " else: c.ch)
        inc x
