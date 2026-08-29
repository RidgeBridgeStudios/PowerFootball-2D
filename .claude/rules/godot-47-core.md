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

### ManagerLoader emits NO formation signal — ManagerDirector does
`autoloads/ManagerLoader.gd` is a pure database loader (pool, JSON parse,
`save_managers()`). It has no signals and no match-time behaviour. The
formation event lives on the per-team match brain:

```gdscript
# entities/manager/ManagerDirector.gd — _shift_to()
GameEvents.manager_formation_changed.emit(_team, formation_name)
```

Payload is `(team: int, new_formation: String)` — a NAME, no anchor data.
Anchors are written straight onto each brain by `_apply_formation()`. A
listener wanting positions needs `GameEvents.formation_anchors_changed(team,
new_anchors)`, added for exactly that reason; `new_anchors` maps
`PlayerBrain.player_index` → `Vector2`.

Note `GameEvents` also carries an unrelated `formation_changed(team, name)`,
emitted by `PauseMenu` and `PreGameScreen` for the team-management UI. Three
similarly named signals — check the emitter before connecting.

### "Deprecated" export ≠ unused export
`PlayerBrain.decision_interval` is superseded by the `UPDATE_INTERVAL` frame
stagger for *scheduling*, but `ManagerDirector._apply_brain_overrides()` still
writes it every bind:

```gdscript
brain.decision_interval = lerpf(0.35, 0.15, _live_pressing)
```

Deleting the export would break that write and drop the value out of every
serialised `.tscn`. Grep for writers before removing any `@export`.

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

### This container has no engine and no GUT
Neither a `godot` binary nor `addons/gut/` exists here, so
`godot --headless -s addons/gut/gut_cmdln.gd -gexit` cannot run and its absence
must never be reported as a passing test run. Use `python3 tools/gdcheck.py`
and label the result a static check. It catches undeclared members, unknown
types, unbalanced brackets, mixed indentation, Godot 3 APIs and bad autoload
entries — it does NOT type-check expressions or execute anything.
