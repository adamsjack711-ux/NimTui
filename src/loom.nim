## loom — a reactive terminal UI framework for Nim.
##
## Declarative widget trees via the `tui` macro, fine-grained reactivity
## via signals, a flex layout engine, and diffed ANSI rendering. Compiles
## to a single zero-dependency binary.

import loom/[geometry, style, buffer, events, reactive, widget, widgets, dsl, app]
export geometry, style, buffer, events, reactive, widget, widgets, dsl, app

const loomVersion* = "0.1.0"

proc renderToString*(w: Widget, width, height: int): string =
  ## Render a widget tree headlessly to plain text — snapshots for tests,
  ## docs, and debugging.
  var buf = newBuffer(width, height)
  w.render(buf, rect(0, 0, width, height), RenderCtx())
  buf.dump
