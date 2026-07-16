## The application runtime: owns the terminal, rebuilds the view when any
## signal it depends on changes, dispatches input, and runs timers.

import std/[monotimes, options, times]
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
    focusIdx: int
    focusables: seq[Widget]
    term: Terminal
    root: Widget

proc newApp*(view: proc (): Widget): App =
  ## `view` is called to (re)build the whole widget tree on every dirty
  ## frame. Signals read inside it are tracked automatically.
  let app = App(viewFn: view, dirty: true)
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

proc rebuild(app: App) =
  clearDeps(app.obs)
  var buf = newBuffer(app.term.width, app.term.height)
  withTracking(app.obs):
    app.root = app.viewFn()
    app.focusables = @[]
    collectFocusable(app.root, app.focusables)
    if app.focusIdx >= app.focusables.len:
      app.focusIdx = 0
    var ctx = RenderCtx()
    if app.focusables.len > 0:
      ctx.focused = app.focusables[app.focusIdx]
    app.root.render(buf, rect(0, 0, buf.w, buf.h), ctx)
  app.term.draw(buf)
  app.dirty = false

proc cycleFocus(app: App, dir: int) =
  if app.focusables.len == 0: return
  app.focusIdx = (app.focusIdx + dir + app.focusables.len) mod app.focusables.len
  app.dirty = true

proc dispatch(app: App, k: Key) =
  var handled = false
  if app.focusIdx < app.focusables.len:
    handled = app.focusables[app.focusIdx].handleKey(k)
  if not handled and app.keyFn != nil:
    handled = app.keyFn(k)
  if not handled:
    case k.kind
    of kTab: app.cycleFocus(1)
    of kBackTab: app.cycleFocus(-1)
    of kChar:
      if k.ctrl and k.ch == "c":
        app.quit()
    else:
      discard

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
      t.next = now + t.interval

proc run*(app: App) =
  ## Enter the event loop; returns when `quit` is called. The terminal is
  ## always restored, including on exceptions.
  app.term.setup()
  app.running = true
  try:
    app.runTimers()
    app.rebuild()
    while app.running:
      var k = pollKey(app.nextTimeoutMs())
      var drained = 0
      while k.isSome and drained < 64:
        app.dispatch(k.get)
        if not app.running: break
        inc drained
        k = pollKey(0)
      if not app.running: break
      app.runTimers()
      if app.term.checkResize():
        app.dirty = true
      if app.dirty:
        app.rebuild()
  finally:
    app.term.restore()
