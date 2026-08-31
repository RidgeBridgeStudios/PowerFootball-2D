# ANTI_PATTERNS.md — Anti-Hallucination & Architectural Integrity Corpus

This document catalogues canonical failure modes, false assumptions, Godot 4.7 / GDScript 2.0 pitfalls, postmortem discoveries, and architectural violations for autonomous agents (Antigravity, Gemini, Claude, DeepSeek) and human contributors working on **PowerFootball-2D**.

---

## 1. Complete Godot 4.7 / GDScript 2.0 Pitfall Matrix

| Godot 4.7 / GDScript 2.0 Pitfall | Root Cause & Failure Mode | Mandatory Remediation |
|---|---|---|
| **Material Batching Glitch** | Shared shader material overrides player kit colors globally across instanced sprites. | Set `resource_local_to_scene = true` on instanced sprite materials. |
| **Reserved Keyword Collision** | Naming a passing state method `pass()` triggers a GDScript parser syntax error. | Use domain identifiers like `pass_to()` or `execute_pass()`. |
| **Variable Shadowing Warnings** | Method arguments named `ball` or `team` shadow class variables or autoloads. | Prefix parameters with descriptive namespaces (e.g., `p_ball`, `context_ball`). |
| **Nested Collection Typing** | GDScript lacks nested type constraints (e.g. `Dictionary[String, Array[T]]`). | Store basic arrays and apply inline casting (`items[i] as PlayerData`). |
| **Pause Freeze Lockup** | Pausing the scene tree halts unconfigured singleton managers. | Explicitly set `process_mode = PROCESS_MODE_ALWAYS` on coordinator singletons. |
| **Time Unit Mismatch** | Mixing `Time.get_ticks_msec()` (ms) with `delta` (seconds). | Standardize explicit units in variable names (`_msec` vs `_sec`). |
| **`randi_range` Bounds Error** | `randi_range(0, count)` is inclusive, causing out-of-bounds indexing. | Subtract 1 from upper limit: `randi_range(0, count - 1)`. |
| **Synchronized AI CPU Spikes** | Simultaneous AI initialization creates periodic frame-time spikes. | Apply a randomized millisecond jitter offset to initial tick timers. |
| **Signal Order Race Conditions** | UI reads stale state when signals fire before data mutations. | Mutate state arrays completely *before* emitting update signals. |
| **Square Root CPU Overhead** | Calling `distance_to()` in hot sorting loops invokes costly square roots. | Use `distance_squared_to()` for all proximity ranking and target sorting. |
| **Parse-Time Duplicate `var`** | GDScript performs scope checks at parse time; duplicate `var` in unreachable code below early `return` causes fatal compiler failure. | Delete or refactor all downstream unreachable code within the block. |
| **Object vs StringName `==`** | Comparing `current_state` (`PlayerState`) to `StringName` fails at parse time in strict typing. | Compare against explicit string name property (`current_state_name`). |

---

## 2. Engine & GDScript 2.0 Syntax Anti-Patterns

| Anti-Pattern (FORBIDDEN) | Positive Replacement (CANONICAL) | Rationale |
|---|---|---|
| `yield(get_tree().create_timer(1.0), "timeout")` | `await get_tree().create_timer(1.0).timeout` | Godot 4 coroutine syntax replaced `yield()` with native `await`. |
| `class KinematicBody2D` | `class CharacterBody2D` | Godot 4 unified 2D kinematic physics under `CharacterBody2D`. |
| `class RigidBody` | `class RigidBody2D` | Godot 4 requires explicit 2D/3D type differentiation. |
| `var f = File.new(); f.open(...)` | `var f = FileAccess.open(...)` | Godot 4 `FileAccess` and `DirAccess` use static factory constructors. |
| `var d = Directory.new(); d.open(...)` | `var d = DirAccess.open(...)` | `Directory.new()` is deprecated and raises compiler errors in Godot 4. |
| `OS.get_ticks_msec() / 1000.0` | `Time.get_ticks_msec() / 1000.0` | Time queries are consolidated under the `Time` singleton. |
| `export(float) var speed = 10.0` | `@export var speed: float = 10.0` | Godot 4 uses `@export` and `@onready` annotations. |
| `onready var ball = $Ball` | `@onready var ball: Pseudo3DBall = $Ball` | Untyped `@onready` variables violate strict typing rules. |

