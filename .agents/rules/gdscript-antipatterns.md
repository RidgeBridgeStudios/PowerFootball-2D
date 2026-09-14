---
description: GDScript 2.0 and Godot 4.7 anti-patterns, scope rules, and postmortem compiler safeguards
paths: ["**/*.gd"]
---

# GDScript 2.0 Anti-Patterns & Postmortem Safeguards

## 1. Object vs Literal Equality Comparisons
- NEVER compare an object instance or typed enum (`career`, `fixture`, `current_phase`) to a `String` or `StringName` literal.
- Example Violation: `current_phase == &"FULL_TIME"` (fails parse-time strict typing).
- Canonical Fix: Compare the enum value: `current_phase == GameManager.MatchPhase.FULL_TIME`.

## 2. Function Scope & Duplicate Declaration Rules
- In GDScript 2.0, local variable scopes are evaluated function-wide at parse time.
- NEVER declare the same variable name with `var` multiple times in the same function (e.g. across loops or branches).
- When adding an early `return`, inspect the remainder of the function to remove any orphaned dead code that could trigger duplicate declaration errors.

## 3. Hot-Path Zero-Allocation Discipline
- The manager-only pivot removed the 60Hz per-entity loops, so the old
  `_physics_process()` / `score_pass()` / `get_dynamic_anchor_position()` hot
  paths no longer exist. The discipline still applies to any loop that runs
  per-player or per-event inside a simulation pass, and to the `tools/fuzz_*.py`
  harnesses that call shared solvers in tight loops.
- Forbidden inside those loops:
  - `.new()` (e.g. `RefCounted.new()`, `Array.new()`, `RandomNumberGenerator.new()`)
  - Array literals `[a, b]`
  - Dictionary literals `{"key": val}`
- Always use pre-allocated buffers, primitive float/Vector2 computations, or class-level scratch caches.

## 4. Distance Calculation Discipline
- In proximity sorting, nearest-player queries, and candidate ranking loops, NEVER use `distance_to()`.
- ALWAYS use `distance_squared_to()` to avoid unnecessary square root floating-point instructions.

## 5. StringName Literal Discipline
- Use `&"literal_name"` for all signal emissions, connections, and metadata lookups:
  - `GameEvents.formation_changed.emit(...)`
  - `object.set_meta(&"meta_key", value)`
  - `object.get_meta(&"meta_key", default)`
