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
    shift*: bool  ## only reported for special keys (arrows, fn, ...)
    n*: int       ## function-key number for kFn

proc `==`*(a, b: Key): bool =
  a.kind == b.kind and a.ch == b.ch and a.ctrl == b.ctrl and
    a.alt == b.alt and a.shift == b.shift and a.n == b.n

proc key*(kind: KeyKind): Key = Key(kind: kind)

proc chKey*(c: string, ctrl = false, alt = false): Key =
  Key(kind: kChar, ch: c, ctrl: ctrl, alt: alt)

proc isChar*(k: Key, c: string): bool =
  ## True for a plain (unmodified) character key.
  k.kind == kChar and not k.ctrl and not k.alt and k.ch == c

type
  MouseKind* = enum
    mPress, mRelease, mWheelUp, mWheelDown

  MouseButton* = enum
    mbNone, mbLeft, mbMiddle, mbRight

  Mouse* = object
    kind*: MouseKind
    btn*: MouseButton
    x*, y*: int   ## 0-based screen cell coordinates

  EventKind* = enum
    ekKey, ekMouse, ekPaste

  Event* = object
    case kind*: EventKind
    of ekKey: key*: Key
    of ekMouse: mouse*: Mouse
    of ekPaste: paste*: string   ## bracketed-paste payload

proc keyEvent*(k: Key): Event = Event(kind: ekKey, key: k)

proc mouseEvent*(kind: MouseKind, btn: MouseButton, x, y: int): Event =
  Event(kind: ekMouse, mouse: Mouse(kind: kind, btn: btn, x: x, y: y))

proc pasteEvent*(s: string): Event = Event(kind: ekPaste, paste: s)

proc isNoneEvent*(e: Event): bool =
  e.kind == ekKey and e.key.kind == kNone

proc `$`*(k: Key): string =
  case k.kind
  of kChar: result = k.ch
  of kFn: result = "F" & $k.n
  of kNone: result = "none"
  else:
    const names: array[KeyKind, string] = [
      "none", "char", "enter", "esc", "backspace", "tab", "shift+tab",
      "↑", "↓", "←", "→", "home", "end", "pgup", "pgdn", "insert",
      "delete", "fn"]
    result = names[k.kind]
  if k.shift and k.kind != kBackTab: result = "shift+" & result
  if k.alt: result = "alt+" & result
  if k.ctrl: result = "ctrl+" & result
