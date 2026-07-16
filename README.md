# loom

A reactive terminal UI framework for Nim. Declarative widget trees via a
macro DSL, fine-grained reactivity via signals, a flex layout engine, and
diffed ANSI rendering — compiled to a single zero-dependency binary.

```nim
import loom

let cpu = signal(0.42)

proc view(): Widget =
  tui:
    vbox:
      panel(title = "stats", height = fixed(3)):
        gauge(cpu.get, label = "cpu")
      panel(title = "items"):
        for name in ["alpha", "beta", "gamma"]:
          text(name)

let app = newApp(view)
app.onKey(proc (k: Key): bool =
  if k.isChar("q"): app.quit(); true else: false)
app.run()
```

Set `cpu` from anywhere — a timer, a socket, a subprocess — and the UI
updates itself. No manual redraw calls, no dirty flags, no virtual DOM.

## Why

Nim has excellent low-level terminal libraries (illwill and friends) but no
high-level framework: nothing with reactive state, a layout system, and a
declarative API. loom fills that hole, and Nim's macro system is what makes
the DSL feel native — `tui:` blocks are plain Nim, so `if`, `case`, `for`,
and `let` work anywhere inside the tree.

## How it works

```
Signal ──changes──▶ App marks dirty ──▶ view() rebuilds widget tree
                                              │
   terminal ◀── minimal ANSI diff ◀── render into cell Buffer
```

- **`reactive.nim`** — `Signal[T]` with automatic dependency tracking.
  Reading a signal inside the render pass subscribes it; writing one marks
  the app dirty. Dependencies re-track on every run, so conditional reads
  (`if cond.get: a.get else: b.get`) subscribe exactly what they use.
- **`widget.nim`** — the flex layout engine. Each widget has a `SizeSpec`
  per axis: `fixed(n)` cells, `flex(weight)` share of the remainder, or
  `fit()` measured from content.
- **`buffer.nim`** — a cell grid double buffer. Consecutive frames are
  diffed and only changed cells are written, with minimal cursor moves and
  SGR changes.
- **`term.nim`** — raw mode, alternate screen, SIGWINCH resize handling,
  and an escape-sequence parser for keys (arrows, function keys, ctrl/alt
  chords, UTF-8) and SGR mouse events (click, wheel). POSIX only; no
  ncurses, no external packages. `feedInput` injects bytes for tests and
  programmatic driving.
- **`dsl.nim`** — the `tui` macro. It only rewrites nesting into
  constructor-plus-`add` calls, so everything inside is ordinary Nim.
- **`app.nim`** — the event loop: poll input with timer-aware timeouts,
  dispatch keys (focused widget → global handler → defaults) and mouse
  events (hit-tested against last frame's layout: click focuses and acts —
  select a list row, switch a tab, place the input cursor; wheel scrolls),
  run timers, rebuild when dirty. Tab / shift-tab cycle focus
  automatically; mark a widget `autofocus = true` to start focused.

State lives in signals you own; the view is a pure function of them,
rebuilt per dirty frame and diffed at the cell level (an Elm-style loop
without the boilerplate).

## Widgets

| widget | description |
|---|---|
| `vbox` / `hbox` / `panel` | flex containers; `panel` adds border + title |
| `text` | multiline, alignment, word wrap |
| `gauge` | smooth eighth-block bar, auto green/yellow/red |
| `sparkline` | multi-row block-tick chart, auto-scaled |
| `list` | selectable + scrollable; tails output when non-interactive |
| `table` | auto-sized columns |
| `input` | single-line editor with cursor, rune-aware |
| `tabs` | arrow-key switchable tab bar |
| `spacer` / `rule` | flexible gap / horizontal divider |

All constructors are plain procs — the DSL is optional sugar.

## Demo

A live system dashboard (`ps` process table with reactive filtering, load
gauge + history sparkline, memory, log panel, tabs):

```sh
nimble demo        # or: nim c -d:release examples/dashboard.nim
./bin/dashboard
```

The release binary is ~255 KB and links only libSystem/libc.

## Testing

Widgets render headlessly via `renderToString(widget, w, h)`, so layout
and visuals are unit-testable without a terminal:

```sh
nimble test
```

## Status / roadmap

v0.1 — core is functional and tested. Not yet done:

- wide-glyph (CJK/emoji) cell widths
- scrollable free-form viewport widget
- mouse drag / motion events (click + wheel are supported)
- style themes; Windows (via VT sequences) support

## License

MIT
