## A live system dashboard built with loom — reactive signals feed the
## view; the framework re-renders (diffed) whenever they change.
##
##   nim c -d:release examples/dashboard.nim && ./bin/dashboard

import std/[algorithm, cpuinfo, os, osproc, strformat, strutils, times]
import loom

proc getloadavg(loads: ptr cdouble, nelem: cint): cint
  {.importc, header: "<stdlib.h>".}

# ---- data sampling ---------------------------------------------------------

proc sampleLoad(): float =
  var l: array[3, cdouble]
  if getloadavg(addr l[0], 3) >= 1: l[0].float else: 0.0

var totalMem = 0.0   # bytes; fetched once at startup

proc initTotalMem() =
  when defined(macosx):
    try:
      totalMem = parseFloat(execProcess("sysctl",
        args = ["-n", "hw.memsize"], options = {poUsePath}).strip)
    except CatchableError:
      discard

proc parseVmStat(vs: string): float =
  ## macOS vm_stat output -> fraction of memory in use.
  var pageSize = 16384.0
  var freeish = 0.0
  for ln in vs.splitLines:
    if "page size of" in ln:
      for tok in ln.splitWhitespace:
        if tok.allCharsInSet(Digits):
          pageSize = parseFloat(tok)
    for pfx in ["Pages free:", "Pages inactive:", "Pages speculative:"]:
      if ln.startsWith(pfx):
        try:
          freeish += parseFloat(ln.split(':')[1].strip.strip(chars = {'.'}))
        except ValueError:
          discard
  if totalMem > 0:
    clamp(1.0 - freeish * pageSize / totalMem, 0.0, 1.0)
  else:
    0.0

proc sampleMemLinux(): float =
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

proc parsePs(outp: string): tuple[rows, pids: seq[string]] =
  type Row = tuple[cpu: float, pid, line: string]
  var rows: seq[Row]
  for ln in outp.splitLines:
    let f = ln.splitWhitespace(maxsplit = 3)
    if f.len < 4: continue
    let cpu =
      try: parseFloat(f[1])
      except ValueError: 0.0
    let name = f[3].rsplit('/', maxsplit = 1)[^1]
    rows.add (cpu, f[0], &"{f[0]:>6} {f[1]:>6} {f[2]:>6}  {name}")
  if rows.len == 0:
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
  helpScroll = signal(0)
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
frame, so only changed cells are written to the terminal. Sampling runs
through execAsync, so a slow `ps` can never freeze the UI.

This help lives in a scrollable viewport — scroll it with the wheel or
arrow/page keys when focused.

Keys:
  q          quit
  tab        cycle focus (the filter starts focused)
  ↑ / ↓      move the process selection
  pgup/pgdn  page through processes
  ← / →      switch tabs (when the tab bar is focused)
  type       filter the process list (when the filter is focused)
  t          cycle themes (default → neon → mono)
  m          toggle mouse capture (off = terminal text selection works)
  ctrl-z     suspend; fg resumes cleanly

Mouse (when capture is on):
  click      focus a widget, select a row, switch a tab, place the cursor
  drag       sweep the selection / cursor
  wheel      scroll the process list or this help

Wide glyphs are measured properly — 日本語 and 🚀 take two columns each
and never tear the layout.

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
          viewport(text(helpText, wrap = true), helpScroll, id = "help")
      spans([(" q ", hintKey), ("quit", hintDim), ("  ↑/↓ ", hintKey),
             ("select", hintDim), ("  tab ", hintKey), ("focus", hintDim),
             ("  ←/→ ", hintKey), ("tabs", hintDim), ("  t ", hintKey),
             ("theme", hintDim), ("  m ", hintKey), ("mouse", hintDim)])

# ---- wiring ----------------------------------------------------------------

proc selftest(): int =
  ## Render one frame headlessly and print it — no event loop, no tty.
  ## Lets CI verify the binary actually runs and lays out on each platform
  ## without the fragility of piping keystrokes into an interactive TUI.
  initTotalMem()
  let (rows, pids) = parsePs(execProcess("ps",
    args = ["axo", "pid=,pcpu=,pmem=,comm="], options = {poUsePath}))
  allProcs.set rows
  allPids.set pids
  let app = newApp(view)
  let frame = app.renderFrame(100, 30)
  echo frame.dump
  if "loom dashboard" in frame.dump: 0 else: 1

proc main() =
  if "--selftest" in commandLineParams():
    quit(selftest())
  let app = newApp(view, mouse = true)
  var mouseOn = true
  const themes = [themeDefault, themeNeon, themeMono]
  var themeIdx = 0
  initTotalMem()

  app.every(1000, proc () =
    let l = sampleLoad()
    load1.set l
    var h = loadHist.peek
    h.add l
    if h.len > 300: h = h[^300 .. ^1]
    loadHist.set h)

  # sampling runs off the loop — a slow subprocess can't freeze input
  app.every(2000, proc () =
    app.execAsync("ps", @["axo", "pid=,pcpu=,pmem=,comm="],
      proc (outp: string) =
        let (rows, pids) = parsePs(outp)
        allProcs.set rows
        allPids.set pids)
    when defined(macosx):
      app.execAsync("vm_stat", @[], proc (outp: string) =
        memUsed.set parseVmStat(outp))
    else:
      memUsed.set sampleMemLinux())

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
    elif k.isChar("t"):
      themeIdx = (themeIdx + 1) mod themes.len
      setTheme(themes[themeIdx])
      pushLog "theme: " & themes[themeIdx].name
      true
    else:
      false)

  pushLog "dashboard started — " & $ncpu & " cores"
  app.every(10000, proc () =
    pushLog &"load {load1.peek:.2f} · mem {int(memUsed.peek * 100)}%")

  app.run()

main()
