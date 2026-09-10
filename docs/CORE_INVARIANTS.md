# CORE_INVARIANTS.md — PowerFootball-2D Architectural & Engine Invariants

**Canonical Single Source of Truth for all Agents (Antigravity, Gemini, Claude, DeepSeek, Human Developers).**

All agents, workflows, and tools reference this document for universal engine contracts, simulation layer rules, and file choke points.

---

## 1. Engine Lock

**Godot 4.7-stable · GDScript 2.0 ONLY · Strictly Typed**

### Prohibited / Strictly Forbidden APIs
| Forbidden | Replacement | Rationale / Context |
|---|---|---|
| `yield(...)` | `await ...` | Godot 4 coroutine syntax |
| `KinematicBody2D` | `CharacterBody2D` | Godot 4 2D physics body |
| `RigidBody` | `RigidBody2D` | 2D physics type specificity |
| `file.open()` / `File.new()` | `FileAccess.open(...)` | Godot 4 FileAccess static API |
| `dir.open()` / `Directory.new()` | `DirAccess.open(...)` | Godot 4 DirAccess static API |
| `OS.get_ticks_msec() / 1000` | `Time.get_ticks_msec()` | Godot 4 Time singleton |
| `export(...)` | `@export` | Godot 4 annotation |
| `onready var` | `@onready var` | Godot 4 annotation |

### Strict Typing Invariant
Every variable declaration, function parameter, and function return type MUST be explicitly typed:
- **CORRECT:** `var velocity: Vector2 = Vector2.ZERO`
- **INCORRECT:** `var velocity = Vector2.ZERO`
- **CORRECT:** `func calculate_steer(target_pos: Vector2, max_speed: float) -> Vector2:`
- **INCORRECT:** `func calculate_steer(target_pos, max_speed):`
- **CORRECT:** `for player: CharacterBody2D in team_players:`
- **INCORRECT:** `for player in team_players:`

### Scene Initialization & Serialization
- Node references must use `@onready var`.
- Exported properties must use `@export var name: Type`.
- Any node instantiated dynamically in GDScript meant for scene persistence must set `.owner = scene_root` before saving.

---

## 2. Simulation Stack

Five-layer upward event propagation model. Events bubble upward; each layer feeds the next:

```text
LAYER 5 — NARRATIVE      PressOffice, TouchlineBubble, WorldEvent log
                            ↑ quote generation from layers 3 & 4
LAYER 4 — CLUB WORLD     RelationshipGraph, OffPitchEventEngine, TrainingSystem
                            ↑ trust decay, dressing room events, injuries
LAYER 3 — MATCH SOCIAL   MoodSystem (SLUMP/STREAK), StarMarking, SubReactions
                            ↑ relationship-weighted passing, foul heat
LAYER 2 — MATCH AI       UtilityScorer, FormationAnchors, GK, RoleChaseBudgets
                            ↑ MatchWorldModel spatial cache, 15-frame jitter
LAYER 1 — PHYSICS        Pseudo3DBall, CharacterBody2D, CollisionLayers, SetPieces
```

### Cross-Layer Architectural Invariant
**Every major feature touches at least two layers.** Single-layer systems are ornamental. A tackle in Layer 1 modifies social heat in Layer 3, adjusts trust in Layer 4, and produces press quotes in Layer 5.

---

## 3. Critical File Contracts (Choke Points)

| File | Contract | Must Never Do |
|---|---|---|
| `autoloads/MatchWorldModel.gd` | ALL spatial position reads route here. Global cache of 22 players + ball. Owns `defensive_line_x` — shared per-team defensive-line depth (world X), recomputed every physics frame. **In possession** the line holds the rest-defence band `LINE_OFFSET_REST_DEFENCE` (240px) behind the ball as counter-attack insurance; **out of possession** it lerps `LINE_OFFSET_DROPPED`→`LINE_OFFSET_PRESSED` by that team's own pressure on the carrier. Also owns `count_bypassed_opponents()` — the packing count `PassUtilityScorer.WEIGHT_PACKING` is priced against. | Call `get_tree().get_nodes_in_group()` inside `_process`/`_physics_process`; compute a per-player defensive line independently instead of reading `defensive_line_x`; allocate per-frame inside `_update_defensive_lines()`. |
| `autoloads/GameEvents.gd` | ALL inter-system events propagate via signals on this bus. Single event hub for physics, AI, match events, and social systems. | Emit cross-system signals from individual components directly; bypass `GameEvents`. |
| `autoloads/GameManager.gd` | Match phase, score, clock, set pieces. Single source of truth for match lifecycle. | Query multiple disparate files for match state; maintain duplicate score or clock state. |
| `entities/player/HeavyPlayerController.gd` | Physics execution body for CharacterBody2D. Owns `velocity`, acceleration curves, top speed clamping, collision resolution, and resolved `is_sprinting` state. Reads `movement_intent` and `wants_sprint` from `PlayerBrain`. | Contain tactical decision-making or utility scoring logic; mask Layer 3 (Ball collision layer). |
| `entities/player/PlayerBrain.gd` | Only the defender `_resolve_defensive_duty()` names `TRIGGER_PRESS` is released from its chase budget by `clamp_chase_target()` — a live press trigger must NOT unclamp the whole team, or both centre-backs abandon the rest-defence band at once. Utility-scored AI decision engine. Runs on 15-frame jitter per `player_index`. Writes ONLY `player.movement_intent` (Vector2 direction) and `player.wants_sprint` (bool/desired speed scale) — never `velocity`, `acceleration`, or `is_sprinting`. | Allocate or scan scene trees inside `_physics_process`; write to `velocity`, `acceleration`, or `is_sprinting` directly. |
| `shared/PlayerData.gd` | Player attributes, traits, relationships. Persists across matches. | Mutate attributes directly from outside call sites; use class methods only. |
| `shared/PlayerRoleConfig.gd` | Data-driven role tuning resource (`.tres` presets in `shared/roles/`). `anchor_weight` (0–1): 1.0 = hold formation anchor rigidly, 0.0 = roam freely — the INVERSE of PlayerBrain's internal roam alpha (`ROLE_SPACE_ALPHA` convention). Consumers convert via `1.0 - anchor_weight` when blending toward open space. `role_config` is null on all entities until a `.tres` is assigned — always guard reads with `if player.role_config != null`. Separate from `DEFENSIVE_LINE_DEPTH_WEIGHT` (X-axis line-depth blend). | Feed `anchor_weight` straight into a roam-weighted alpha (conventions are inverted); treat `ROLE_SPACE_ALPHA` as a float (it is a Dictionary const in `PlayerBrain.gd`); confuse `anchor_weight` with `DEFENSIVE_LINE_DEPTH_WEIGHT`. |
| `shared/CollisionLayers.gd` | Layer bitmask constants. Layer 1 = PitchWorld, Layer 2 = PlayerBodies, Layer 3 = BallPhysicsBody, Layer 4 = FootSensorArea, Layer 5 = AerialHitboxZone, Layer 6 = BoundarySensor. CharacterBody2D masks Layer 1+2 ONLY. | Mask Layer 3 in CharacterBody2D (ball manages its own pseudo-3D height and collision). |
| `docs/course_implementation_specification.md` | READ-ONLY reference specification. Course-derived build phases 1–10, FSM patterns, physics formulas, data models, known gotchas, and agent protocol. Consult before starting any new phase. | Modify this file. It is a reference artifact only. |

