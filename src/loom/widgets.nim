## Built-in leaf widgets: text, rule, gauge, sparkline, list, table,
## input, tabs.

import std/[sequtils, strutils, unicode]
import geometry, style, buffer, events, reactive, widget

proc runesToStr(rs: seq[Rune]): string =
  for r in rs: result.add r.toUTF8

proc clipRunes(s: string, w: int): string =
  var n = 0
  for r in s.runes:
    if n >= w: break
    result.add r.toUTF8
    inc n

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
  if width <= 0 or line.runeLen <= width:
    return @[line]
  var cur = ""
  var curLen = 0
  for word in line.split(' '):
    let wl = word.runeLen
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
    w = max(w, l.runeLen)
  size(min(w, max(avail.w, 0)), ls.len)

method render*(t: Text, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  let ls = t.textLines(area.w)
  for i, line in ls:
    if i >= area.h: break
    let len = line.runeLen
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
  for x in area.x ..< area.right:
    buf.put(x, area.y, "─", r.style)

proc rule*(style = Style(fg: clBrightBlack)): Rule =
  Rule(style: style, widthSpec: flex(1), heightSpec: fixed(1))

# ---- Gauge -----------------------------------------------------------------

type Gauge* = ref object of Widget
  value*: float          ## 0.0 .. 1.0
  label*: string
  color*: Color          ## default color = auto green/yellow/red
  showPct*: bool

const gaugeEighths = ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]

method minSize*(g: Gauge, avail: Size): Size =
  size(g.label.runeLen + 10, 1)

method render*(g: Gauge, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.h < 1 or area.w < 2: return
  var x = area.x
  if g.label.len > 0:
    x += buf.write(x, area.y, g.label & " ", Style(), area.right - x)
  let v = clamp(g.value, 0.0, 1.0)
  var pct = ""
  if g.showPct:
    pct = " " & align($int(v * 100 + 0.5) & "%", 4)
  let barW = area.right - x - pct.runeLen
  if barW < 1: return
  let col =
    if g.color != defaultColor: g.color
    elif v < 0.6: clGreen
    elif v < 0.85: clYellow
    else: clRed
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
    discard buf.write(x + barW, area.y, pct, Style(), pct.runeLen)

proc gauge*(value: float; label = ""; color = defaultColor; showPct = true;
            width = flex(1); height = fixed(1)): Gauge =
  Gauge(value: value, label: label, color: color, showPct: showPct,
        widthSpec: width, heightSpec: height)

# ---- Sparkline ---------------------------------------------------------------

type Sparkline* = ref object of Widget
  data*: seq[float]
  color*: Color
  zeroBase*: bool   ## scale from 0 instead of min(data)

const sparkTicks = [" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

method minSize*(s: Sparkline, avail: Size): Size =
  size(min(s.data.len, max(avail.w, 0)), 1)

method render*(s: Sparkline, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty or s.data.len == 0: return
  let points = if s.data.len > area.w: s.data[^area.w .. ^1] else: s.data
  var lo = if s.zeroBase: 0.0 else: min(points)
  var hi = max(points)
  if hi <= lo: hi = lo + 1.0
  let st = Style(fg: s.color)
  let xoff = area.w - points.len   # right-align
  let levelMax = area.h * 8
  for i, v in points:
    let lvl = int((v - lo) / (hi - lo) * levelMax.float + 0.5)
    for row in 0 ..< area.h:
      # row 0 is the top; count eighths from the bottom row upward
      let fromBottom = area.h - 1 - row
      let cellLvl = clamp(lvl - fromBottom * 8, 0, 8)
      buf.put(area.x + xoff + i, area.y + row, sparkTicks[cellLvl], st)

proc sparkline*(data: seq[float]; color = clCyan; zeroBase = true;
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
    w = max(w, it.runeLen + 2)
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
      st.attrs.incl aReverse
      if ctx.focused != l: st.attrs.incl aDim
      prefix = "▸ "
    elif l.interactive:
      prefix = "  "
    var line = prefix & l.items[idx]
    line = clipRunes(line, area.w)
    if isSel:
      line = line & spaces(max(0, area.w - line.runeLen))
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
  of mPress:
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
    result[i] = h.runeLen
  for row in t.rows:
    for i, cell in row:
      if i < result.len:
        result[i] = max(result[i], cell.runeLen)

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
      discard buf.write(x, y, clipRunes(cell, w), st, area.right - x)
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
    lastOff: int   ## horizontal scroll offset from the last render

proc inputState*(initial = ""): InputState =
  InputState(text: signal(initial), cursor: signal(initial.runeLen))

method minSize*(i: Input, avail: Size): Size =
  size(max(i.state.text.peek.runeLen + 1, i.placeholder.runeLen), 1)

method render*(inp: Input, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  let focused = ctx.focused == inp
  let runes = inp.state.text.get.toRunes
  let cur = clamp(inp.state.cursor.get, 0, runes.len)
  let off = max(0, cur - area.w + 1)
  inp.lastOff = off
  if runes.len == 0 and inp.placeholder.len > 0:
    discard buf.write(area.x, area.y, inp.placeholder,
                      Style(fg: clBrightBlack, attrs: {aItalic}), area.w)
  else:
    let visible = runes[min(off, runes.len) .. ^1]
    discard buf.write(area.x, area.y, runesToStr(visible), inp.style, area.w)
  if focused:
    let cx = area.x + cur - off
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
  if m.kind != mPress or m.btn != mbLeft: return false
  let runes = inp.state.text.peek.toRunes
  inp.state.cursor.set clamp(inp.lastOff + (m.x - area.x), 0, runes.len)
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
  for l in t.labels: w += l.runeLen + 3
  size(w, 1)

method render*(t: Tabs, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  let active = clamp(t.active.get, 0, max(0, t.labels.high))
  let focused = ctx.focused == t
  var x = area.x
  for i, label in t.labels:
    var st = t.style
    if i == active:
      st.attrs.incl aReverse
      if not focused: st.attrs.incl aDim
    else:
      st.attrs.incl aDim
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
    let w = label.runeLen + 2   # " label " segment
    if m.x - area.x < x + w:
      t.active.set i
      return true
    x += w + 1                  # separator space
  false

proc tabs*(labels: seq[string]; active: Signal[int]; style = Style();
           autofocus = false; id = ""; width = flex(1); height = fixed(1)): Tabs =
  Tabs(labels: labels, active: active, style: style,
       widthSpec: width, heightSpec: height, focusable: true,
       autofocus: autofocus, id: id)

# ---- Spans (rich single-line text) ------------------------------------------

type
  Span* = tuple[text: string, style: Style]

  SpanLine* = ref object of Widget
    parts*: seq[Span]
    align*: Align

method minSize*(s: SpanLine, avail: Size): Size =
  var w = 0
  for p in s.parts: w += p.text.runeLen
  size(min(w, max(avail.w, 0)), 1)

method render*(s: SpanLine, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  var total = 0
  for p in s.parts: total += p.text.runeLen
  var x = case s.align
    of alLeft: area.x
    of alCenter: area.x + max(0, (area.w - total) div 2)
    of alRight: area.x + max(0, area.w - total)
  for p in s.parts:
    if x >= area.right: break
    x += buf.write(x, area.y, p.text, p.style, area.right - x)

proc spans*(parts: openArray[Span]; align = alLeft;
            width = flex(1); height = fixed(1)): SpanLine =
  ## One line of differently-styled fragments, e.g.
  ## `spans([("ok", style(fg = clGreen)), (" 34 checks", Style())])`.
  SpanLine(parts: @parts, align: align, widthSpec: width, heightSpec: height)
