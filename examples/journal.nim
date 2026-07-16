## A journal / notes app built with loom — the split-pane stress test:
## a file-tree sidebar (keyed selection, expand/collapse) next to a
## markdown-ish preview rendered as styled spans inside a scrollable
## viewport, plus a raw-source tab and a quick-capture input that appends
## to the inbox note.
##
##   nim c -d:release examples/journal.nim && ./bin/journal

import std/[sequtils, strutils, times]
import loom

# ---- notes tree --------------------------------------------------------------

type
  NodeKind = enum nkDir, nkNote

  TreeNode = ref object
    kind: NodeKind
    name: string
    path: string          # unique key, e.g. "journal/2026-07/16 nimtui ships"
    children: seq[TreeNode]
    content: string       # nkNote only

proc note(name, content: string): TreeNode =
  TreeNode(kind: nkNote, name: name, content: content)

proc dir(name: string, children: varargs[TreeNode]): TreeNode =
  TreeNode(kind: nkDir, name: name, children: @children)

proc assignPaths(n: TreeNode, prefix: string) =
  n.path = if prefix.len == 0: n.name else: prefix & "/" & n.name
  for c in n.children:
    assignPaths(c, n.path)

let inbox = note("inbox", """
# inbox

Quick captures land here — focus the input at the bottom of the screen,
type, and press **enter**.
""")

let root = @[
  dir("journal",
    dir("2026-07",
      note("16 nimtui ships", """
# nimtui ships v0.2

The framework this app is built with — **nimtui** (Nim package `loom`) —
went from *empty repo* to a published npm demo in two days.

## what landed today

- wide-glyph cells — 日本語 and 🚀 no longer tear layouts
- a `viewport` widget (this preview scrolls inside one)
- themes in a signal: press **t** and the whole app repaints
- `spans` — the styled, wrapping text you are reading right now

## the pitch

> illwill and nimwave hand you a cell grid. nimtui adds signals, flex
> layout and a declarative view — the *Elm loop* in about 2000 lines.

Try the published demo:

```sh
npx nimtui
```

Source lives in the [NimTui repo](https://github.com/adamsjack711-ux/NimTui).

---

*This whole journal is one `view()` proc: rebuild on change, diff to ANSI.*
"""),
      note("15 loom day one", """
# day one

Started a reactive TUI framework in Nim. Signals with automatic
dependency tracking, a flex `Box` engine, and a `tui:` macro that turns
nesting into constructor calls.

The release binary is ~300 KB and links only libSystem. *Zero deps.*
"""),
      note("14 three tools", """
# three tools, three days

- `driftcheck` — semantic config differ, live on npm
- `agentwatch` — token/cost TUI for coding agents
- `stik` — file-based idea capture

The npm binary-shim pattern is now muscle memory.
""")),
    dir("2026-06",
      note("26 adventure buddy", """
# adventure buddy

A cozy macOS body-doubling app: focus timer plus a pixel buddy chopping
wood. The homestead grows with focus hours.
"""),
      note("20 cernis ideas", """
# cernis

Detection pipeline notes. Rule of thumb that stuck: **never report
accuracy** — PR-AUC and FP/hour only.
"""))),
  dir("notes",
    note("markdown cheatsheet", """
# markdown-ish, rendered

This preview understands a small, honest subset of markdown and renders
it with loom `spans` — every styled fragment you see is a `(text, Style)`
tuple flowing through the word-wrapper.

## inline styles

Mix **bold**, *italic*, `inline code` and [links](https://example.com)
inside a paragraph. They wrap correctly because the span-flow measures
display width, not byte length.

## headings

Three levels are styled (h1, h2, h3). Anything deeper is prose.

## lists

- unordered bullets get a colored dot
- they wrap like paragraphs when the line runs long enough to need it
- *inline* styles work **inside** bullets too

1. ordered lists keep their numbers
2. and are styled like bullets

## quotes

> The best interface is the one you can rebuild from scratch on every
> keystroke and still ship as a 300 KB binary.

## code blocks

```nim
let app = newApp(view, mouse = true)
app.every(1000, proc () = clock.set now().format("HH:mm:ss"))
app.run()
```

## rules

---

That line above is a real `rule()` widget, not three dashes.

## why this is a good stress test

The preview pane is a `viewport` over a `vbox` whose children are a mix
of `text`, `spans` and `rule` widgets — natural-height content, windowed
and scrolled. The sidebar is a keyed `list`, so selection follows the
note even when folders fold and the row indices shift underneath it.

Keep scrolling — the scrollbar on the right is drawn by the viewport
itself whenever content is taller than the window.

## odds and ends

- switch to the **raw** tab to see this file unrendered
- the clock in the header is a signal on a 1 s timer
- the quick-capture bar at the bottom appends to notes/inbox
- press `t` to cycle default → neon → mono themes

*fin.*
"""),
    note("wide glyphs", """
# wide glyphs

CJK and emoji take two terminal columns. The buffer stores a
continuation sentinel so clipping, alignment and diffing never split a
glyph in half.

- 日本語のテキストは二列幅で描画される
- 中文也可以正常显示
- 한국어도 잘 나옵니다
- emoji: 🚀 🔥 🎉 ☕ 🧵

Mixing widths in one line — loom 織機 weaves 🧶 them fine.
"""),
    inbox),
  dir("projects",
    note("nimtui roadmap", """
# roadmap

- grapheme clusters (ZWJ emoji, combining marks)
- windows backend (VT output already fine; input layer is POSIX)
- nimble registry publish
- more examples — a chess board is next
"""),
    note("reading list", """
# reading list

- [The Elm Architecture](https://guide.elm-lang.org/architecture/)
- [How to build a terminal renderer](https://poor.dev/blog/terminal-anatomy/)
- *Crafting Interpreters*, again
"""))]

