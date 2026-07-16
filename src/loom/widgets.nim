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

proc rule*(style = Style(fg: Color(kind: ckAnsi, idx: 8))): Rule =
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
  selected*: Signal[int]   ## nil = non-interactive log view (tails output)
  style*: Style
  lastH: int               ## viewport height from the last render (page keys)

method minSize*(l: List, avail: Size): Size =
  var w = 0
  for it in l.items:
    w = max(w, it.runeLen + 2)
  size(min(w, max(avail.w, 0)), l.items.len)

method render*(l: List, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  l.lastH = area.h
  var sel = -1
  var off = 0
  if l.selected != nil:
    sel = clamp(l.selected.get, 0, max(0, l.items.high))
    if sel >= area.h: off = sel - area.h + 1
  elif l.items.len > area.h:
    off = l.items.len - area.h   # follow the tail
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
    elif sel >= 0:
      prefix = "  "
    var line = prefix & l.items[idx]
    line = clipRunes(line, area.w)
    if isSel:
      line = line & spaces(max(0, area.w - line.runeLen))
    discard buf.write(area.x, area.y + row, line, st, area.w)

method handleKey*(l: List, k: Key): bool =
  if l.selected == nil or l.items.len == 0: return false
  var s = clamp(l.selected.peek, 0, l.items.high)
  let page = max(1, l.lastH)
  case k.kind
  of kUp: s = max(0, s - 1)
  of kDown: s = min(l.items.high, s + 1)
  of kHome: s = 0
  of kEnd: s = l.items.high
  of kPageUp: s = max(0, s - page)
  of kPageDown: s = min(l.items.high, s + page)
  else: return false
  l.selected.set s
  true

proc list*(items: seq[string]; selected: Signal[int] = nil; style = Style();
           width = flex(1); height = flex(1)): List =
  List(items: items, selected: selected, style: style,
       widthSpec: width, heightSpec: height,
       focusable: selected != nil)

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
    cursor*: int   ## rune index

  Input* = ref object of Widget
    state*: InputState
    placeholder*: string
    style*: Style

proc inputState*(initial = ""): InputState =
  InputState(text: signal(initial), cursor: initial.runeLen)

method minSize*(i: Input, avail: Size): Size =
  size(max(i.state.text.peek.runeLen + 1, i.placeholder.runeLen), 1)

method render*(inp: Input, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  let focused = ctx.focused == inp
  let runes = inp.state.text.get.toRunes
  let cur = clamp(inp.state.cursor, 0, runes.len)
  if runes.len == 0 and inp.placeholder.len > 0:
    discard buf.write(area.x, area.y, inp.placeholder,
                      Style(fg: clBrightBlack, attrs: {aItalic}), area.w)
  else:
    let off = max(0, cur - area.w + 1)
    let visible = runes[min(off, runes.len) .. ^1]
    discard buf.write(area.x, area.y, runesToStr(visible), inp.style, area.w)
  if focused:
    let cx = area.x + min(cur, area.w - 1) - (if cur >= area.w: cur - area.w + 1 else: 0)
    var cell = buf[cx, area.y]
    cell.style.attrs.incl aReverse
    buf[cx, area.y] = cell

method handleKey*(inp: Input, k: Key): bool =
  var runes = inp.state.text.peek.toRunes
  var cur = clamp(inp.state.cursor, 0, runes.len)
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
  inp.state.cursor = cur
  inp.state.text.set runesToStr(runes)
  true

proc input*(state: InputState; placeholder = ""; style = Style();
            width = flex(1); height = fixed(1)): Input =
  Input(state: state, placeholder: placeholder, style: style,
        widthSpec: width, heightSpec: height, focusable: true)

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

proc tabs*(labels: seq[string]; active: Signal[int]; style = Style();
           width = flex(1); height = fixed(1)): Tabs =
  Tabs(labels: labels, active: active, style: style,
       widthSpec: width, heightSpec: height, focusable: true)
