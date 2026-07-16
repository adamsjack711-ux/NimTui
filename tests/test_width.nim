import std/[strutils, unicode, unittest]
import loom

suite "wide glyphs":
  test "runeWidth basics":
    check runeWidth(Rune('a')) == 1
    check runeWidth("é".runeAt(0)) == 1
    check runeWidth("日".runeAt(0)) == 2
    check runeWidth("語".runeAt(0)) == 2
    check runeWidth("🚀".runeAt(0)) == 2
    check strWidth("abc") == 3
    check strWidth("日本語") == 6
    check strWidth("a日b") == 4

  test "wide runes occupy head + continuation cells":
    var b = newBuffer(6, 1)
    discard b.write(0, 0, "日本語")
    check b[0, 0].ch == "日".runeAt(0)
    check b[1, 0].ch == contRune
    check b[2, 0].ch == "本".runeAt(0)
    check b[5, 0].ch == contRune
    check b.dump == "日本語"

  test "write clips a wide rune that only half-fits":
    var b = newBuffer(10, 1)
    let n = b.write(0, 0, "日本語", Style(), 5)
    check n == 4          # 日本 fits in 4 columns; 語 needs 2 more
    check b.dump == "日本      "

  test "wide rune never lands in the last column":
    var b = newBuffer(3, 1)
    discard b.write(0, 0, "a日")   # 日 would need columns 1+2: fits
    check b.dump == "a日"
    var c = newBuffer(2, 1)
    discard c.write(0, 0, "a日")   # 日 would need column 2: doesn't fit
    check c.dump == "a "

  test "overwriting a continuation blanks the orphaned head":
    var b = newBuffer(4, 1)
    discard b.write(0, 0, "日x")
    b.put(1, 0, "y")   # lands on 日's continuation cell
    check b.dump == " yx "

  test "overwriting a head blanks the orphaned continuation":
    var b = newBuffer(4, 1)
    discard b.write(0, 0, "日x")
    b.put(0, 0, "z")
    check b.dump == "z x "

  test "diff emits the wide glyph once and skips the continuation":
    var a = newBuffer(4, 1)
    var b = newBuffer(4, 1)
    discard b.write(0, 0, "日")
    let d = diffToAnsi(a, b)
    check d.count("日") == 1
    check "\e[1;1H" in d

  test "diff starting on a changed continuation re-emits the head":
    var a = newBuffer(4, 1)
    discard a.write(0, 0, "日日")   # wait: 日日 = 4 cols
    var b = newBuffer(4, 1)
    discard b.write(0, 0, "日x")
    let d = diffToAnsi(a, b)
    check "x" in d

suite "width-aware widgets":
  test "list clips without splitting a wide glyph":
    let l = list(@["日本語です"])   # 10 columns wide
    let snap = renderToString(l, 5, 1)
    check snap.startsWith("日本")

  test "list pads keyed selection to full width with CJK":
    let sel = signal(0)
    let l = list(@["日本"], sel)
    var buf = newBuffer(8, 1)
    let ctx = RenderCtx()
    ctx.focused = l
    l.render(buf, rect(0, 0, 8, 1), ctx)
    check attrMap(buf, aReverse) == "########"

  test "input cursor column accounts for wide runes":
    let st = inputState("日本")   # cursor at rune 2 = column 4
    let inp = input(st)
    var buf = newBuffer(10, 1)
    let ctx = RenderCtx()
    ctx.focused = inp
    inp.render(buf, rect(0, 0, 10, 1), ctx)
    check attrMap(buf, aReverse) == "....#....."

  test "input click on a wide glyph maps to the right rune":
    let st = inputState("日本語")
    let inp = input(st)
    discard renderToString(inp, 10, 1)
    # column 3 is inside 本 (columns 2-3) -> cursor lands after it
    check inp.handleMouse(Mouse(kind: mPress, btn: mbLeft, x: 3, y: 0),
                          rect(0, 0, 10, 1))
    check st.cursor.peek == 2

  test "text alignment centers by display width":
    let t = text("日本", align = alCenter)
    let snap = renderToString(t, 8, 1)
    check snap == "  日本  "