for r in root:
  assignPaths(r, "")

proc findNode(ns: seq[TreeNode], path: string): TreeNode =
  for n in ns:
    if n.path == path:
      return n
    if path.startsWith(n.path & "/"):
      return findNode(n.children, path)
  nil

proc flatten(n: TreeNode, depth: int, exp: seq[string],
             rows, keys: var seq[string]) =
  let pad = "  ".repeat(depth)
  if n.kind == nkDir:
    let open = n.path in exp
    rows.add pad & (if open: "▾ " else: "▸ ") & n.name
    keys.add n.path
    if open:
      for c in n.children:
        flatten(c, depth + 1, exp, rows, keys)
  else:
    rows.add pad & "· " & n.name
    keys.add n.path

# ---- markdown-ish rendering --------------------------------------------------

const
  h1Style = Style(fg: clBrightWhite, attrs: {aBold, aUnderline})
  h2Style = Style(fg: clBrightCyan, attrs: {aBold})
  h3Style = Style(fg: clCyan, attrs: {aBold})
  codeStyle = Style(fg: c256(179))
  quoteStyle = Style(fg: clBrightBlack, attrs: {aItalic})
  bulletStyle = Style(fg: clCyan)
  linkStyle = Style(fg: clBlue, attrs: {aUnderline})

proc inlineSpans(s: string, base = Style()): seq[Span] =
  ## Split one line into styled fragments: **bold**, *italic*, `code`,
  ## [text](url).
  var plain = ""
  var i = 0
  template flush() =
    if plain.len > 0:
      result.add (text: plain, style: base)
      plain = ""
  while i < s.len:
    if s.continuesWith("**", i):
      let e = s.find("**", i + 2)
      if e >= 0:
        flush()
        result.add (text: s[i + 2 ..< e],
                    style: mergeStyle(base, Style(attrs: {aBold})))
        i = e + 2
        continue
    if s[i] == '*':
      let e = s.find('*', i + 1)
      if e >= 0:
        flush()
        result.add (text: s[i + 1 ..< e],
                    style: mergeStyle(base, Style(attrs: {aItalic})))
        i = e + 1
        continue
    if s[i] == '`':
      let e = s.find('`', i + 1)
      if e >= 0:
        flush()
        result.add (text: s[i + 1 ..< e], style: codeStyle)
        i = e + 1
        continue
    if s[i] == '[':
      let e = s.find(']', i + 1)
      if e >= 0 and e + 1 < s.len and s[e + 1] == '(':
        let u = s.find(')', e + 2)
        if u >= 0:
          flush()
          result.add (text: s[i + 1 ..< e], style: linkStyle)
          i = u + 1
          continue
    plain.add s[i]
    inc i
  flush()

proc prefixed(prefix: string, st: Style, rest: seq[Span]): seq[Span] =
  result = @[(text: prefix, style: st)]
  result.add rest

proc numberedPrefix(ln: string): int =
  ## Index just past "N. ", or -1 when the line isn't an ordered item.
  var i = 0
  while i < ln.len and ln[i] in Digits:
    inc i
  if i > 0 and i + 1 < ln.len and ln[i] == '.' and ln[i + 1] == ' ':
    i + 2
  else:
    -1

proc mdView(content: string): Widget =
  let box = vbox()
  var inCode = false
  for ln in content.splitLines:
    if ln.startsWith("```"):
      inCode = not inCode
      box.add text(ln, style = Style(fg: clBrightBlack))
    elif inCode:
      box.add text("  " & ln, style = codeStyle)
    elif ln.startsWith("# "):
      box.add text(ln[2 .. ^1], style = h1Style)
    elif ln.startsWith("## "):
      box.add text(ln[3 .. ^1], style = h2Style)
    elif ln.startsWith("### "):
      box.add text(ln[4 .. ^1], style = h3Style)
    elif ln.startsWith("> "):
      box.add spans(prefixed("┃ ", quoteStyle,
                             inlineSpans(ln[2 .. ^1], quoteStyle)), wrap = true)
    elif ln.startsWith("- ") or ln.startsWith("* "):
      box.add spans(prefixed("  • ", bulletStyle,
                             inlineSpans(ln[2 .. ^1])), wrap = true)
    elif ln.strip == "---":
      box.add rule()
    elif ln.len == 0:
      box.add text("")
    else:
      let np = numberedPrefix(ln)
      if np > 0:
        box.add spans(prefixed("  " & ln[0 ..< np], bulletStyle,
                               inlineSpans(ln[np .. ^1])), wrap = true)
      else:
        box.add spans(inlineSpans(ln), wrap = true)
  box

