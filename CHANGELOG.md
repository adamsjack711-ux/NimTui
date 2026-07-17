# Changelog

All notable changes to loom are documented here. The version in
`loom.nimble` is the source of truth; release tags (`vX.Y.Z`) and the
`nimtui` npm package version must match it — the release workflow
enforces this.

## [0.2.1] — 2026-07-17

### Added
- Prebuilt npm binaries for all four shipped platforms: macOS arm64 + x64,
  Linux x64 + arm64 (static musl, cross-compiled through `zig cc`) —
  `npx nimtui` now works on macOS and Linux (`npm/build-binaries.sh`).
- `--selftest` flag on the dashboard: renders one frame headlessly via
  `renderFrame` and exits 0/1, so CI can smoke-test shipped binaries
  without a tty.
- Journal example (`nimble journal`) — split-pane notes app: keyed
  file-tree with folding, markdown-ish preview as wrapped `spans` in a
  `viewport`, raw-source tab, quick-capture input.
- Chess example (`nimble chess`) — full legal hot-seat chess as one
  custom widget (`render` + `handleKey` + `handleMouse`), click-click or
  drag-and-drop, riding the framework's focus/hit-testing/dirty-repaint.
- Tag-triggered release workflow: builds the four binaries, smoke-tests,
  publishes a GitHub release with checksummed tarballs, and publishes to
  npm.

### Fixed
- `spans(wrap = true)` splits words on explicit spaces only — fragments
  that touch without a space (e.g. `` `code` `` followed by `)`) no longer
  grow a phantom space between them.

## [0.2.0] — 2026-07-16

### Added
- Wide-glyph support: CJK and emoji take two columns, handled through
  measurement, clipping, alignment, cursor math, and diffing; compact
  `Cell` (one `Rune` + style, no per-cell heap allocation).
- Theme system (`theme.nim`): default / neon / mono built in; the active
  theme is a signal, so `setTheme` restyles the whole app in one repaint.
- `viewport` — scrollable window over tall content, with scrollbar.
- `spans` rich text, including `wrap = true` styled word-flow.
- Mouse support (opt-in via `newApp(view, mouse = true)`): SGR click,
  wheel, and drag, hit-tested against the last frame's layout — click
  focuses and acts, wheel scrolls lists.
- Autofocus (`autofocus = true`) and `Widget.id` so focus survives
  rebuilds that change the tree shape.
- Keyed list selection (`selectedKey` + `keys`) that follows rows through
  re-sorted data.
- Bracketed paste, modified arrow keys (ctrl/shift/alt), ctrl-z
  suspend/resume, SIGTERM/SIGHUP-safe terminal restore.
- `app.execAsync(cmd, args, done)` — subprocesses off the UI loop; the
  callback runs on the loop when the process exits.
- `nimtui` npm package (darwin-arm64) — the dashboard demo via `npx`.

### Fixed
- Input cursor overflow at the right edge; cursor movement now repaints
  (handled events always mark dirty).
- `pollEvent` always `select()`s, so piped stdin can't block the loop.

## [0.1.0] — 2026-07-15

### Added
- Initial release: `Signal[T]` reactivity with automatic dependency
  tracking, `tui:` macro DSL (plain Nim inside), Box flex layout
  (`fixed` / `flex` / `fit`), diffed-ANSI cell-buffer renderer, raw-mode
  POSIX terminal backend with escape-sequence key parser.
- Widgets: vbox / hbox / panel, text, gauge, sparkline, list, table,
  input, tabs, spacer, rule; order-based tab focus.
- Fully headless test harness (`renderToString`, `renderFrame`,
  `processEvent`, `feedInput`).
