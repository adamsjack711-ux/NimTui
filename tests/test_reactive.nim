import std/unittest
import loom

suite "reactive":
  test "signal get/set/peek":
    let s = signal(1)
    check s.get == 1
    s.set 5
    check s.peek == 5

  test "effect runs immediately and on change":
    let s = signal(0)
    var runs = 0
    effect(proc () =
      discard s.get
      inc runs)
    check runs == 1
    s.set 1
    check runs == 2

  test "setting an equal value does not notify":
    let s = signal(3)
    var runs = 0
    effect(proc () =
      discard s.get
      inc runs)
    s.set 3
    check runs == 1

  test "effect tracks multiple signals":
    let a = signal(1)
    let b = signal(2)
    var total = 0
    effect(proc () = total = a.get + b.get)
    check total == 3
    a.set 10
    check total == 12
    b.set 20
    check total == 30

  test "dependencies re-track each run (conditional reads)":
    let cond = signal(true)
    let x = signal(1)
    let y = signal(100)
    var seen = 0
    effect(proc () =
      seen = (if cond.get: x.get else: y.get))
    check seen == 1
    cond.set false
    check seen == 100
    # x is no longer a dependency
    var before = seen
    x.set 42
    check seen == before
    y.set 7
    check seen == 7

  test "computed chains":
    let base = signal(2)
    let doubled = computed(proc (): int = base.get * 2)
    let plusOne = computed(proc (): int = doubled.get + 1)
    check plusOne.get == 5
    base.set 10
    check doubled.peek == 20
    check plusOne.peek == 21

  test "dispose stops re-runs":
    let s = signal(0)
    var runs = 0
    let obs = effect(proc () =
      discard s.get
      inc runs)
    obs.dispose()
    s.set 99
    check runs == 1

  test "update helper":
    let s = signal(@[1, 2])
    s.update(proc (x: seq[int]): seq[int] =
      result = x
      result.add 3)
    check s.peek == @[1, 2, 3]
