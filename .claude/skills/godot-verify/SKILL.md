---
name: godot-verify
description: Headless GUT verification for Godot 4.7
allowed-tools: ["Bash"]
---

Run:
  ! godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit

If compilation errors exist → extract file path, line number, error message.
  Fix immediately. Re-run /godot-verify. Repeat until clean.
If GUT test failures exist → inspect assertion, update implementation, re-run.
If no addons/gut/ found → run syntax check only:
  godot --headless --check-only --script res://autoloads/MatchWorldModel.gd

## Container fallback (no engine on PATH)

This repository's CI container ships neither a `godot` binary nor `addons/gut/`.
When `command -v godot` fails, run the static checker instead and report the
result as a static check, never as an engine run:

  ! python3 tools/gdcheck.py

`tools/gdcheck.py` parses every `.gd` file and verifies: balanced brackets,
consistent tab indentation, that every identifier used as `Type.MEMBER` or
`obj.method()` against a project class actually exists, that every
`class_name` referenced resolves, that no forbidden Godot 3 API appears, and
that autoload names in `project.godot` map to real files. It is not a
substitute for compiling — say so when reporting.
