import std/unittest
import loom

# A probe records the area it was given, so layout math is directly testable.
type Probe = ref object of Widget
  got: Rect

method render(p: Probe, buf: var Buffer, area: Rect, ctx: RenderCtx) =
  p.got = area

proc probe(width = flex(1), height = flex(1)): Probe =
  Probe(widthSpec: width, heightSpec: height)

proc renderInto(w: Widget, width, height: int) =
  var buf = newBuffer(width, height)
  w.render(buf, rect(0, 0, width, height), RenderCtx())

suite "layout":
  test "vbox splits fixed then flex by weight":
    let a = probe(height = fixed(2))
    let b = probe(height = flex(1))
    let c = probe(height = flex(2))
    let root = vbox()
    root.add a
    root.add b
    root.add c
    renderInto(root, 10, 20)
    check a.got == rect(0, 0, 10, 2)
    check b.got == rect(0, 2, 10, 6)
    check c.got == rect(0, 8, 10, 12)

  test "hbox with gap":
    let a = probe(width = fixed(4))
    let b = probe(width = flex(1))
    let root = hbox(gap = 2)
    root.add a
    root.add b
    renderInto(root, 12, 3)
    check a.got == rect(0, 0, 4, 3)
    check b.got == rect(6, 0, 6, 3)

  test "border and padding shrink the inner area":
    let a = probe()
    let root = panel(padding = 1)
    root.add a
    renderInto(root, 10, 8)
    # 1 border + 1 padding on each side
    check a.got == rect(2, 2, 6, 4)

  test "auto height measures content":
    let t = text("a\nb\nc", height = fit())
    let rest = probe()
    let root = vbox()
    root.add t
    root.add rest
    renderInto(root, 10, 10)
    check rest.got == rect(0, 3, 10, 7)

  test "flex remainder cells go to the first flex children":
    let a = probe(height = flex(1))
    let b = probe(height = flex(1))
    let c = probe(height = flex(1))
    let root = vbox()
    root.add a
    root.add b
    root.add c
    renderInto(root, 5, 10)   # 10 / 3 -> 4, 3, 3
    check a.got.h == 4
    check b.got.h == 3
    check c.got.h == 3

  test "fixed cross-axis size is respected":
    let a = probe(width = fixed(3), height = flex(1))
    let root = vbox()
    root.add a
    renderInto(root, 10, 5)
    check a.got == rect(0, 0, 3, 5)

  test "overflowing children are clipped, not crashed":
    let a = probe(height = fixed(100))
    let root = vbox()
    root.add a
    renderInto(root, 5, 5)
    check a.got.h <= 5
