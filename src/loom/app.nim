## The application runtime: owns the terminal, rebuilds the view when any
## signal it depends on changes, dispatches input, and runs timers.

import std/[monotimes, options, times]
from std/posix import kill, getpid, SIGTSTP
import geometry, buffer, term, widget, reactive, events

type
  Timer = object
    interval: Duration
    next: MonoTime
    cb: proc ()

  App* = ref object
    viewFn: proc (): Widget
    keyFn: proc (k: Key): bool
    timers: seq[Timer]
    obs: Observer
    dirty: bool
    running: bool
    mouseOn: bool
    focusIdx: int
    focusInited: bool
    focusedId: string   ## id of the focused widget, for keyed restore
    focusables: seq[Widget]
    lastHits: seq[HitRegion]
    term: Terminal
    root: Widget

proc newApp*(view: proc (): Widget; mouse = false): App =
  ## `view` is called to (re)build the whole widget tree on every dirty
  ## frame. Signals read inside it are tracked automatically.
  ##
  ## Mouse capture is off by default because it disables the terminal's
  ## own text selection/copy; pass `mouse = true` (or call `setMouse`)
  ## to enable click/wheel events.
  let app = App(viewFn: view, mouseOn: mouse, dirty: true, running: true)
  app.obs = newObserver(proc () = app.dirty = true)
  app

proc onKey*(app: App, fn: proc (k: Key): bool) =
  ## Global key handler; runs after the focused widget declines the key.
  ## Return true to consume.
  app.keyFn = fn

proc every*(app: App, ms: int, cb: proc ()) =
  ## Run `cb` every `ms` milliseconds (first run is immediate).
  app.timers.add Timer(interval: initDuration(milliseconds = ms),
                       next: getMonoTime(), cb: cb)

proc quit*(app: App) =
  app.running = false

proc isRunning*(app: App): bool = app.running

proc focused*(app: App): Widget =
  ## The currently focused widget (nil when nothing is focusable).
  if app.focusIdx < app.focusables.len: app.focusables[app.focusIdx]
  else: nil

proc setMouse*(app: App, on: bool) =
  ## Toggle mouse capture at runtime.
  app.mouseOn = on
  app.term.setMouse(on)

proc rememberFocus(app: App) =
  let w = app.focused
  app.focusedId = if w != nil: w.id else: ""

proc renderFrame*(app: App, width, height: int): Buffer =
  ## Build the view, resolve focus, and render one frame into a buffer.
  ## Needs no terminal — this is the seam tests drive.
  clearDeps(app.obs)
  result = newBuffer(width, height)
  let ctx = RenderCtx()
  withTracking(app.obs):
    app.root = app.viewFn()
    app.focusables = @[]
    collectFocusable(app.root, app.focusables)
    if not app.focusInited and app.focusables.len > 0:
      app.focusInited = true
      for i, w in app.focusables:
        if w.autofocus:
          app.focusIdx = i
          break
      app.rememberFocus()
    if app.focusedId.len > 0:
      for i, w in app.focusables:
        if w.id == app.focusedId:
          app.focusIdx = i
          break
    if app.focusIdx >= app.focusables.len:
      app.focusIdx = 0
    if app.focusables.len > 0:
      ctx.focused = app.focusables[app.focusIdx]
    app.root.render(result, rect(0, 0, width, height), ctx)
  app.lastHits = ctx.hits
  app.dirty = false

proc rebuild(app: App) =
  let buf = app.renderFrame(app.term.width, app.term.height)
  app.term.draw(buf)

proc cycleFocus(app: App, dir: int) =
  if app.focusables.len == 0: return
  app.focusIdx = (app.focusIdx + dir + app.focusables.len) mod app.focusables.len
  app.rememberFocus()
  app.dirty = true

proc suspend(app: App) =
  ## ctrl-z: restore the terminal, stop like a normal job, resume cleanly.
  app.term.restore()
  discard kill(getpid(), SIGTSTP)
  # execution continues here after SIGCONT (fg/bg)
  app.term.setup()
  app.term.setMouse(app.mouseOn)
  app.dirty = true

proc dispatchKey(app: App, k: Key) =
  var handled = false
  let w = app.focused
  if w != nil:
    handled = w.handleKey(k)
  if not handled and app.keyFn != nil:
    handled = app.keyFn(k)
  if handled:
    # Handled events may change widget-internal state that no signal
    # tracks, so always repaint.
    app.dirty = true
    return
  case k.kind
  of kTab: app.cycleFocus(1)
  of kBackTab: app.cycleFocus(-1)
  of kChar:
    if k.ctrl and k.ch == "c":
      app.quit()
    elif k.ctrl and k.ch == "z":
      app.suspend()
  else:
    discard

proc dispatchMouse(app: App, m: Mouse) =
  var target: Widget = nil
  var tArea: Rect
  for i in countdown(app.lastHits.len - 1, 0):
    if app.lastHits[i].area.contains(m.x, m.y):
      target = app.lastHits[i].w
      tArea = app.lastHits[i].area
      break
  if target == nil: return
  if m.kind == mPress:
    let idx = app.focusables.find(target)
    if idx >= 0 and idx != app.focusIdx:
      app.focusIdx = idx
      app.rememberFocus()
      app.dirty = true
  if target.handleMouse(m, tArea):
    app.dirty = true

proc processEvent*(app: App, e: Event) =
  ## Feed one input event through focus/handler dispatch. Exposed so the
  ## app can be driven headlessly (tests, automation).
  case e.kind
  of ekKey: app.dispatchKey(e.key)
  of ekMouse: app.dispatchMouse(e.mouse)
  of ekPaste:
    let w = app.focused
    if w != nil and w.handlePaste(e.paste):
      app.dirty = true

proc nextTimeoutMs(app: App): int =
  result = 250
  let now = getMonoTime()
  for t in app.timers:
    let ms = (t.next - now).inMilliseconds.int
    result = min(result, max(ms, 0))

proc runTimers(app: App) =
  let now = getMonoTime()
  for t in app.timers.mitems:
    if now >= t.next:
      t.cb()
      t.next = t.next + t.interval
      if t.next <= now:               # missed beats: don't burst-fire
        t.next = now + t.interval

proc run*(app: App) =
  ## Enter the event loop; returns when `quit` is called. The terminal is
  ## always restored — on exceptions via `finally`, on SIGTERM/SIGHUP via
  ## the loop check, and on unexpected exits via an exit proc.
  app.term.setup()
  app.term.setMouse(app.mouseOn)
  app.running = true
  try:
    app.runTimers()
    app.rebuild()
    while app.running:
      var ev = pollEvent(app.nextTimeoutMs())
      var drained = 0
      while ev.isSome and drained < 64:
        app.processEvent(ev.get)
        if not app.running: break
        inc drained
        ev = pollEvent(0)
      if quitRequested():
        app.quit()
      if not app.running: break
      app.runTimers()
      if app.term.checkResize():
        app.dirty = true
      if app.dirty:
        app.rebuild()
  finally:
    app.term.restore()
