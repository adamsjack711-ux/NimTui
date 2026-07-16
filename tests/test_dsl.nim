import std/[strutils, unittest]
import loom

suite "dsl":
  test "nesting builds the tree":
    let root = tui:
      vbox:
        text("a")
        hbox:
          text("b")
          text("c")
    check root of Box
    check root.children.len == 2
    check root.children[0] of Text
    check root.children[1] of Box
    check root.children[1].children.len == 2

  test "for loops emit one child per iteration":
    let root = tui:
      vbox:
        for i in 0 ..< 3:
          text($i)
    check root.children.len == 3
    check Text(root.children[2]).content == "2"

  test "if statements include or omit children":
    let cond = false
    let root = tui:
      vbox:
        text("always")
        if cond:
          text("never")
    check root.children.len == 1

  test "case statements select children":
    let mode = 1
    let root = tui:
      vbox:
        case mode
        of 0: text("zero")
        of 1: text("one")
        else: text("other")
    check root.children.len == 1
    check Text(root.children[0]).content == "one"

  test "let bindings pass through":
    let root = tui:
      vbox:
        let label = "hi"
        text(label)
    check Text(root.children[0]).content == "hi"

suite "widget rendering":
  test "panel with title and text":
    let root = tui:
      panel(title = "T", border = bkSingle):
        text("hi")
    let snap = renderToString(root, 8, 3)
    let lines = snap.split('\n')
    check lines[0] == "┌─ T ──┐"
    check lines[1] == "│hi    │"
    check lines[2] == "└──────┘"

  test "gauge renders filled bar and percentage":
    let g = gauge(0.5, width = fixed(14))
    let snap = renderToString(g, 14, 1)
    check "█" in snap
    check "50%" in snap

  test "sparkline maps values to ticks":
    let s = sparkline(@[0.0, 0.5, 1.0], zeroBase = true, width = fixed(3))
    let snap = renderToString(s, 3, 1)
    check "█" in snap
    check "▄" in snap

  test "list highlights the selected row":
    let sel = signal(1)
    let l = list(@["one", "two", "three"], sel)
    let snap = renderToString(l, 10, 3)
    let lines = snap.split('\n')
    check lines[0].startsWith("  one")
    check lines[1].startsWith("▸ two")

  test "list without selection tails its items":
    let l = list(@["1", "2", "3", "4"])
    let snap = renderToString(l, 5, 2)
    let lines = snap.split('\n')
    check lines[0].startsWith("3")
    check lines[1].startsWith("4")

  test "list keys move the selection":
    let sel = signal(0)
    let l = list(@["a", "b", "c"], sel)
    check l.handleKey(key(kDown))
    check sel.peek == 1
    check l.handleKey(key(kEnd))
    check sel.peek == 2
    check not l.handleKey(chKey("x"))

  test "table renders headers and rows":
    let t = table(@["NAME", "CPU"], @[@["nim", "42"], @["sh", "1"]])
    let snap = renderToString(t, 12, 3)
    let lines = snap.split('\n')
    check lines[0].startsWith("NAME")
    check "nim" in lines[1]
    check "42" in lines[1]

  test "input editing via keys":
    let st = inputState("ab")
    let inp = input(st)
    check inp.handleKey(chKey("c"))
    check st.text.peek == "abc"
    check inp.handleKey(key(kBackspace))
    check st.text.peek == "ab"
    check inp.handleKey(key(kHome))
    check inp.handleKey(chKey("x"))
    check st.text.peek == "xab"

  test "tabs switch with arrow keys":
    let active = signal(0)
    let t = tabs(@["one", "two"], active)
    check t.handleKey(key(kRight))
    check active.peek == 1
    check t.handleKey(key(kRight))
    check active.peek == 0

  test "text wrapping":
    let t = text("aaa bbb ccc", wrap = true, width = fixed(7))
    let snap = renderToString(t, 7, 2)
    let lines = snap.split('\n')
    check lines[0].startsWith("aaa bbb")
    check lines[1].startsWith("ccc")
