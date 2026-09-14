---
trigger: always_on
glob: "**/*.gd"
description: Strict GDScript 2.0 typing contracts, engine invariants, and Gemini 3.8 Flash anti-patterns for Godot 4.7.
---

# GDScript 2.0 & Godot 4.7 Strict Architecture Rules

All GDScript written or edited in PowerFootball-2D must strictly adhere to Godot 4.7-stable, GDScript 2.0 specifications, and repository static analysis gates (`tools/verify_gate.py`).

### 1. Strict Typing Discipline
- Every variable, parameter, and return type must be explicitly typed (`var x: float = 0.0`, `func foo() -> void:`).
- Inferred typing (`:=`) is permitted only when the type is statically unambiguous.
- Collections must be explicitly typed: `Array[Vector2]`, `Dictionary[StringName, Variant]`.

### 2. Forbidden Pythonisms
- Use `null` instead of `None`.
- Use `true` / `false` instead of `True` / `False`.
- Use `func` instead of `def`.
- Use `array.size()` instead of `len(array)`.
- Use `is` instead of `isinstance()`.
- Use `preload("res://...")` instead of `import`.

### 3. GDScript 2.0 Language Invariants
- Lambdas capturing `self`: Capturing `self` inside an anonymous lambda closure is forbidden. Assign `var host: Node = self` first.
- Direct Callable invocation: Never invoke a `Callable` directly (`my_callable(...)`). Always use `my_callable.call(...)` or `.call_deferred(...)`.
- Object-to-string comparisons: Never compare an Object or typed enum directly to a String or StringName literal (`current_phase == "FULL_TIME"`). Compare the enum value (`current_phase == GameManager.MatchPhase.FULL_TIME`) or the object's own typed accessor.

### 4. Hot-Path Performance Rules
- In sorting or candidate loops, always use `distance_squared_to()` to avoid square root penalties.
- Zero transient allocations: Never instantiate `RandomNumberGenerator.new()` or temporary resources inside a per-player/per-event simulation loop (the 60Hz physics loops were archived with the real-time match layer).
- Use StringName literal syntax (`&"string_name"`) for signal names and metadata keys.
