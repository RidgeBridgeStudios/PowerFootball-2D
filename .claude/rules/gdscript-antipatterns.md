---
description: GDScript 2.0 and Godot 4.7 anti-patterns, scope rules, and postmortem compiler safeguards
paths: ["**/*.gd"]
---

# GDScript 2.0 Anti-Patterns & Postmortem Safeguards

## 1. Object vs Literal Equality Comparisons
- NEVER compare an object instance (`current_state`, `player`, `ball`) to a `String` or `StringName` literal.
- Example Violation: `current_state == &"ThrowIn"` (fails parse-time strict typing).
- Canonical Fix: Use the dedicated StringName property: `current_state_name == &"ThrowIn"`.

## 2. Function Scope & Duplicate Declaration Rules
- In GDScript 2.0, local variable scopes are evaluated function-wide at parse time.
- NEVER declare the same variable name with `var` multiple times in the same function (e.g. across loops or branches).
- When adding an early `return`, inspect the remainder of the function to remove any orphaned dead code that could trigger duplicate declaration errors.

## 3. Hot-Path Zero-Allocation Discipline
- The following functions run 60 times per second per entity and MUST NOT allocate heap memory:
  - `score_pass()`
  - `calculate_intercept_point()`
  - `_physics_process()`
  - `get_dynamic_anchor_position()`
- Forbidden inside hot paths:
  - `.new()` (e.g. `RefCounted.new()`, `Array.new()`, `RandomNumberGenerator.new()`)
  - Array literals `[a, b]`
  - Dictionary literals `{"key": val}`
- Always use pre-allocated buffers, primitive float/Vector2 computations, or class-level scratch caches.

## 4. Distance Calculation Discipline
- In proximity sorting, nearest-player queries, and candidate ranking loops, NEVER use `distance_to()`.
- ALWAYS use `distance_squared_to()` to avoid unnecessary square root floating-point instructions.

## 5. StringName Literal Discipline
- Use `&"literal_name"` for all signal emissions, connections, and metadata lookups:
  - `GameEvents.ball_struck.emit(...)`
  - `object.set_meta(&"meta_key", value)`
  - `object.get_meta(&"meta_key", default)`
