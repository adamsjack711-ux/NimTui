import std/[strutils, unittest]
import loom

suite "buffer":
  test "new buffer is blank":
    let b = newBuffer(4, 2)
    check b.dump == "    \n    "

  test "write clips at the right edge":
    var b = newBuffer(6, 1)
    let n = b.write(4, 0, "hello")
    check n == 2
    check b.dump == "    he"

  test "write respects maxW":
    var b = newBuffer(10, 1)
    discard b.write(0, 0, "hello", Style(), 3)
    check b.dump == "hel       "

  test "write stops at newline":
    var b = newBuffer(10, 1)
    discard b.write(0, 0, "ab\ncd")
    check b.dump == "ab        "

  test "out-of-bounds put is a no-op":
    var b = newBuffer(2, 2)
    b.put(-1, 0, "x")
    b.put(5, 5, "x")
    check b.dump == "  \n  "

  test "unicode runes occupy one cell each":
    var b = newBuffer(4, 1)
    discard b.write(0, 0, "héllo")
    check b.dump == "héll"

  test "border drawing":
    var b = newBuffer(6, 3)
    b.drawBorder(rect(0, 0, 6, 3), bkSingle)
    check b.dump == "┌────┐\n│    │\n└────┘"

  test "diff of identical buffers is empty":
    var a = newBuffer(4, 2)
    var b = newBuffer(4, 2)
    discard a.write(0, 0, "hi")
    discard b.write(0, 0, "hi")
    check diffToAnsi(a, b) == ""

  test "diff addresses only the changed cell":
    var a = newBuffer(4, 2)
    var b = newBuffer(4, 2)
    discard b.write(2, 1, "x")
    let d = diffToAnsi(a, b)
    check "\e[2;3H" in d
    check "x" in d
    check "\e[1;1H" notin d

  test "dimension change forces full clear":
    let a = newBuffer(2, 2)
    let b = newBuffer(4, 2)
    check "\e[2J" in diffToAnsi(a, b)
