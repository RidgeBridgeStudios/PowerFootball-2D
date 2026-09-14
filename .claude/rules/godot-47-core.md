---
description: Engine API version lock and GDScript 2.0 syntax invariants
paths: ["**/*.gd"]
---
## Godot 4.7 GDScript 2.0 Invariants

STRICT TYPING: Every var, param, and return type MUST be explicitly typed.
  CORRECT:   var velocity: Vector2 = Vector2.ZERO
  INCORRECT: var velocity = Vector2.ZERO

DEPRECATED API — STRICTLY FORBIDDEN:
  NEVER yield()          → use await
  NEVER KinematicBody2D  → use CharacterBody2D
  NEVER RigidBody        → use RigidBody2D
  NEVER file.open()      → use FileAccess.open()
  NEVER dir.open()       → use DirAccess.open()

SCENE INIT:
  Node refs  → @onready
  Exports    → @export with explicit type

TSCN SERIALIZATION:
  Any node created in GDScript MUST have .owner = scene_root before save
  or it will silently vanish on reload.

## Compounded corrections — verified against the source

### ManagerLoader emits NO formation signal — the manager-mode tactics UI does
`autoloads/ManagerLoader.gd` is a pure database loader (pool, JSON parse,
`save_managers()`). It has no signals and no match-time behaviour. The live
formation event is emitted by the manager-mode tactics panel:

```gdscript
# ui/manager_mode/TacticsPanel.gd
GameEvents.formation_changed.emit(GameManager.TEAM_A, formation)
```

Payload is `(team: int, new_formation: String)` — a NAME, no anchor data.
`formation_changed` and `lineup_changed` are the whole live team-management
signal surface. There is no `formation_anchors_changed` and no per-player brain
to write anchors onto: the pre-pivot `ManagerDirector` (which emitted a
similarly named `manager_formation_changed`) was archived under `legacy/`.
Check the emitter before connecting.

### "Deprecated" export ≠ unused export (historical pre-pivot example)
Before the pivot, `PlayerBrain.decision_interval` was superseded by the
`UPDATE_INTERVAL` frame stagger for *scheduling*, but
`ManagerDirector._apply_brain_overrides()` still wrote it every bind. Both of
those files are archived under `legacy/`, so the concrete example no longer
applies — the rule it illustrates still does: grep for writers before removing
any `@export`. A stale writer is a runtime error, and the serialised value can
silently drop out of every `.tscn`.

### `@onready` / `@export` and the `\b` word-boundary trap
A regex like `\bonready\s+var\b` matches inside `@onready var` — `\b` fires
between `@` and `o`. Any lint rule for Godot 3 leftovers needs a negative
lookbehind, or it reports every correct annotation in the project as an error:

```python
re.compile(r"(?<!@)\bonready\s+var\b")   # correct
re.compile(r"\bonready\s+var\b")         # matches @onready — false positive
```

### `.new()` is inherited, not declared
Static-analysis of `SomeClass.member` must whitelist the universal Object /
RefCounted / Resource surface (`new`, `instantiate`, `duplicate`, `connect`,
`call`, `free`, ...). `TeamData.new()` is valid despite `new` appearing
nowhere in `TeamData.gd`.

### gdcheck resolves autoload singleton names as types — never "fix" this by adding class_name
`tools/gdcheck.py` used to flag every `var x: MatchWorldModel` (or any other
autoload used as a type annotation) as `unknown type — no class_name and not
an engine type`, because it only recognised types with a declared
`class_name`. The now-archived `MatchWorldModel.gd` deliberately had no
`class_name` — Godot 4.7+ rejects a `class_name` that collides with an
autoload's injected global name — so the fix was in the checker, not the
script: `gdcheck.py` now reads `[autoload]` from `project.godot` once
(`parse_autoload_entries()`) and treats every autoload name as a known type in
`check_static_access()`. A live example is `var manager: CareerManager`. If a
type-annotation error ever names an autoload again, the bug is in the
checker's autoload parsing, not a missing `class_name` — do not add one.

`gdcheck.py` also enforces the boot contract: `GameEvents` must be the FIRST
`[autoload]`, the four loaders (`DataLoader`, `RefereeLoader`, `ManagerLoader`,
`StaffLoader`) must precede `WorldEventLog`, and `WorldEventLog` must precede
`CareerManager`.

### This container has no engine and no GUT
Neither a `godot` binary nor `addons/gut/` exists here, so
`godot --headless -s addons/gut/gut_cmdln.gd -gexit` cannot run and its absence
must never be reported as a passing test run. Use `py -3 tools/gdcheck.py`
and label the result a static check. It catches undeclared members, unknown
types, unbalanced brackets, mixed indentation, Godot 3 APIs and bad autoload
entries — it does NOT type-check expressions or execute anything.
