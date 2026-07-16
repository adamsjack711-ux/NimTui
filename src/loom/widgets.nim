## Built-in leaf widgets: text, rule, gauge, sparkline, list, table,
## input, tabs, spans, viewport. All measurement is display-width aware
## (CJK/emoji take two columns) and styling falls back to the active
## theme when no explicit style is given.

import std/[sequtils, strutils, unicode]
import geometry, style, buffer, events, reactive, widget, theme

proc runesToStr(rs: seq[Rune]): string =
  for r in rs: result.add r.toUTF8

proc clipWidth(s: string, w: int): string =
  ## Clip to at most `w` display columns without splitting a wide glyph.
  var used = 0
  for r in s.runes:
    let rw = runeWidth(r)
    if used + rw > w: break
    result.add r.toUTF8
    used += rw

# ---- Text ------------------------------------------------------------------

type
  Align* = enum
    alLeft, alCenter, alRight

  Text* = ref object of Widget
    content*: string
    style*: Style
    align*: Align
    wrap*: bool

proc wrapLine(line: string, width: int): seq[string] =
  if width <= 0 or line.strWidth <= width:
    return @[line]
  var cur = ""
  var curLen = 0
  for word in line.split(' '):
    let wl = word.strWidth
    if curLen == 0:
      cur = word
      curLen = wl
    elif curLen + 1 + wl <= width:
      cur.add " "
      cur.add word
      curLen += 1 + wl
    else:
      result.add cur
      cur = word
      curLen = wl
  if curLen > 0:
    result.add cur

proc textLines(t: Text, width: int): seq[string] =
  for line in t.content.split('\n'):
    if t.wrap:
      result.add wrapLine(line, width)
    else:
      result.add line

method minSize*(t: Text, avail: Size): Size =
  let ls = t.textLines(avail.w)
  var w = 0
  for l in ls:
    w = max(w, l.strWidth)
  size(min(w, max(avail.w, 0)), ls.len)

