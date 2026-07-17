# Contributing to loom

Thanks for your interest! Issues and PRs are welcome.

## Setup

You need Nim ≥ 2.0 (developed on 2.2.x) — `brew install nim` or
[choosenim](https://github.com/nim-lang/choosenim). No other dependencies.

```sh
git clone https://github.com/adamsjack711-ux/NimTui
cd NimTui
nimble test
```

## Layout

Everything lives in `src/loom/` — see the "How it works" section of the
README for the module map (`reactive` → `widget`/`dsl` → `buffer` →
`term`, orchestrated by `app`). Examples are in `examples/`
(`nimble demo` / `journal` / `chess` build them into `bin/`).

## Tests

`nimble test` runs 8 suites, all headless — no tty needed. Useful seams:

- `renderToString(widget, w, h)` — plain-text snapshot of a widget
- `attrMap(buffer, attr)` — assert on styles, not just characters
- `feedInput` + `pollEvent(0)` — drive the escape-sequence parser
- `renderFrame(app, w, h)` + `processEvent(app, e)` — the full app loop
  (focus, key dispatch, mouse hit-testing) without a terminal

Please add tests with behavior changes. CI runs the suite on macOS and
Linux and smoke-runs the shipped binary for the runner's platform.

## Shipped npm binaries

`npm/dist/<platform>/nimtui` are checked in so CI can smoke-test them
(`--selftest` renders one frame and exits). Rebuild all four with
`sh npm/build-binaries.sh` from the repo root on macOS — the Linux
targets cross-compile through `zig cc` (static musl), so `zig` must be
on PATH.

## Releasing (maintainers)

1. Bump `version` in `loom.nimble` (the source of truth) and
   `npm/package.json`, and add a section to `CHANGELOG.md`.
2. Commit, then tag and push:
   `git tag vX.Y.Z && git push origin main vX.Y.Z`
3. The `release` workflow builds all four binaries, smoke-tests, creates
   a GitHub release with checksummed tarballs (release notes come from
   the CHANGELOG section for that version), and publishes `nimtui` to
   npm. It fails fast if the tag doesn't match `loom.nimble`, and skips
   the npm publish if that version is already live.
