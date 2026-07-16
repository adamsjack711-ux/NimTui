## Terminal backend: raw mode, alternate screen, diffed drawing, and
## escape-sequence key parsing. POSIX only (macOS + Linux), zero deps.

import std/[options, strutils]
import std/posix except Signal, Key
import std/termios
import buffer, geometry, events

type
  IoctlWinSize = object
    ws_row, ws_col, ws_xpixel, ws_ypixel: cushort

var TIOCGWINSZ {.importc: "TIOCGWINSZ", header: "<sys/ioctl.h>".}: culong
var SIGWINCH {.importc: "SIGWINCH", header: "<signal.h>".}: cint
proc ioctl(fd: cint, request: culong, arg: pointer): cint
  {.importc, varargs, header: "<sys/ioctl.h>".}

var
  origTios: Termios
  rawOn = false
  winch = false

proc onWinch(sig: cint) {.noconv.} =
  winch = true

proc termSize*(): Size =
  var ws: IoctlWinSize
  if ioctl(1, TIOCGWINSZ, addr ws) == 0 and ws.ws_col > 0:
    size(ws.ws_col.int, ws.ws_row.int)
  else:
    size(80, 24)

type
  Terminal* = object
    width*, height*: int
    prev: Buffer
    active: bool

proc setup*(t: var Terminal) =
  if tcGetAttr(0, addr origTios) == 0:
    var raw = origTios
    raw.c_iflag = raw.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or ISTRIP or IXON)
    raw.c_oflag = raw.c_oflag and not Cflag(OPOST)
    raw.c_cflag = raw.c_cflag or Cflag(CS8)
    raw.c_lflag = raw.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
    raw.c_cc[VMIN] = char(0)
    raw.c_cc[VTIME] = char(0)
    discard tcSetAttr(0, TCSAFLUSH, addr raw)
    rawOn = true
  discard posix.signal(SIGWINCH, onWinch)
  # alt screen, hidden cursor, clear, then SGR mouse reporting
  stdout.write "\e[?1049h\e[?25l\e[2J\e[?1000h\e[?1006h"
  stdout.flushFile()
  let s = termSize()
  t.width = s.w
  t.height = s.h
  t.prev = newBuffer(0, 0)   # dimension mismatch forces a full first draw
  t.active = true

proc restore*(t: var Terminal) =
  if not t.active: return
  stdout.write "\e[?1006l\e[?1000l\e[0m\e[?25h\e[?1049l"
  stdout.flushFile()
  if rawOn:
    discard tcSetAttr(0, TCSAFLUSH, addr origTios)
    rawOn = false
  t.active = false

proc draw*(t: var Terminal, next: Buffer) =
  let outp = diffToAnsi(t.prev, next)
  if outp.len > 0:
    stdout.write outp
    stdout.flushFile()
  t.prev = next

proc checkResize*(t: var Terminal): bool =
  ## True if the terminal was resized since the last check; refreshes
  ## dimensions and invalidates the previous frame.
  if not winch: return false
  winch = false
  let s = termSize()
  t.width = s.w
  t.height = s.h
  t.prev = newBuffer(0, 0)
  true

# ---- input ----------------------------------------------------------------

var
  pendingBuf = ""
  pendingPos = 0

proc waitReadable(timeoutMs: int): bool =
  var fds: TFdSet
  FD_ZERO(fds)
  FD_SET(0, fds)
  var tv: Timeval
  tv.tv_sec = posix.Time(timeoutMs div 1000)
  tv.tv_usec = Suseconds((timeoutMs mod 1000) * 1000)
  select(1, addr fds, nil, nil, addr tv) > 0

proc readAvailable(): string =
  var tmp: array[256, char]
  while true:
    let n = read(0, addr tmp[0], tmp.len)
    if n <= 0: break
    for i in 0 ..< n:
      result.add tmp[i]
    if n < tmp.len: break

