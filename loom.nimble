# Package

version       = "0.1.0"
author        = "Jack Adams-Lovell"
description   = "Reactive terminal UI framework for Nim — declarative macro DSL, flex layout, zero dependencies"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.0"

task test, "Run the test suite":
  for f in ["test_buffer", "test_reactive", "test_layout", "test_dsl",
            "test_events", "test_app"]:
    exec "nim c -r --hints:off tests/" & f & ".nim"

task demo, "Build the dashboard demo (release, size-optimized)":
  exec "nim c -d:release --opt:size --hints:off examples/dashboard.nim"
  echo "binary at bin/dashboard"
