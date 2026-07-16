## Input event types, decoupled from the terminal backend so the widget
## layer stays headless-testable.

type
  KeyKind* = enum
    kNone, kChar, kEnter, kEsc, kBackspace, kTab, kBackTab,
    kUp, kDown, kLeft, kRight, kHome, kEnd, kPageUp, kPageDown,
    kInsert, kDelete, kFn

  Key* = object
    kind*: KeyKind
    ch*: string   ## UTF-8 text for kChar (single grapheme)
    ctrl*: bool
    alt*: bool
    n*: int       ## function-key number for kFn

proc `==`*(a, b: Key): bool =
  a.kind == b.kind and a.ch == b.ch and a.ctrl == b.ctrl and
    a.alt == b.alt and a.n == b.n

proc key*(kind: KeyKind): Key = Key(kind: kind)

proc chKey*(c: string, ctrl = false, alt = false): Key =
  Key(kind: kChar, ch: c, ctrl: ctrl, alt: alt)

proc isChar*(k: Key, c: string): bool =
  ## True for a plain (unmodified) character key.
  k.kind == kChar and not k.ctrl and not k.alt and k.ch == c

proc `$`*(k: Key): string =
  case k.kind
  of kChar:
    result = k.ch
    if k.ctrl: result = "ctrl+" & result
    if k.alt: result = "alt+" & result
  of kFn: result = "F" & $k.n
  of kNone: result = "none"
  else:
    const names: array[KeyKind, string] = [
      "none", "char", "enter", "esc", "backspace", "tab", "shift+tab",
      "↑", "↓", "←", "→", "home", "end", "pgup", "pgdn", "insert",
      "delete", "fn"]
    result = names[k.kind]
