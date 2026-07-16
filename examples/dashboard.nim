## A live system dashboard built with loom — reactive signals feed the
## view; the framework re-renders (diffed) whenever they change.
##
##   nim c -d:release examples/dashboard.nim && ./bin/dashboard

import std/[algorithm, cpuinfo, osproc, strformat, strutils, times]
import loom

proc getloadavg(loads: ptr cdouble, nelem: cint): cint
  {.importc, header: "<stdlib.h>".}

# ---- data sampling ---------------------------------------------------------

proc sampleLoad(): float =
  var l: array[3, cdouble]
  if getloadavg(addr l[0], 3) >= 1: l[0].float else: 0.0

proc sampleMem(): float =
  ## Fraction of physical memory in use.
  when defined(macosx):
    try:
      let vs = execProcess("vm_stat", options = {poUsePath})
      var pageSize = 16384.0
      var freeish = 0.0
      for ln in vs.splitLines:
        if "page size of" in ln:
          for tok in ln.splitWhitespace:
            if tok.allCharsInSet(Digits):
              pageSize = parseFloat(tok)
        for pfx in ["Pages free:", "Pages inactive:", "Pages speculative:"]:
          if ln.startsWith(pfx):
            freeish += parseFloat(ln.split(':')[1].strip.strip(chars = {'.'}))
      let total = parseFloat(execProcess("sysctl",
        args = ["-n", "hw.memsize"], options = {poUsePath}).strip)
      if total > 0:
        return clamp(1.0 - freeish * pageSize / total, 0.0, 1.0)
    except CatchableError:
      discard
    0.0
  else:
    try:
      var total, avail = 0.0
      for ln in readFile("/proc/meminfo").splitLines:
        if ln.startsWith("MemTotal:"): total = parseFloat(ln.splitWhitespace[1])
        elif ln.startsWith("MemAvailable:"): avail = parseFloat(ln.splitWhitespace[1])
      if total > 0:
        return clamp(1.0 - avail / total, 0.0, 1.0)
    except CatchableError:
      discard
    0.0

proc sampleProcs(): tuple[rows, pids: seq[string]] =
  type Row = tuple[cpu: float, pid, line: string]
  var rows: seq[Row]
  try:
    let outp = execProcess("ps",
      args = ["axo", "pid=,pcpu=,pmem=,comm="], options = {poUsePath})
    for ln in outp.splitLines:
      let f = ln.splitWhitespace(maxsplit = 3)
      if f.len < 4: continue
      let cpu =
        try: parseFloat(f[1])
        except ValueError: 0.0
      let name = f[3].rsplit('/', maxsplit = 1)[^1]
      rows.add (cpu, f[0], &"{f[0]:>6} {f[1]:>6} {f[2]:>6}  {name}")
  except CatchableError:
    return (@["(ps unavailable)"], @[""])
  rows.sort do (a, b: Row) -> int: cmp(b.cpu, a.cpu)
  for r in rows[0 .. min(59, rows.high)]:
    result.rows.add r.line
    result.pids.add r.pid

# ---- state -----------------------------------------------------------------

let ncpu = max(1, cpuinfo.countProcessors())

var
  load1 = signal(0.0)
  loadHist = signal(newSeq[float]())
  memUsed = signal(0.0)
  allProcs = signal(newSeq[string]())
  allPids = signal(newSeq[string]())
  filter = inputState()
  selPid = signal("")   # keyed selection: follows the process through re-sorts
  activeTab = signal(0)
  clock = signal("")
  logs = signal(newSeq[string]())

proc pushLog(msg: string) =
  var l = logs.peek
  l.add now().format("HH:mm:ss") & "  " & msg
  if l.len > 200: l = l[^200 .. ^1]
  logs.set l

proc filteredProcs(): tuple[rows, pids: seq[string]] =
  let f = filter.text.get.toLowerAscii
  let rows = allProcs.get
  let pids = allPids.get
  if f.len == 0: return (rows, pids)
  for i, r in rows:
    if f in r.toLowerAscii:
      result.rows.add r
      result.pids.add (if i < pids.len: pids[i] else: "")

const helpText = """
loom dashboard — a demo of the loom TUI framework.

Everything on screen is a plain Nim value inside a Signal. The view is
rebuilt from signals on every change and diffed against the previous
frame, so only changed cells are written to the terminal.

Keys:
  q          quit
  tab        cycle focus (the filter starts focused)
  ↑ / ↓      move the process selection
  pgup/pgdn  page through processes
  ← / →      switch tabs (when the tab bar is focused)
  type       filter the process list (when the filter is focused)

Mouse (press m to toggle; off = terminal text selection works):
  click      focus a widget, select a row, switch a tab, place the cursor
  wheel      scroll the process list

Selection is keyed by PID, so it stays on the same process while the
table re-sorts. The process table is live `ps` output, the load gauge is
getloadavg() against your core count, and memory comes from vm_stat /
/proc/meminfo."""

# ---- view ------------------------------------------------------------------

const
  hintKey = Style(fg: clBrightYellow)
  hintDim = Style(fg: clBrightBlack)

proc view(): Widget =
  let (rows, pids) = filteredProcs()
  tui:
    vbox:
      panel(height = fixed(3)):
        hbox:
          text(" loom dashboard", style = style(fg = clBrightCyan, attrs = {aBold}))
          spacer()
          text(clock.get & " ", style = style(fg = clBrightBlack))
      tabs(@["overview", "help"], activeTab, id = "tabbar")
      if activeTab.get == 0:
        hbox:
          panel(title = "processes — " & $rows.len, width = flex(3)):
            input(filter, placeholder = "type to filter…",
                  autofocus = true, id = "filter")
            rule()
            list(rows, selPid, keys = pids, id = "procs")
          vbox(width = flex(2)):
            panel(title = "cpu load", height = flex(2)):
              gauge(load1.get / ncpu.float, label = " 1m")
              sparkline(loadHist.get, height = flex(1))
            panel(title = "memory", height = fixed(3)):
              gauge(memUsed.get, label = " used")
            panel(title = "log", height = flex(2)):
              list(logs.get)
      else:
        panel(title = "help"):
          text(helpText, wrap = true)
      spans([(" q ", hintKey), ("quit", hintDim), ("  ↑/↓ ", hintKey),
             ("select", hintDim), ("  tab ", hintKey), ("focus", hintDim),
             ("  ←/→ ", hintKey), ("tabs", hintDim), ("  m ", hintKey),
             ("mouse on/off", hintDim)])

# ---- wiring ----------------------------------------------------------------

proc main() =
  let app = newApp(view, mouse = true)
  var mouseOn = true

  app.every(1000, proc () =
    let l = sampleLoad()
    load1.set l
    var h = loadHist.peek
    h.add l
    if h.len > 300: h = h[^300 .. ^1]
    loadHist.set h)

  app.every(2000, proc () =
    let (rows, pids) = sampleProcs()
    allProcs.set rows
    allPids.set pids
    memUsed.set sampleMem())

  app.every(1000, proc () =
    clock.set now().format("ddd d MMM HH:mm:ss"))

  app.onKey(proc (k: Key): bool =
    if k.isChar("q"):
      app.quit()
      true
    elif k.isChar("m"):
      mouseOn = not mouseOn
      app.setMouse(mouseOn)
      pushLog(if mouseOn: "mouse capture on"
              else: "mouse capture off — text selection works")
      true
    else:
      false)

  pushLog "dashboard started — " & $ncpu & " cores"
  app.every(10000, proc () =
    pushLog &"load {load1.peek:.2f} · mem {int(memUsed.peek * 100)}%")

  app.run()

main()