---

## 3. Strict Type System & Autoload Invariants

### Anti-Pattern 3.1: Untyped Declarations
```gdscript
# FORBIDDEN: Untyped variable, loop iterator, and missing function return type
func calculate_pressure(player, radius):
    var count = 0
    for opponent in opponents:
        if opponent.global_position.distance_to(player.global_position) < radius:
            count += 1
    return count
```
### Positive Pattern 3.1: Strict Typing on Every Declaration
```gdscript
# CANONICAL: Explicit static typing on variables, parameters, and returns
func calculate_pressure(player: HeavyPlayerController, radius: float) -> int:
    var count: int = 0
    for opponent: HeavyPlayerController in opponents:
        if opponent.global_position.distance_squared_to(player.global_position) < radius * radius:
            count += 1
    return count
```

### Anti-Pattern 3.2: Adding `class_name` to an Autoload Singleton Script
```gdscript
# FORBIDDEN in autoloads/MatchWorldModel.gd:
class_name MatchWorldModel  # Causes collision with project.godot [autoload]
extends Node
```
### Positive Pattern 3.2: Autoload Singleton Scripts Omit `class_name`
```gdscript
# CANONICAL in autoloads/MatchWorldModel.gd:
extends Node
# Autoload registration in project.godot registers MatchWorldModel as a global singleton.
```

### Anti-Pattern 3.3: Duplicate Local Variable Declarations
```gdscript
# FORBIDDEN: Declaring 'var target' multiple times in function scopes
func _execute(player: HeavyPlayerController) -> void:
    for a in list_a:
        var target: Node2D = a
    for b in list_b:
        var target: Node2D = b  # Fatal GDScript parse failure
```
### Positive Pattern 3.3: Unique Local Scoping
```gdscript
# CANONICAL: Explicit unique local variable names
func _execute(player: HeavyPlayerController) -> void:
    for a in list_a:
        var target_a: Node2D = a
    for b in list_b:
        var target_b: Node2D = b
```

---

## 4. Five-Layer Simulation Stack & Choke Point Invariants

```text
LAYER 5 - NARRATIVE      PressOffice, TouchlineBubble, WorldEvent log
LAYER 4 - CLUB WORLD     RelationshipGraph, OffPitchEventEngine, TrainingSystem
LAYER 3 - MATCH SOCIAL   MoodSystem (SLUMP/STREAK), StarMarking, SubReactions
LAYER 2 - MATCH AI       UtilityScorer, FormationAnchors, GK, RoleChaseBudgets
LAYER 1 - PHYSICS        Pseudo3DBall, CharacterBody2D, CollisionLayers, SetPieces
```

### Anti-Pattern 4.1: Direct Tree Crawling in AI Decision Loops
```gdscript
# FORBIDDEN in PlayerBrain.gd / Tactical Scorers:
var all_players: Array[Node] = get_tree().get_nodes_in_group(&"players")
for node: Node in all_players:
    # Traverses scene tree, triggers StringName hashing, causes GC pauses
```
### Positive Pattern 4.1: Spatial Queries Route Through `MatchWorldModel.gd`
```gdscript
# CANONICAL: Linear array indexing from process_priority -100 spatial cache
var world: MatchWorldModel = MatchWorldModel.instance
for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
    var pos: Vector2 = world.player_positions[i]
    var vel: Vector2 = world.player_velocities[i]
```

### Anti-Pattern 4.2: Direct Mutation of Player Kinematics from Brain or State
```gdscript
# FORBIDDEN in PlayerBrain.gd or states/*.gd:
player.velocity = target_velocity      # Snaps velocity; bypasses turning penalties
player.global_position = target_pos    # Teleports body; breaks collision resolution
player.move_and_slide()                # Invoking physics step outside HeavyPlayerController
```
### Positive Pattern 4.2: Brain Writes Tactical Intent Only
```gdscript
# CANONICAL: HeavyPlayerController integrates intent into physics
player.movement_intent = (target_pos - player.global_position).normalized()
player.wants_sprint = true
# HeavyPlayerController._physics_process() computes turning penalties, mass scaling, and move_and_slide()
```