method render*(t: Text, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  let ls = t.textLines(area.w)
  for i, line in ls:
    if i >= area.h: break
    let len = line.strWidth
    let x = case t.align
      of alLeft: area.x
      of alCenter: area.x + max(0, (area.w - len) div 2)
      of alRight: area.x + max(0, area.w - len)
    discard buf.write(x, area.y + i, line, t.style, area.right - x)

proc text*(content: string; style = Style(); align = alLeft; wrap = false;
           width = fit(); height = fit()): Text =
  Text(content: content, style: style, align: align, wrap: wrap,
       widthSpec: width, heightSpec: height)

# ---- Rule (horizontal divider) ---------------------------------------------

type Rule* = ref object of Widget
  style*: Style

method minSize*(r: Rule, avail: Size): Size = size(0, 1)

method render*(r: Rule, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.h < 1: return
  let st = if r.style == Style(): theme().dim else: r.style
  for x in area.x ..< area.right:
    buf.put(x, area.y, "─", st)

proc rule*(style = Style()): Rule =
  Rule(style: style, widthSpec: flex(1), heightSpec: fixed(1))

# ---- Gauge -----------------------------------------------------------------

type Gauge* = ref object of Widget
  value*: float          ## 0.0 .. 1.0
  label*: string
  color*: Color          ## default color = theme low/mid/high by value
  showPct*: bool

const gaugeEighths = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

method minSize*(g: Gauge, avail: Size): Size =
  size(g.label.strWidth + 10, 1)

method render*(g: Gauge, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.h < 1 or area.w < 2: return
  var x = area.x
  if g.label.len > 0:
    x += buf.write(x, area.y, g.label & " ", Style(), area.right - x)
  let v = clamp(g.value, 0.0, 1.0)
  var pct = ""
  if g.showPct:
    pct = " " & align($int(v * 100 + 0.5) & "%", 4)
  let barW = area.right - x - pct.len
  if barW < 1: return
  let col =
    if g.color != defaultColor: g.color
    elif v < 0.6: theme().gaugeLow
    elif v < 0.85: theme().gaugeMid
    else: theme().gaugeHigh
  let st = Style(fg: col)
  let filled8 = int(v * barW.float * 8 + 0.5)
  let full = min(filled8 div 8, barW)
  let rem = filled8 mod 8
  for i in 0 ..< barW:
    if i < full:
      buf.put(x + i, area.y, "█", st)
    elif i == full and rem > 0:
      buf.put(x + i, area.y, gaugeEighths[rem], st)
    else:
      buf.put(x + i, area.y, " ", st)
  if pct.len > 0:
    discard buf.write(x + barW, area.y, pct, Style(), pct.len)

proc gauge*(value: float; label = ""; color = defaultColor; showPct = true;
            width = flex(1); height = fixed(1)): Gauge =
  Gauge(value: value, label: label, color: color, showPct: showPct,
        widthSpec: width, heightSpec: height)

# ---- Sparkline ---------------------------------------------------------------

type Sparkline* = ref object of Widget
  data*: seq[float]
  color*: Color   ## default color = theme accent
  zeroBase*: bool ## scale from 0 instead of min(data)

const sparkTicks = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

method minSize*(s: Sparkline, avail: Size): Size =
  size(min(s.data.len, max(avail.w, 0)), 1)

method render*(s: Sparkline, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty or s.data.len == 0: return
  let points = if s.data.len > area.w: s.data[^area.w .. ^1] else: s.data
  var lo = if s.zeroBase: 0.0 else: min(points)
  var hi = max(points)
  if hi <= lo: hi = lo + 1.0
  let st = Style(fg: if s.color == defaultColor: theme().accent else: s.color)
  let xoff = area.w - points.len   # right-align
  let levelMax = area.h * 8
  for i, v in points:
    let lvl = int((v - lo) / (hi - lo) * levelMax.float + 0.5)
    for row in 0 ..< area.h:
      let fromBottom = area.h - 1 - row
      let cellLvl = clamp(lvl - fromBottom * 8, 0, 8)
      buf.put(area.x + xoff + i, area.y + row, sparkTicks[cellLvl], st)

proc sparkline*(data: seq[float]; color = defaultColor; zeroBase = true;
                width = flex(1); height = fixed(1)): Sparkline =
  Sparkline(data: data, color: color, zeroBase: zeroBase,
            widthSpec: width, heightSpec: height)

# ---- List ------------------------------------------------------------------

type List* = ref object of Widget
  items*: seq[string]
  selected*: Signal[int]        ## positional selection
  selectedKey*: Signal[string]  ## keyed selection: tracks `keys[i]`, so it
                                ## survives reordered/filtered data
  keys*: seq[string]            ## row keys, parallel to items (keyed mode)
  style*: Style
  lastH: int    ## viewport height from the last render (page keys)
  lastOff: int  ## scroll offset from the last render (mouse hits)

proc interactive(l: List): bool =
  l.selected != nil or l.selectedKey != nil

proc curIndex(l: List, tracked: bool): int =
  ## Current selection as an index into items; -1 when nothing selected.
  if l.selectedKey != nil:
    let k = if tracked: l.selectedKey.get else: l.selectedKey.peek
    result = l.keys.find(k)
    if result >= l.items.len: result = -1
  elif l.selected != nil:
    let s = if tracked: l.selected.get else: l.selected.peek
    result = clamp(s, 0, max(0, l.items.high))
  else:
    result = -1

proc setIndex(l: List, i: int) =
  if l.selectedKey != nil:
    if i >= 0 and i < min(l.keys.len, l.items.len):
      l.selectedKey.set l.keys[i]
  elif l.selected != nil:
    l.selected.set i

method minSize*(l: List, avail: Size): Size =
  var w = 0
  for it in l.items:
    w = max(w, it.strWidth + 2)
  size(min(w, max(avail.w, 0)), l.items.len)

method render*(l: List, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  l.lastH = area.h
  let sel = if l.interactive: l.curIndex(tracked = true) else: -1
  var off = 0
  if sel >= area.h:
    off = sel - area.h + 1
  elif not l.interactive and l.items.len > area.h:
    off = l.items.len - area.h   # follow the tail
  l.lastOff = off
  for row in 0 ..< area.h:
    let idx = off + row
    if idx >= l.items.len: break
    let isSel = idx == sel
    var st = l.style
    var prefix = ""
    if isSel:
      st = mergeStyle(st, if ctx.focused == l: theme().selection
                          else: theme().selectionUnfocused)
      prefix = "▸ "
    elif l.interactive:
      prefix = "  "
    var line = prefix & l.items[idx]
    line = clipWidth(line, area.w)
    if isSel:
      line = line & spaces(max(0, area.w - line.strWidth))
    discard buf.write(area.x, area.y + row, line, st, area.w)

method handleKey*(l: List, k: Key): bool =
  if not l.interactive or l.items.len == 0: return false
  var s = max(0, l.curIndex(tracked = false))
  let page = max(1, l.lastH)
  case k.kind
  of kUp: s = max(0, s - 1)
  of kDown: s = min(l.items.high, s + 1)
  of kHome: s = 0
  of kEnd: s = l.items.high
  of kPageUp: s = max(0, s - page)
  of kPageDown: s = min(l.items.high, s + page)
  else: return false
  l.setIndex s
  true

method handleMouse*(l: List, m: Mouse, area: Rect): bool =
  if not l.interactive or l.items.len == 0: return false
  case m.kind
  of mPress, mDrag:
    if m.btn != mbLeft: return false
    let idx = l.lastOff + (m.y - area.y)
    if idx < 0 or idx >= l.items.len: return false
    l.setIndex idx
    true
  of mWheelUp:
    l.setIndex max(0, l.curIndex(tracked = false) - 1)
    true
  of mWheelDown:
    l.setIndex min(l.items.high, max(0, l.curIndex(tracked = false)) + 1)
    true
  else: false

proc list*(items: seq[string]; selected: Signal[int] = nil; style = Style();
           autofocus = false; id = ""; width = flex(1); height = flex(1)): List =
  ## Positional selection (or a passive tailing view when `selected` is nil).
  List(items: items, selected: selected, style: style,
       widthSpec: width, heightSpec: height,
       focusable: selected != nil, autofocus: autofocus, id: id)

proc list*(items: seq[string]; selectedKey: Signal[string]; keys: seq[string];
           style = Style(); autofocus = false; id = "";
           width = flex(1); height = flex(1)): List =
  ## Keyed selection: `keys` parallels `items`; the signal holds the key of
  ## the selected row, so selection follows the row through re-sorts.
  List(items: items, selectedKey: selectedKey, keys: keys, style: style,
       widthSpec: width, heightSpec: height,
       focusable: true, autofocus: autofocus, id: id)

# ---- Table -----------------------------------------------------------------

type Table* = ref object of Widget
  headers*: seq[string]
  rows*: seq[seq[string]]
  headerStyle*: Style
  style*: Style

proc colWidths(t: Table, avail: int): seq[int] =
  result = newSeq[int](t.headers.len)
  for i, h in t.headers:
    result[i] = h.strWidth
  for row in t.rows:
    for i, cell in row:
      if i < result.len:
        result[i] = max(result[i], cell.strWidth)

method minSize*(t: Table, avail: Size): Size =
  let ws = t.colWidths(avail.w)
  var total = 0
  for w in ws: total += w + 2
  size(min(max(0, total - 2), max(avail.w, 0)), t.rows.len + 1)

method render*(t: Table, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty or t.headers.len == 0: return
  let ws = t.colWidths(area.w)
  template drawRow(y: int, cells: seq[string], st: Style) =
    var x = area.x
    for i, w in ws:
      if x >= area.right: break
      let cell = if i < cells.len: cells[i] else: ""
      discard buf.write(x, y, clipWidth(cell, w), st, area.right - x)
      x += w + 2
  drawRow(area.y, t.headers, t.headerStyle)
  for r, row in t.rows:
    if r + 1 >= area.h: break
    drawRow(area.y + r + 1, row, t.style)

proc table*(headers: seq[string]; rows: seq[seq[string]];
            headerStyle = Style(attrs: {aBold, aUnderline}); style = Style();
            width = flex(1); height = flex(1)): Table =
  Table(headers: headers, rows: rows, headerStyle: headerStyle, style: style,
        widthSpec: width, heightSpec: height)

# ---- Input -----------------------------------------------------------------

type
  InputState* = ref object
    text*: Signal[string]
    cursor*: Signal[int]   ## rune index; a signal so cursor-only changes
                           ## repaint like any other state change

  Input* = ref object of Widget
    state*: InputState
    placeholder*: string
    style*: Style
    lastOff: int      ## first visible rune index from the last render
    lastOffCol: int   ## display column of that rune

proc inputState*(initial = ""): InputState =
  InputState(text: signal(initial), cursor: signal(initial.runeLen))

method minSize*(i: Input, avail: Size): Size =
  size(max(i.state.text.peek.strWidth + 1, i.placeholder.strWidth), 1)

method render*(inp: Input, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  let focused = ctx.focused == inp
  let runes = inp.state.text.get.toRunes
  let cur = clamp(inp.state.cursor.get, 0, runes.len)
  var cursorCol = 0
  for i in 0 ..< cur:
    cursorCol += runeWidth(runes[i])
  # scroll (in runes) so the cursor column is visible
  var off = 0
  var offCol = 0
  while off < runes.len and cursorCol - offCol >= area.w:
    offCol += runeWidth(runes[off])
    inc off
  inp.lastOff = off
  inp.lastOffCol = offCol
  if runes.len == 0 and inp.placeholder.len > 0:
    discard buf.write(area.x, area.y, inp.placeholder,
                      theme().placeholder, area.w)
  else:
    discard buf.write(area.x, area.y, runesToStr(runes[min(off, runes.len) .. ^1]),
                      inp.style, area.w)
  if focused:
    let cx = area.x + (cursorCol - offCol)
    if cx < area.right:
      var cell = buf[cx, area.y]
      cell.style.attrs.incl aReverse
      buf[cx, area.y] = cell

proc edit(inp: Input, runes: seq[Rune], cur: int) =
  inp.state.cursor.set clamp(cur, 0, runes.len)
  inp.state.text.set runesToStr(runes)

method handleKey*(inp: Input, k: Key): bool =
  var runes = inp.state.text.peek.toRunes
  var cur = clamp(inp.state.cursor.peek, 0, runes.len)
  case k.kind
  of kChar:
    if k.ctrl or k.alt: return false
    for r in k.ch.runes:
      runes.insert(r, cur)
      inc cur
  of kBackspace:
    if cur > 0:
      runes.delete(cur - 1 .. cur - 1)
      dec cur
  of kDelete:
    if cur < runes.len:
      runes.delete(cur .. cur)
  of kLeft: cur = max(0, cur - 1)
  of kRight: cur = min(runes.len, cur + 1)
  of kHome: cur = 0
  of kEnd: cur = runes.len
  else: return false
  inp.edit(runes, cur)
  true

method handleMouse*(inp: Input, m: Mouse, area: Rect): bool =
  if m.kind notin {mPress, mDrag} or m.btn != mbLeft: return false
  let runes = inp.state.text.peek.toRunes
  let targetCol = inp.lastOffCol + (m.x - area.x)
  var col = 0
  var idx = 0
  while idx < runes.len and col < targetCol:
    col += runeWidth(runes[idx])
    inc idx
  inp.state.cursor.set clamp(idx, 0, runes.len)
  true

method handlePaste*(inp: Input, s: string): bool =
  ## Single-line field: control characters become spaces.
  var runes = inp.state.text.peek.toRunes
  var cur = clamp(inp.state.cursor.peek, 0, runes.len)
  for r in s.runes:
    let clean = if r.int32 < 32: Rune(' ') else: r
    runes.insert(clean, cur)
    inc cur
  inp.edit(runes, cur)
  true

proc input*(state: InputState; placeholder = ""; style = Style();
            autofocus = false; id = ""; width = flex(1); height = fixed(1)): Input =
  Input(state: state, placeholder: placeholder, style: style,
        widthSpec: width, heightSpec: height, focusable: true,
        autofocus: autofocus, id: id)

# ---- Tabs ------------------------------------------------------------------

type Tabs* = ref object of Widget
  labels*: seq[string]
  active*: Signal[int]
  style*: Style

method minSize*(t: Tabs, avail: Size): Size =
  var w = 0
  for l in t.labels: w += l.strWidth + 3
  size(w, 1)

method render*(t: Tabs, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  let active = clamp(t.active.get, 0, max(0, t.labels.high))
  let focused = ctx.focused == t
  var x = area.x
  for i, label in t.labels:
    var st: Style
    if i == active:
      st = mergeStyle(t.style, if focused: theme().selection
                               else: theme().selectionUnfocused)
    else:
      st = mergeStyle(t.style, theme().tabInactive)
    x += buf.write(x, area.y, " " & label & " ", st, area.right - x)
    x += buf.write(x, area.y, " ", Style(), area.right - x)

method handleKey*(t: Tabs, k: Key): bool =
  if t.labels.len == 0: return false
  let a = clamp(t.active.peek, 0, t.labels.high)
  case k.kind
  of kLeft: t.active.set((a - 1 + t.labels.len) mod t.labels.len)
  of kRight: t.active.set((a + 1) mod t.labels.len)
  else: return false
  true

method handleMouse*(t: Tabs, m: Mouse, area: Rect): bool =
  if m.kind != mPress or m.btn != mbLeft: return false
  var x = 0
  for i, label in t.labels:
    let w = label.strWidth + 2   # " label " segment
    if m.x - area.x < x + w:
      t.active.set i
      return true
    x += w + 1                   # separator space
  false

proc tabs*(labels: seq[string]; active: Signal[int]; style = Style();
           autofocus = false; id = ""; width = flex(1); height = fixed(1)): Tabs =
  Tabs(labels: labels, active: active, style: style,
       widthSpec: width, heightSpec: height, focusable: true,
       autofocus: autofocus, id: id)

# ---- Spans (rich text) -------------------------------------------------------

type
  Span* = tuple[text: string, style: Style]

  SpanLine* = ref object of Widget
    parts*: seq[Span]
    align*: Align
    wrap*: bool

proc flowSpans(parts: seq[Span], width: int): seq[seq[Span]] =
  ## Greedy word-wrap across styled fragments. '\n' forces a break.
  ## Words split on explicit spaces only — a fragment boundary with no
  ## space around it (styled text directly followed by punctuation)
  ## stays glued, so one word may carry several styles.
  var words: seq[seq[Span]]   # each word = styled pieces glued together
  var breaks: seq[int]        # word index a '\n' forces a break before
  var cur: seq[Span]
  var seg = ""

  proc pushSeg(st: Style) =
    if seg.len > 0:
      if cur.len > 0 and cur[^1].style == st:
        cur[^1].text.add seg
      else:
        cur.add (text: seg, style: st)
      seg = ""

  proc pushWord() =
    if cur.len > 0:
      words.add cur
      cur = @[]

  for part in parts:
    for ch in part.text:
      case ch
      of ' ':
        pushSeg(part.style)
        pushWord()
      of '\n':
        pushSeg(part.style)
        pushWord()
        breaks.add words.len
      else:
        seg.add ch
    pushSeg(part.style)   # the word may continue into the next fragment
  pushWord()

  var line: seq[Span]
  var lineW = 0
  var bi = 0
  template flush() =
    result.add line
    line = @[]
    lineW = 0
  for wi, w in words:
    while bi < breaks.len and breaks[bi] <= wi:
      flush()
      inc bi
    var ww = 0
    for p in w:
      ww += p.text.strWidth
    if lineW == 0:
      line = w
      lineW = ww
    elif width <= 0 or lineW + 1 + ww <= width:
      # join with a space; merge into the previous fragment when the
      # style matches to keep the seq small
      if line[^1].style == w[0].style:
        line[^1].text.add " " & w[0].text
        line.add w[1 .. ^1]
      else:
        line[^1].text.add " "
        line.add w
      lineW += 1 + ww
    else:
      flush()
      line = w
      lineW = ww
  while bi < breaks.len:
    flush()
    inc bi
  if line.len > 0 or result.len == 0:
    result.add line

proc lineWidth(line: seq[Span]): int =
  for p in line: result += p.text.strWidth

method minSize*(s: SpanLine, avail: Size): Size =
  if s.wrap:
    let lines = flowSpans(s.parts, avail.w)
    var w = 0
    for l in lines: w = max(w, l.lineWidth)
    size(min(w, max(avail.w, 0)), lines.len)
  else:
    var w = 0
    for p in s.parts: w += p.text.strWidth
    size(min(w, max(avail.w, 0)), 1)

method render*(s: SpanLine, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  let lines = if s.wrap: flowSpans(s.parts, area.w) else: @[s.parts]
  for row, line in lines:
    if row >= area.h: break
    let total = line.lineWidth
    var x = case s.align
      of alLeft: area.x
      of alCenter: area.x + max(0, (area.w - total) div 2)
      of alRight: area.x + max(0, area.w - total)
    for p in line:
      if x >= area.right: break
      x += buf.write(x, area.y + row, p.text, p.style, area.right - x)

proc spans*(parts: openArray[Span]; align = alLeft; wrap = false;
            width = fit(); height = fit()): SpanLine =
  ## Mixed-style text, e.g.
  ## `spans([("ok", style(fg = clGreen)), (" 34 checks", Style())])`.
  ## With `wrap = true` fragments flow across as many lines as needed.
  SpanLine(parts: @parts, align: align, wrap: wrap,
           widthSpec: width, heightSpec: height)

# ---- Viewport (scrollable content) -------------------------------------------

type Viewport* = ref object of Widget
  content*: Widget       ## rendered at natural height, then windowed.
                         ## Display-only: widgets inside don't get focus.
  scroll*: Signal[int]   ## top row offset
  lastH: int
  lastContentH: int

const maxViewportContent = 10_000   # rows; runaway-content guard

proc maxScroll(v: Viewport): int =
  max(0, v.lastContentH - v.lastH)

method minSize*(v: Viewport, avail: Size): Size = size(0, 1)

method render*(v: Viewport, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty or v.content == nil: return
  let contentH = clamp(v.content.minSize(size(area.w, maxViewportContent)).h,
                       0, maxViewportContent)
  v.lastH = area.h
  v.lastContentH = contentH
  let sc = clamp(v.scroll.get, 0, v.maxScroll)
  var off = newBuffer(area.w, contentH)
  # fresh context: inner hit regions would carry offscreen coordinates
  v.content.render(off, rect(0, 0, area.w, contentH), RenderCtx())
  for row in 0 ..< min(area.h, contentH - sc):
    for x in 0 ..< area.w:
      buf[area.x + x, area.y + row] = off[x, sc + row]
  if contentH > area.h and area.w > 0:
    let barX = area.right - 1
    let thumbH = max(1, area.h * area.h div contentH)
    let thumbY = if v.maxScroll == 0: 0
                 else: (area.h - thumbH) * sc div v.maxScroll
    for row in 0 ..< area.h:
      let ch = if row >= thumbY and row < thumbY + thumbH: "┃" else: "│"
      buf.put(barX, area.y + row, ch, theme().dim)

method handleKey*(v: Viewport, k: Key): bool =
  let page = max(1, v.lastH)
  var sc = clamp(v.scroll.peek, 0, v.maxScroll)
  case k.kind
  of kUp: sc = max(0, sc - 1)
  of kDown: sc = min(v.maxScroll, sc + 1)
  of kPageUp: sc = max(0, sc - page)
  of kPageDown: sc = min(v.maxScroll, sc + page)
  of kHome: sc = 0
  of kEnd: sc = v.maxScroll
  else: return false
  v.scroll.set sc
  true

method handleMouse*(v: Viewport, m: Mouse, area: Rect): bool =
  case m.kind
  of mWheelUp: v.scroll.set max(0, clamp(v.scroll.peek, 0, v.maxScroll) - 3)
  of mWheelDown: v.scroll.set min(v.maxScroll, clamp(v.scroll.peek, 0, v.maxScroll) + 3)
  else: return false
  true

proc viewport*(content: Widget; scroll: Signal[int]; focusable = true;
               id = ""; width = flex(1); height = flex(1)): Viewport =
  ## Scrollable window over content taller than the screen. Arrow/page
  ## keys and the wheel scroll it; a scrollbar appears when needed.
  Viewport(content: content, scroll: scroll, focusable: focusable,
           id: id, widthSpec: width, heightSpec: height)
