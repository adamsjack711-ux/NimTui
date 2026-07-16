import std/[strutils, unittest]
import loom

# The app loop is testable headlessly: renderFrame builds/lays out/renders
# without a terminal, and processEvent drives dispatch directly.

var
  active = signal(0)
  st = inputState()
  sel = signal(0)
  showExtra = signal(false)
  extraSt = inputState()

proc view(): Widget =
  tui:
    vbox:
      tabs(@["a", "b"], active, id = "tabbar", height = fixed(1))
      input(st, autofocus = true, id = "main-input", height = fixed(1))
      if showExtra.get:
        input(extraSt, id = "extra", height = fixed(1))
      list(@["one", "two", "three"], sel, id = "list", height = fixed(3))

proc freshApp(): App =
  showExtra.set false
  st.text.set ""
  st.cursor.set 0
  sel.set 0
  result = newApp(view)
  discard result.renderFrame(40, 8)

suite "app loop":
  test "autofocus picks the flagged widget":
    let app = freshApp()
    check app.focused != nil
    check app.focused.id == "main-input"

  test "tab cycles focus in tree order and wraps":
    let app = freshApp()
    app.processEvent keyEvent(key(kTab))
    check app.focused.id == "list"
    app.processEvent keyEvent(key(kTab))
    check app.focused.id == "tabbar"
    app.processEvent keyEvent(key(kBackTab))
    check app.focused.id == "list"

  test "focused widget consumes keys before the global handler":
    let app = freshApp()
    var sawGlobal: seq[string]
    app.onKey(proc (k: Key): bool =
      sawGlobal.add $k
      true)
    app.processEvent keyEvent(chKey("x"))   # input takes it
    check st.text.peek == "x"
    check sawGlobal.len == 0
    app.processEvent keyEvent(key(kUp))     # input declines -> global
    check sawGlobal == @["↑"]

  test "focus follows widget id when the tree changes shape":
    let app = freshApp()
    app.processEvent keyEvent(key(kTab))    # focus the list
    check app.focused.id == "list"
    showExtra.set true                      # inserts a focusable before it
    discard app.renderFrame(40, 8)
    check app.focused.id == "list"

  test "ctrl-c quits":
    let app = freshApp()
    check app.isRunning
    app.processEvent keyEvent(chKey("c", ctrl = true))
    check not app.isRunning

  test "mouse click focuses the widget under the cursor and selects":
    let app = freshApp()
    # rows: tabbar y0, input y1, list y2..4
    app.processEvent mouseEvent(mPress, mbLeft, 2, 3)
    check app.focused.id == "list"
    check sel.peek == 1
    let buf = app.renderFrame(40, 8)
    check attrMap(buf, aReverse).splitLines[3][0] == '#'

  test "paste lands in the focused input, sanitized":
    let app = freshApp()
    app.processEvent pasteEvent("a\tb\nc")
    check st.text.peek == "a b c"

  test "unfocusable views clamp focus without crashing":
    proc emptyView(): Widget =
      tui:
        vbox:
          text("empty")
    let app = newApp(emptyView)
    discard app.renderFrame(20, 4)
    check app.focused == nil
    app.processEvent keyEvent(key(kTab))
    app.processEvent mouseEvent(mPress, mbLeft, 1, 1)

var
  items = signal(@["alpha", "beta", "gamma"])
  keys = signal(@["a", "b", "g"])
  selKey = signal("")

proc keyedView(): Widget =
  tui:
    vbox:
      list(items.get, selKey, keys = keys.get, id = "kl", height = fixed(3))

suite "keyed selection":
  test "selection follows the key through reorders":
    let app = newApp(keyedView)
    discard app.renderFrame(20, 3)
    app.processEvent keyEvent(key(kDown))   # -1 -> 0 -> down -> index 1
    check selKey.peek == "b"
    # re-sort: beta moves to the top
    items.set @["beta", "gamma", "alpha"]
    keys.set @["b", "g", "a"]
    let buf = app.renderFrame(20, 3)
    check selKey.peek == "b"
    check attrMap(buf, aReverse).splitLines[0][0] == '#'
    check attrMap(buf, aReverse).splitLines[1][0] == '.'

  test "missing key means no highlighted row":
    selKey.set "zz"
    let app = newApp(keyedView)
    let buf = app.renderFrame(20, 3)
    check '#' notin attrMap(buf, aReverse)