### Anti-Pattern 4.3: Direct Cross-System Signal Coupling
```gdscript
# FORBIDDEN: Direct component-to-component signal coupling
manager_director.tactical_shift.connect(hud._on_tactical_shift)
```
### Positive Pattern 4.3: Inter-System Events Propagate Through `GameEvents.gd`
```gdscript
# CANONICAL: Single central event bus for inter-layer communication
GameEvents.manager_formation_changed.emit(team, new_formation)
```

---

## 5. Physics & Collision Matrix Anti-Patterns

### Anti-Pattern 5.1: Masking Layer 3 (Ball) in `CharacterBody2D`
```gdscript
# FORBIDDEN: Setting player collision_mask to include Layer 3 (Ball, bit 3 / value 4)
collision_mask = CollisionLayers.MASK_PLAYER_BODIES | CollisionLayers.LAYER_BALL_PHYSICS
```
*Why this fails:* If the ball is a solid physics obstacle to `CharacterBody2D`, Godot's `move_and_slide()` solver zeroes player velocity upon contact, instantly destroying the kinematic momentum and turning weight model.
### Positive Pattern 5.1: Programmatic Detection via Sensors
```gdscript
# CANONICAL: Player body masks world (1) + players (2). FootSensor (Layer 4) detects Ball (Layer 3).
collision_mask = CollisionLayers.MASK_PLAYER_BODIES
foot_sensor.collision_mask = CollisionLayers.MASK_FOOT_SENSOR
```

### Anti-Pattern 5.2: Dynamic Allocations in Hot-Path Functions
```gdscript
# FORBIDDEN in score_pass(), calculate_intercept_point(), _physics_process():
var breakdown := PassScoreBreakdown.new()  # Heap allocation every candidate per tick
var temp_array: Array = [pos_a, pos_b]     # Dynamic Array literal allocation
var context_dict: Dictionary = {"d": 1.0}  # Dynamic Dictionary literal allocation
```
### Positive Pattern 5.2: Zero-Allocation Math Primitives
```gdscript
# CANONICAL: Primitive float/Vector2 computations without heap allocations
static func score_pass(distance: float, passer_facing_dot: float, ...) -> float:
    var distance_utility: float = UtilityMath.quadratic_decay(distance, MAX_DIST)
    return _weighted_total(distance_utility, ...)
```

---

## 6. AI Tactical & Spatial Logic Anti-Patterns

### Anti-Pattern 6.1: Inverting Role `anchor_weight` Convention
```gdscript
# FORBIDDEN: Treating anchor_weight as free-roam alpha directly
var alpha: float = player.role_config.anchor_weight  # WRONG: 1.0 means rigid anchor!
```
*Why this fails:* In `PlayerRoleConfig`, `anchor_weight = 1.0` means rigidly holding formation anchor, while `0.0` means roaming freely.
### Positive Pattern 6.1: Invert `anchor_weight` to Compute Roam Alpha
```gdscript
# CANONICAL: 1.0 - anchor_weight converts rigid anchor weight to roam alpha
var alpha: float = 0.35
if player.role_config != null:
    alpha = 1.0 - player.role_config.anchor_weight
```

### Anti-Pattern 6.2: Computing Per-Player Defensive Lines Independently
```gdscript
# FORBIDDEN: Each defender calculating their own independent line depth
var my_line_x: float = compute_custom_line_depth(player)
```
### Positive Pattern 6.2: Blending Toward Shared `defensive_line_x`
```gdscript
# CANONICAL: Team backline coordinates depth via MatchWorldModel.defensive_line_x
var team_line_x: float = MatchWorldModel.instance.defensive_line_x[team]
var target_x: float = lerpf(anchor.x, team_line_x, DEFENSIVE_LINE_DEPTH_WEIGHT)
```
