import std/[options, unittest]
import loom

# feedInput injects bytes into the input queue, so pollEvent(0) parses
# them without touching the real terminal.

suite "key parsing":
  test "plain char":
    feedInput "a"
    check pollEvent(0).get.key.isChar("a")

  test "arrow keys":
    feedInput "\e[A\e[B\e[C\e[D"
    check pollEvent(0).get.key.kind == kUp
    check pollEvent(0).get.key.kind == kDown
    check pollEvent(0).get.key.kind == kRight
    check pollEvent(0).get.key.kind == kLeft

  test "ctrl chord":
    feedInput "\x03"
    check pollEvent(0).get.key == chKey("c", ctrl = true)

  test "alt chord":
    feedInput "\eb"
    check pollEvent(0).get.key == chKey("b", alt = true)

  test "utf8 multi-byte char":
    feedInput "é"
    check pollEvent(0).get.key.ch == "é"

  test "enter, tab, backspace, shift-tab":
    feedInput "\r\t\x7f\e[Z"
    check pollEvent(0).get.key.kind == kEnter
    check pollEvent(0).get.key.kind == kTab
    check pollEvent(0).get.key.kind == kBackspace
    check pollEvent(0).get.key.kind == kBackTab

  test "tilde sequences":
    feedInput "\e[5~\e[6~\e[3~"
    check pollEvent(0).get.key.kind == kPageUp
    check pollEvent(0).get.key.kind == kPageDown
    check pollEvent(0).get.key.kind == kDelete

suite "mouse parsing":
  test "SGR left press and release":
    feedInput "\e[<0;5;3M"
    let e = pollEvent(0).get
    check e.kind == ekMouse
    check e.mouse.kind == mPress
    check e.mouse.btn == mbLeft
    check e.mouse.x == 4
    check e.mouse.y == 2
    feedInput "\e[<0;5;3m"
    check pollEvent(0).get.mouse.kind == mRelease

  test "wheel up and down":
    feedInput "\e[<64;2;2M\e[<65;2;2M"
    check pollEvent(0).get.mouse.kind == mWheelUp
    check pollEvent(0).get.mouse.kind == mWheelDown

  test "right button":
    feedInput "\e[<2;1;1M"
    check pollEvent(0).get.mouse.btn == mbRight

suite "mouse on widgets":
  test "click selects a list row":
    let sel = signal(0)
    let l = list(@["a", "b", "c"], sel)
    discard renderToString(l, 10, 3)   # records scroll offset
    check l.handleMouse(Mouse(kind: mPress, btn: mbLeft, x: 3, y: 2),
                        rect(0, 0, 10, 3))
    check sel.peek == 2

  test "click below the last row is ignored":
    let sel = signal(0)
    let l = list(@["a"], sel)
    discard renderToString(l, 10, 5)
    check not l.handleMouse(Mouse(kind: mPress, btn: mbLeft, x: 0, y: 4),
                            rect(0, 0, 10, 5))
    check sel.peek == 0

  test "wheel moves the selection":
    let sel = signal(1)
    let l = list(@["a", "b", "c"], sel)
    check l.handleMouse(Mouse(kind: mWheelUp, x: 0, y: 0), rect(0, 0, 10, 3))
    check sel.peek == 0
    check l.handleMouse(Mouse(kind: mWheelDown, x: 0, y: 0), rect(0, 0, 10, 3))
    check sel.peek == 1

  test "click switches tabs":
    let active = signal(0)
    let t = tabs(@["one", "two"], active)
    # " one  two " — "two" segment starts at x 6
    check t.handleMouse(Mouse(kind: mPress, btn: mbLeft, x: 7, y: 0),
                        rect(0, 0, 20, 1))
    check active.peek == 1

  test "click places the input cursor":
    let st = inputState("hello")
    let inp = input(st)
    discard renderToString(inp, 10, 1)
    check inp.handleMouse(Mouse(kind: mPress, btn: mbLeft, x: 2, y: 0),
                          rect(0, 0, 10, 1))
    check st.cursor == 2

suite "autofocus":
  test "constructors carry the flag":
    check input(inputState(), autofocus = true).autofocus
    check list(@["x"], signal(0), autofocus = true).autofocus
    check not tabs(@["a"], signal(0)).autofocus
