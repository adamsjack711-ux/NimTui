## Minimal fine-grained reactivity: signals with automatic dependency
## tracking. Reading a signal inside a tracked scope (an `effect`, or the
## app's render pass) subscribes the current observer; setting a signal
## re-runs its subscribers.

import std/sequtils

type
  Observer* = ref object
    fn: proc () {.closure.}
    deps: seq[SignalBase]
    active: bool

  SignalBase* = ref object of RootObj
    subs: seq[Observer]
    owner: Observer   ## the effect driving a computed, for disposal

  Signal*[T] = ref object of SignalBase
    v: T

var
  obsStack: seq[Observer]
  pendingObs: seq[Observer]
  flushing = false

proc newObserver*(fn: proc ()): Observer =
  ## An observer that is NOT run immediately — used by the app's render
  ## loop, which manages its own tracked scope. Most code wants `effect`.
  Observer(fn: fn, active: true)

proc clearDeps*(o: Observer) =
  for d in o.deps:
    d.subs.keepItIf(it != o)
  o.deps.setLen 0

proc dispose*(o: Observer) =
  o.active = false
  o.clearDeps()

proc pushObserver*(o: Observer) = obsStack.add o
proc popObserver*() = obsStack.setLen(obsStack.len - 1)

template withTracking*(o: Observer, body: untyped) =
  pushObserver(o)
  try:
    body
  finally:
    popObserver()

proc track(s: SignalBase) =
  if obsStack.len > 0:
    let o = obsStack[^1]
    if o notin s.subs:
      s.subs.add o
      o.deps.add s

proc notify(s: SignalBase) =
  # Propagation is simple breadth-order, not topological: diamond-shaped
  # dependency graphs may recompute a downstream computed more than once
  # per change (a "glitch"). Dedup below is O(n^2) in pending observers.
  # Both are fine at UI scale; don't build a data pipeline on this.
  for o in s.subs:
    if o.active and o notin pendingObs:
      pendingObs.add o
  if flushing: return
  flushing = true
  try:
    var i = 0
    while i < pendingObs.len:
      let o = pendingObs[i]
      inc i
      if not o.active: continue
      o.clearDeps()
      withTracking(o):
        o.fn()
    pendingObs.setLen 0
  finally:
    flushing = false

proc signal*[T](v: T): Signal[T] =
  Signal[T](v: v)

proc get*[T](s: Signal[T]): T =
  ## Read the value, subscribing the current observer (if any).
  track(s)
  s.v

proc peek*[T](s: Signal[T]): T =
  ## Read the value without subscribing.
  s.v

proc set*[T](s: Signal[T], v: T) =
  ## Write the value; no-op (no notification) when unchanged.
  when compiles(s.v == v):
    if s.v == v: return
  s.v = v
  notify(s)

proc update*[T](s: Signal[T], f: proc (x: T): T) =
  s.set f(s.peek)

proc effect*(fn: proc ()): Observer {.discardable.} =
  ## Run `fn` now with tracking; re-run whenever any signal it read changes.
  result = newObserver(fn)
  withTracking(result):
    fn()

proc computed*[T](fn: proc (): T): Signal[T] =
  ## A read-only signal derived from other signals. Stop it with `dispose`.
  let s = signal(default(T))
  s.owner = effect(proc () = s.set fn())
  s

proc dispose*(s: SignalBase) =
  ## Stop a computed signal from recomputing. No-op for plain signals.
  if s.owner != nil:
    s.owner.dispose()
    s.owner = nil