proc dirSummary(n: TreeNode): Widget =
  let box = vbox()
  box.add text(n.path & "/", style = h2Style)
  box.add text("")
  for c in n.children:
    box.add text("  " & (if c.kind == nkDir: "▸ " & c.name & "/"
                         else: "· " & c.name))
  box.add text("")
  box.add text($n.children.len & " items — enter folds/unfolds",
               style = Style(fg: clBrightBlack))
  box

# ---- state -------------------------------------------------------------------

var
  expanded = signal(@["journal", "journal/2026-07", "notes"])
  selPath = signal("journal/2026-07/16 nimtui ships")
  mode = signal(0)          # 0 = preview, 1 = raw
  bodyScroll = signal(0)
  capture = inputState()
  clock = signal("")

# ---- view --------------------------------------------------------------------

const
  hintKey = Style(fg: clBrightYellow)
  hintDim = Style(fg: clBrightBlack)

proc view(): Widget =
  var rows, keys: seq[string]
  let exp = expanded.get
  for r in root:
    flatten(r, 0, exp, rows, keys)
  let sel = findNode(root, selPath.get)
  tui:
    vbox:
      panel(height = fixed(3)):
        hbox:
          text(" ✎ journal — a nimtui demo",
               style = Style(fg: clBrightMagenta, attrs: {aBold}))
          spacer()
          text(clock.get & " ", style = hintDim)
      hbox:
        panel(title = "notes", width = fixed(30)):
          list(rows, selPath, keys = keys, autofocus = true, id = "tree")
        vbox:
          tabs(@["preview", "raw"], mode, id = "mode")
          if sel != nil and sel.kind == nkNote:
            panel(title = sel.name):
              if mode.get == 0:
                viewport(mdView(sel.content), bodyScroll, id = "body")
              else:
                viewport(text(sel.content), bodyScroll, id = "body")
          elif sel != nil:
            panel(title = sel.name):
              dirSummary(sel)
          else:
            panel(title = "journal"):
              text("select a note on the left")
      hbox(height = fixed(1)):
        text(" + ", style = Style(fg: clBrightGreen, attrs: {aBold}))
        input(capture, placeholder = "quick capture — enter appends to notes/inbox",
              id = "capture")
      hbox(height = fixed(1)):
        spans([(" enter ", hintKey), ("fold", hintDim), ("  ←/→ ", hintKey),
               ("close/open", hintDim), ("  tab ", hintKey), ("focus", hintDim),
               ("  t ", hintKey), ("theme", hintDim), ("  m ", hintKey),
               ("mouse", hintDim), ("  q ", hintKey), ("quit", hintDim)])
        spacer()
        if sel != nil and sel.kind == nkNote:
          text($sel.content.splitWhitespace.len & " words ", style = hintDim)

# ---- wiring ------------------------------------------------------------------

proc main() =
  let app = newApp(view, mouse = true)
  var mouseOn = true
  const themes = [themeDefault, themeNeon, themeMono]
  var themeIdx = 0

  # jump back to the top whenever the note or the view mode changes
  effect(proc () =
    discard selPath.get
    discard mode.get
    bodyScroll.set 0)

  app.every(1000, proc () =
    clock.set now().format("ddd d MMM HH:mm"))

  proc toggleDir(path: string) =
    var e = expanded.peek
    let i = e.find(path)
    if i >= 0:
      e.delete(i .. i)
      # keep the selection visible when its folder folds
      if selPath.peek.startsWith(path & "/"):
        selPath.set path
    else:
      e.add path
    expanded.set e

  app.onKey(proc (k: Key): bool =
    let focusId = if app.focused != nil: app.focused.id else: ""
    if focusId == "tree":
      let sel = findNode(root, selPath.peek)
      if sel != nil and sel.kind == nkDir and
         (k.kind == kEnter or k.isChar(" ")):
        toggleDir(sel.path)
        return true
      if k.kind == kRight and sel != nil and sel.kind == nkDir and
         sel.path notin expanded.peek:
        toggleDir(sel.path)
        return true
      if k.kind == kLeft and sel != nil:
        if sel.kind == nkDir and sel.path in expanded.peek:
          toggleDir(sel.path)
        elif '/' in sel.path:
          selPath.set sel.path.rsplit('/', maxsplit = 1)[0]
        return true
    if focusId == "capture" and k.kind == kEnter:
      let line = capture.text.peek.strip
      if line.len > 0:
        inbox.content.add "\n- " & now().format("HH:mm") & " — " & line
        capture.text.set ""
        capture.cursor.set 0
        selPath.set inbox.path   # show the capture land
      return true
    if k.isChar("q"):
      app.quit()
      return true
    if k.isChar("t"):
      themeIdx = (themeIdx + 1) mod themes.len
      setTheme(themes[themeIdx])
      return true
    if k.isChar("m"):
      mouseOn = not mouseOn
      app.setMouse(mouseOn)
      return true
    false)

  app.run()

main()
