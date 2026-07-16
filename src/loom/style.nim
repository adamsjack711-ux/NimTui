## Colors and text attributes, rendered to ANSI SGR escape sequences.

type
  ColorKind* = enum
    ckDefault, ckAnsi, ckC256, ckRgb

  Color* = object
    kind*: ColorKind
    idx*: uint8         ## ANSI 0-15 or 256-palette index
    r*, g*, b*: uint8   ## truecolor components

  Attr* = enum
    aBold, aDim, aItalic, aUnderline, aReverse, aStrike

  Style* = object
    fg*, bg*: Color
    attrs*: set[Attr]

proc `==`*(a, b: Color): bool =
  if a.kind != b.kind: return false
  case a.kind
  of ckDefault: true
  of ckAnsi, ckC256: a.idx == b.idx
  of ckRgb: a.r == b.r and a.g == b.g and a.b == b.b

proc `==`*(a, b: Style): bool =
  a.fg == b.fg and a.bg == b.bg and a.attrs == b.attrs

const
  defaultColor* = Color(kind: ckDefault)
  clBlack* = Color(kind: ckAnsi, idx: 0)
  clRed* = Color(kind: ckAnsi, idx: 1)
  clGreen* = Color(kind: ckAnsi, idx: 2)
  clYellow* = Color(kind: ckAnsi, idx: 3)
  clBlue* = Color(kind: ckAnsi, idx: 4)
  clMagenta* = Color(kind: ckAnsi, idx: 5)
  clCyan* = Color(kind: ckAnsi, idx: 6)
  clWhite* = Color(kind: ckAnsi, idx: 7)
  clBrightBlack* = Color(kind: ckAnsi, idx: 8)
  clBrightRed* = Color(kind: ckAnsi, idx: 9)
  clBrightGreen* = Color(kind: ckAnsi, idx: 10)
  clBrightYellow* = Color(kind: ckAnsi, idx: 11)
  clBrightBlue* = Color(kind: ckAnsi, idx: 12)
  clBrightMagenta* = Color(kind: ckAnsi, idx: 13)
  clBrightCyan* = Color(kind: ckAnsi, idx: 14)
  clBrightWhite* = Color(kind: ckAnsi, idx: 15)

proc ansi*(n: range[0 .. 15]): Color = Color(kind: ckAnsi, idx: n.uint8)
proc c256*(n: uint8): Color = Color(kind: ckC256, idx: n)
proc rgb*(r, g, b: uint8): Color = Color(kind: ckRgb, r: r, g: g, b: b)

proc style*(fg = defaultColor, bg = defaultColor, attrs: set[Attr] = {}): Style =
  Style(fg: fg, bg: bg, attrs: attrs)

const attrCodes: array[Attr, string] = ["1", "2", "3", "4", "7", "9"]

proc colorCode(c: Color, isBg: bool): string =
  case c.kind
  of ckDefault:
    if isBg: "49" else: "39"
  of ckAnsi:
    let n = c.idx.int
    if n < 8:
      $(if isBg: 40 + n else: 30 + n)
    else:
      $(if isBg: 100 + n - 8 else: 90 + n - 8)
  of ckC256:
    (if isBg: "48;5;" else: "38;5;") & $c.idx
  of ckRgb:
    (if isBg: "48;2;" else: "38;2;") & $c.r & ";" & $c.g & ";" & $c.b

proc sgr*(s: Style): string =
  ## Full reset-and-set sequence for this style.
  result = "\e[0"
  for a in Attr:
    if a in s.attrs:
      result.add ";"
      result.add attrCodes[a]
  result.add ";"
  result.add colorCode(s.fg, false)
  result.add ";"
  result.add colorCode(s.bg, true)
  result.add "m"
