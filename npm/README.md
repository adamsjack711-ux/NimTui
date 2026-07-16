# nimtui

> Live system dashboard built with [loom](https://github.com/adamsjack711-ux/NimTui), the reactive TUI framework for Nim.

One command, one zero-dependency native binary — a full terminal dashboard showing what the framework does: reactive signals, flex layout, a declarative macro DSL, mouse support, themes, and diffed rendering.

- live process table (keyed selection — stays on your process while the list re-sorts)
- type-to-filter with an autofocused input
- load + memory gauges, history sparkline, scrolling log
- tabs, scrollable help viewport, wide-glyph (CJK/emoji) rendering

## Install

```sh
npm install -g nimtui
nimtui
```

or just try it:

```sh
npx nimtui
```

This installs a prebuilt native binary (the framework and dashboard are written in Nim; the binary links only libSystem).

## Keys

| key | action |
|---|---|
| `q` | quit |
| `tab` | cycle focus (the filter starts focused) |
| `↑/↓`, click, wheel, drag | select processes |
| `←/→` | switch tabs |
| `t` | cycle themes (default → neon → mono) |
| `m` | toggle mouse capture (off = terminal text selection works) |

## The framework

The dashboard is ~100 lines of view code. The interesting part is loom itself — signals with automatic dependency tracking, a `tui:` macro where plain Nim control flow builds the widget tree, and cell-diffed ANSI output:

```nim
let cpu = signal(0.42)

proc view(): Widget =
  tui:
    vbox:
      panel(title = "stats", height = fixed(3)):
        gauge(cpu.get, label = "cpu")
```

Docs and source: **https://github.com/adamsjack711-ux/NimTui**

## Platform support

Currently **macOS (Apple Silicon)** only — that's the prebuilt binary bundled in this package. Other platforms can build from source with nim (`nimble demo` in the repo) and set `NIMTUI_BIN` to the built binary.

## License

MIT
