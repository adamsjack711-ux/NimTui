import std/[options, os, strutils, unittest]
import loom

suite "viewport":
  proc tenLines(): Widget =
    var s: seq[string]
    for i in 1 .. 10: s.add "line" & $i
    text(s.join("\n"), height = fit())

  test "windows tall content and shows a scrollbar":
    let sc = signal(0)
    let v = viewport(tenLines(), sc)
    let snap = renderToString(v, 12, 3)
    let lines = snap.split('\n')
    check lines[0].startsWith("line1")
    check lines[2].startsWith("line3")
    check "┃" in snap or "│" in snap   # scrollbar present

  test "scroll offset moves the window":
    let sc = signal(5)
    let v = viewport(tenLines(), sc)
    let snap = renderToString(v, 12, 3)
    check snap.split('\n')[0].startsWith("line6")

  test "keys and wheel adjust the scroll signal":
    let sc = signal(0)
    let v = viewport(tenLines(), sc)
    discard renderToString(v, 12, 3)   # records content/viewport heights
    check v.handleKey(key(kPageDown))
    check sc.peek == 3
    check v.handleKey(key(kEnd))
    check sc.peek == 7                 # 10 lines - 3 visible
    check v.handleMouse(Mouse(kind: mWheelUp, x: 0, y: 0), rect(0, 0, 12, 3))
    check sc.peek == 4

  test "content widgets are not focusable through the viewport":
    let sc = signal(0)
    let inner = input(inputState())
    let v = viewport(inner, sc)
    var acc: seq[Widget]
    collectFocusable(v, acc)
    check acc == @[Widget(v)]

suite "themes":
  test "theme switch restyles borders reactively":
    let root = tui:
      panel(title = "T", border = bkSingle):
        text("hi")
    setTheme(themeNeon)
    var buf = newBuffer(8, 3)
    root.render(buf, rect(0, 0, 8, 3), RenderCtx())
    check buf[0, 0].style.fg == themeNeon.border.fg
    setTheme(themeDefault)
    var buf2 = newBuffer(8, 3)
    root.render(buf2, rect(0, 0, 8, 3), RenderCtx())
    check buf2[0, 0].style.fg == defaultColor

  test "explicit style beats the theme":
    setTheme(themeNeon)
    let root = tui:
      panel(border = bkSingle, style = style(fg = clRed)):
        text("hi")
    var buf = newBuffer(8, 3)
    root.render(buf, rect(0, 0, 8, 3), RenderCtx())
    check buf[0, 0].style.fg == clRed
    setTheme(themeDefault)

  test "theme changes are signal-tracked":
    var runs = 0
    effect(proc () =
      discard theme()
      inc runs)
    setTheme(themeMono)
    check runs == 2
    setTheme(themeDefault)

suite "wrapped spans":
  test "fragments flow across lines":
    let s = spans([("aaa bbb", style(fg = clGreen)), (" ccc", Style())],
                  wrap = true)
    let snap = renderToString(s, 7, 2)
    let lines = snap.split('\n')
    check lines[0].startsWith("aaa bbb")
    check lines[1].startsWith("ccc")

  test "styles survive the wrap":
    let s = spans([("aa", style(attrs = {aBold})), (" bb", Style())],
                  wrap = true)
    var buf = newBuffer(2, 2)
    s.render(buf, rect(0, 0, 2, 2), RenderCtx())
    check attrMap(buf, aBold) == "##\n.."

  test "minSize reports wrapped height":
    let s = spans([("one two three", Style())], wrap = true)
    check s.minSize(size(5, 10)).h == 3

  test "spaceless fragment boundaries stay glued":
    # styled text directly followed by punctuation must not grow a space
    let s = spans([("see ", Style()), ("code", style(attrs = {aBold})),
                   (") after", Style())], wrap = true)
    let snap = renderToString(s, 20, 1)
    check snap.startsWith("see code) after")

  test "a glued word wraps as one unit":
    let s = spans([("aaaa", style(attrs = {aBold})), ("bb cc", Style())],
                  wrap = true)
    # "aaaabb" (6 wide) can't fit in 5 columns next to nothing — it is one
    # word, so "cc" starts the next line
    check s.minSize(size(6, 10)).h == 2

suite "drag":
  test "SGR motion-with-button parses as drag":
    feedInput "\e[<32;4;2M"
    let e = pollEvent(0).get
    check e.kind == ekMouse
    check e.mouse.kind == mDrag
    check e.mouse.btn == mbLeft
    check e.mouse.x == 3 and e.mouse.y == 1

  test "dragging over a list moves the selection":
    let sel = signal(0)
    let l = list(@["a", "b", "c"], sel)
    discard renderToString(l, 10, 3)
    check l.handleMouse(Mouse(kind: mDrag, btn: mbLeft, x: 1, y: 2),
                        rect(0, 0, 10, 3))
    check sel.peek == 2

suite "async offload":
  test "execAsync delivers subprocess output on the loop":
    proc emptyView(): Widget =
      tui:
        vbox:
          text("x")
    let app = newApp(emptyView)
    var got = ""
    app.execAsync("sh", @["-c", "printf hello"], proc (s: string) =
      got = s)
    for _ in 0 ..< 200:
      app.pollJobs()
      if got.len > 0: break
      sleep(10)
    check got == "hello"

  test "output larger than one pipe buffer arrives complete":
    proc emptyView(): Widget =
      tui:
        vbox:
          text("x")
    let app = newApp(emptyView)
    var got = ""
    app.execAsync("sh", @["-c", "yes x | head -20000"], proc (s: string) =
      got = s)
    for _ in 0 ..< 500:
      app.pollJobs()
      if got.len > 0: break
      sleep(10)
    check got.countLines >= 20000