proc parseCsi(): Event =
  ## Called with pendingPos just past "\e[".
  var isMouse = false
  if pendingPos < pendingBuf.len and pendingBuf[pendingPos] == '<':
    isMouse = true
    inc pendingPos
  var params = ""
  while pendingPos < pendingBuf.len and pendingBuf[pendingPos] in {'0' .. '9', ';'}:
    params.add pendingBuf[pendingPos]
    inc pendingPos
  if pendingPos >= pendingBuf.len:
    return keyEvent(key(kNone))
  let final = pendingBuf[pendingPos]
  inc pendingPos
  if isMouse:
    # SGR mouse report: \e[<b;x;yM (press) or \e[<b;x;ym (release)
    if final notin {'M', 'm'}: return keyEvent(key(kNone))
    let parts = params.split(';')
    if parts.len < 3: return keyEvent(key(kNone))
    let b =
      try: parseInt(parts[0])
      except ValueError: return keyEvent(key(kNone))
    let x =
      try: parseInt(parts[1]) - 1
      except ValueError: return keyEvent(key(kNone))
    let y =
      try: parseInt(parts[2]) - 1
      except ValueError: return keyEvent(key(kNone))
    if b >= 64:
      if b > 65: return keyEvent(key(kNone))   # horizontal wheel etc.
      return mouseEvent(if b == 64: mWheelUp else: mWheelDown, mbNone, x, y)
    let btn = case b and 3
      of 0: mbLeft
      of 1: mbMiddle
      of 2: mbRight
      else: mbNone
    return mouseEvent(if final == 'M': mPress else: mRelease, btn, x, y)
  case final
  of 'A': keyEvent(key(kUp))
  of 'B': keyEvent(key(kDown))
  of 'C': keyEvent(key(kRight))
  of 'D': keyEvent(key(kLeft))
  of 'H': keyEvent(key(kHome))
  of 'F': keyEvent(key(kEnd))
  of 'Z': keyEvent(key(kBackTab))
  of '~':
    let n =
      try: parseInt(params.split(';')[0])
      except ValueError: 0
    case n
    of 1, 7: keyEvent(key(kHome))
    of 2: keyEvent(key(kInsert))
    of 3: keyEvent(key(kDelete))
    of 4, 8: keyEvent(key(kEnd))
    of 5: keyEvent(key(kPageUp))
    of 6: keyEvent(key(kPageDown))
    of 11 .. 15: keyEvent(Key(kind: kFn, n: n - 10))
    of 17 .. 21: keyEvent(Key(kind: kFn, n: n - 11))
    of 23, 24: keyEvent(Key(kind: kFn, n: n - 12))
    else: keyEvent(key(kNone))
  else: keyEvent(key(kNone))

proc parseOne(depth = 0): Event =
  ## Parse one event from the pending byte queue, advancing pendingPos.
  let b = pendingBuf[pendingPos]
  inc pendingPos
  case b
  of '\e':
    if pendingPos >= pendingBuf.len:
      # Might be a lone ESC or a split escape sequence: give the rest of
      # the sequence a few ms to arrive.
      if waitReadable(5):
        pendingBuf.add readAvailable()
    if pendingPos >= pendingBuf.len:
      return keyEvent(key(kEsc))
    let nxt = pendingBuf[pendingPos]
    case nxt
    of '[':
      inc pendingPos
      parseCsi()
    of 'O':
      inc pendingPos
      if pendingPos >= pendingBuf.len: return keyEvent(key(kEsc))
      let f = pendingBuf[pendingPos]
      inc pendingPos
      case f
      of 'P' .. 'S': keyEvent(Key(kind: kFn, n: f.ord - 'P'.ord + 1))
      of 'H': keyEvent(key(kHome))
      of 'F': keyEvent(key(kEnd))
      else: keyEvent(key(kNone))
    else:
      if depth > 0: return keyEvent(key(kEsc))
      var e = parseOne(depth + 1)
      if e.kind == ekKey:
        e.key.alt = true
      e
  of '\r', '\n': keyEvent(key(kEnter))
  of '\t': keyEvent(key(kTab))
  of '\b', '\x7f': keyEvent(key(kBackspace))
  of '\x01' .. '\x07', '\x0b', '\x0c', '\x0e' .. '\x1a':
    keyEvent(chKey($chr(b.ord + 'a'.ord - 1), ctrl = true))
  of '\x00': keyEvent(key(kNone))
  else:
    # UTF-8: pull continuation bytes for multi-byte runes.
    var n = 1
    if (b.ord and 0xE0) == 0xC0: n = 2
    elif (b.ord and 0xF0) == 0xE0: n = 3
    elif (b.ord and 0xF8) == 0xF0: n = 4
    var ch = $b
    for _ in 1 ..< n:
      if pendingPos < pendingBuf.len:
        ch.add pendingBuf[pendingPos]
        inc pendingPos
    keyEvent(chKey(ch))

proc feedInput*(s: string) =
  ## Inject bytes as if they arrived from the terminal — for tests and
  ## programmatic driving.
  if pendingPos >= pendingBuf.len:
    pendingBuf = s
    pendingPos = 0
  else:
    pendingBuf.add s

proc pollEvent*(timeoutMs: int): Option[Event] =
  ## Wait up to `timeoutMs` for an input event. Serves buffered input
  ## first, so calling with timeout 0 drains queued events without
  ## blocking.
  if pendingPos >= pendingBuf.len:
    pendingBuf = ""
    pendingPos = 0
    if timeoutMs > 0 and not waitReadable(timeoutMs):
      return none(Event)
    pendingBuf = readAvailable()
    if pendingBuf.len == 0:
      return none(Event)
  var e = parseOne()
  while e.isNoneEvent and pendingPos < pendingBuf.len:
    e = parseOne()
  if e.isNoneEvent:
    return none(Event)
  some e
