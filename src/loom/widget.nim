## Widget base type, size specs, and the flex container (`Box`) that
## implements the layout engine.

import geometry, style, buffer, events

type
  SizeSpecKind* = enum
    skAuto, skFixed, skFlex

  SizeSpec* = object
    kind*: SizeSpecKind
    value*: int   ## cells for skFixed, weight for skFlex

  Widget* = ref object of RootObj
    widthSpec*: SizeSpec
    heightSpec*: SizeSpec
    children*: seq[Widget]
    focusable*: bool

  RenderCtx* = object
    focused*: Widget

proc fixed*(n: int): SizeSpec = SizeSpec(kind: skFixed, value: n)
proc flex*(weight = 1): SizeSpec = SizeSpec(kind: skFlex, value: weight)
proc fit*(): SizeSpec = SizeSpec(kind: skAuto)

method minSize*(w: Widget, avail: Size): Size {.base.} = size(0, 0)

method render*(w: Widget, buf: var Buffer, area: Rect, ctx: RenderCtx) {.base.} =
  discard

method handleKey*(w: Widget, k: Key): bool {.base.} = false

method add*(w: Widget, child: Widget) {.base.} =
  raise newException(ValueError, "this widget is not a container")

proc collectFocusable*(w: Widget, acc: var seq[Widget]) =
  if w.focusable: acc.add w
  for c in w.children:
    collectFocusable(c, acc)

# ---- Box: the flex container ----------------------------------------------

type
  Dir* = enum
    dirH, dirV

  Box* = ref object of Widget
    dir*: Dir
    gap*: int
    padding*: int
    border*: BorderKind
    title*: string
    style*: Style
    titleStyle*: Style

method add*(b: Box, child: Widget) =
  b.children.add child

proc mainSpec(b: Box, c: Widget): SizeSpec =
  if b.dir == dirH: c.widthSpec else: c.heightSpec

proc crossSpec(b: Box, c: Widget): SizeSpec =
  if b.dir == dirH: c.heightSpec else: c.widthSpec

proc chrome(b: Box): int =
  (if b.border != bkNone: 2 else: 0) + b.padding * 2

proc innerRect*(b: Box, area: Rect): Rect =
  var r = area
  if b.border != bkNone: r = r.shrink(1)
  if b.padding > 0: r = r.shrink(b.padding)
  r

method minSize*(b: Box, avail: Size): Size =
  let ch = b.chrome
  let innerAvail = size(max(0, avail.w - ch), max(0, avail.h - ch))
  var main = 0
  var cross = 0
  for i, c in b.children:
    if i > 0: main += b.gap
    let m = c.minSize(innerAvail)
    let spec = b.mainSpec(c)
    main += (if spec.kind == skFixed: spec.value
             elif b.dir == dirH: m.w
             else: m.h)
    cross = max(cross, if b.dir == dirH: m.h else: m.w)
  if b.dir == dirH:
    size(main + ch, cross + ch)
  else:
    size(cross + ch, main + ch)

proc layout*(b: Box, inner: Rect): seq[Rect] =
  ## Solve child rectangles inside `inner`: fixed sizes first, then
  ## content-measured autos, then remaining space split by flex weight.
  let n = b.children.len
  if n == 0: return
  let mainTotal = if b.dir == dirH: inner.w else: inner.h
  var mains = newSeq[int](n)
  var flexIdx: seq[int]
  var used = b.gap * (n - 1)
  for i, c in b.children:
    let spec = b.mainSpec(c)
    case spec.kind
    of skFixed:
      mains[i] = max(0, spec.value)
      used += mains[i]
    of skAuto:
      let m = c.minSize(size(inner.w, inner.h))
      mains[i] = if b.dir == dirH: m.w else: m.h
      used += mains[i]
    of skFlex:
      flexIdx.add i
  var remaining = max(0, mainTotal - used)
  var totalWeight = 0
  for i in flexIdx:
    totalWeight += max(1, b.mainSpec(b.children[i]).value)
  var given = 0
  for i in flexIdx:
    mains[i] = remaining * max(1, b.mainSpec(b.children[i]).value) div max(1, totalWeight)
    given += mains[i]
  var leftover = remaining - given
  for i in flexIdx:
    if leftover <= 0: break
    inc mains[i]
    dec leftover
  var pos = 0
  for i, c in b.children:
    let crossFull = if b.dir == dirH: inner.h else: inner.w
    let cs = b.crossSpec(c)
    let crossLen = if cs.kind == skFixed: min(cs.value, crossFull) else: crossFull
    if b.dir == dirH:
      result.add rect(inner.x + pos, inner.y, mains[i], crossLen)
    else:
      result.add rect(inner.x, inner.y + pos, crossLen, mains[i])
    pos += mains[i] + b.gap

method render*(b: Box, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  if area.isEmpty: return
  if b.style != Style():
    fillRect(buf, area, " ", b.style)
  if b.border != bkNone:
    drawBorder(buf, area, b.border, b.style)
    if b.title.len > 0 and area.w > 4:
      discard buf.write(area.x + 2, area.y, " " & b.title & " ",
                        b.titleStyle, area.w - 4)
  let inr = b.innerRect(area)
  if inr.isEmpty: return
  let rects = b.layout(inr)
  for i, r in rects:
    let clipped = intersect(r, inr)
    if not clipped.isEmpty:
      b.children[i].render(buf, clipped, ctx)

proc newBox*(dir: Dir; gap = 0; padding = 0; border = bkNone; title = "";
             width = flex(1); height = flex(1); style = Style()): Box =
  Box(dir: dir, gap: gap, padding: padding, border: border, title: title,
      widthSpec: width, heightSpec: height, style: style,
      titleStyle: Style(fg: style.fg, bg: style.bg, attrs: {aBold}))

proc vbox*(gap = 0; padding = 0; border = bkNone; title = "";
           width = flex(1); height = flex(1); style = Style()): Box =
  newBox(dirV, gap, padding, border, title, width, height, style)

proc hbox*(gap = 0; padding = 0; border = bkNone; title = "";
           width = flex(1); height = flex(1); style = Style()): Box =
  newBox(dirH, gap, padding, border, title, width, height, style)

proc panel*(title = ""; border = bkRounded; gap = 0; padding = 0;
            width = flex(1); height = flex(1); style = Style()): Box =
  ## A bordered vertical box — the standard dashboard building block.
  newBox(dirV, gap, padding, border, title, width, height, style)

proc spacer*(width = flex(1), height = flex(1)): Widget =
  ## Empty flexible space; pushes siblings apart.
  Widget(widthSpec: width, heightSpec: height)