---

## 4. Physics & Spatial AI Invariants

### Kinematics & Turning Penalties
- Direct velocity assignment on players is FORBIDDEN.
- **Turn speed retention & recovery** (`HeavyPlayerController.apply_kinematic_weight()`): target pace is bled by turn severity (`TURN_TARGET_BLEED`) and floored at `TURN_RETENTION_FLOOR`; a hard turn taken at pace then arms a ramping cap on top speed that restores full pace over `TURN_RECOVERY_90` / `TURN_RECOVERY_180`. Measured behaviour, which any retune must preserve:

  | Turn | Pace kept through the turn | Time back to full pace |
  |---|---|---|
  | 45° | ~92% | immediate |
  | 90° | ~69% | ~1.2s |
  | 180° | ~13.5% | ~1.8s |

  The reversal floor is anchored to the speed **latched on entry to the turn**, not to the current target: `move_toward` walks the velocity in a straight line through velocity space, so a near-180° turn otherwise passes exactly through the origin (a dead stop). Flooring against the target instead fires on every frame of every turn and pins the body at constant speed all the way round, erasing the chord-shaped pace loss that gives a 45°/90° turn its weight.
- **Slide friction** (`slide_friction_scale`): states may request slicker deceleration for a slide (`TackleState.SLIDE_FRICTION_SCALE`), but the controller alone applies it — a state still never writes `velocity`.
- Acceleration and turning curve:
  $$\vec{v}_t = \text{move\_toward}(\vec{v}_{t-1}, \vec{v}_{\text{target}}, a_{\text{eff}} \cdot \Delta t)$$
  $$a_{\text{eff}} = a_{\text{base}} \cdot \left(1.0 - \gamma \cdot \frac{\theta}{\pi}\right) \quad \text{where } \theta = \arccos(\hat{v}_{\text{current}} \cdot \hat{v}_{\text{target}})$$

### Pseudo-3D Ball Simulation
- Trajectory: $z(t+\Delta t) = z(t) + v_z(t) \cdot \Delta t - 0.5 \cdot g \cdot (\Delta t)^2$.
- Visual offset: Sprite Y offset $= -z$; Shadow scale $= \text{clamp}(1.0 - z / 300.0, 0.35, 1.0)$.
- Ball friction is velocity-proportional drag $+ \text{REST\_DRAG\_FLAT}$, scaled by pitch surface wetness.
- Ball possession: `possessor` (Node2D, active ball carrier) vs `last_touched_by` (HeavyPlayerController, last kicker).

### Zero Scene-Tree Polling & Time-Slicing
- Calling `get_tree().get_nodes_in_group()` inside `_process` or `_physics_process` is FORBIDDEN.
- Spatial reads must query `MatchWorldModel.player_positions[i]`.
- NPC tactical decision updates are time-sliced using frame jitter: `(player_index + frame_count) % 15 == 0`.
- Zero dynamic allocations (`Vector2()`, `Array()`, `RandomNumberGenerator.new()`) inside hot physics/decision loops.

### Declarative Squad Layout
- 22 players are pre-instantiated declarative children in `pitch/PitchScene.tscn` (`PlayerA_*`, `PlayerB_*`).
- Registration uses self-service static counters initialized in `_ready()` and reset in `MatchWorldModel.unregister_all()`.

---

## 5. Static Verification & Autoload Handling

### Verification Choke Point
Static analysis is executed via:
```bash
python3 tools/gdcheck.py || python tools/gdcheck.py || py -3 tools/gdcheck.py
```
**Invariant:** 0 errors required before committing or completing any turn.

### Autoload Handling Contract
`gdcheck.py` parses `[autoload]` in `project.godot` and registers autoload singleton names as known global types.
Godot 4.7+ rejects a `class_name` that collides with an autoload singleton. **Never add a `class_name` to an autoload script to fix a type warning.**
