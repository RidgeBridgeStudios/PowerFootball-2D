# entities/player/ — Player Controller & Brain

Home to the human and CPU player logic. Heavy movement, stamina, state machine, and utility-scored AI decisions live here.

## Architecture Overview

```
HeavyPlayerController (CharacterBody2D)
  ├─ input (movement, action stick, gamepad deflection)
  ├─ stamina tracking
  ├─ velocity control via move_and_slide()
  ├─ state machine (IdleState, DribbleState, ShotLockState, TackleState, AerialState, etc.)
  │
  └─ PlayerBrain (AI child)
       ├─ utility-scored decision trees
       ├─ time-sliced evaluation (15-frame jitter)
       ├─ tactical context from MatchWorldModel
       └─ writes ONLY to player.movement_intent and player.wants_sprint
```

---

## HeavyPlayerController.gd

**Contract:** Kinematic weight model. Smooth acceleration, friction, turning penalties, stamina drain. All velocity changes route through `move_and_slide()`.

**Critical Exports:**
- `max_acceleration: float` — Base acceleration (default ~210 px/s²)
- `max_speed: float` — Top speed (default ~210 px/s)
- `turning_penalty_curve: Curve` — θ → penalty multiplier
- `current_stamina: float` — 0.0 to 1.0

**Key Methods:**
- `_physics_process(delta)` — Applies weight; moves; handles collisions
- `_apply_input_movement(input_vec)` — Human input → movement_intent
- `apply_kick(impulse_xy, impulse_z, kicker)` — Kicks ball; releases dribble possession
- `get_current_top_speed()` → `float` — Used by AI intercept solver

**Key Signals:**
- Emits to GameEvents (ball_struck, tackle_won, etc.) via state machines

**Movement Contract:**
- Velocity is NEVER directly assigned. Always use `move_toward(v_current, v_target, a_eff * delta)`
- Turning penalty: `a_eff = a_base * (1.0 - penalty_curve(θ / π))`
- No snappy turns; momentum persists

**Physics Layers:**
- Masks layers 1 (terrain) + 2 (other players) ONLY
- MUST NOT mask layer 3 (ball) — zeroes velocity in solver

**Stamina:**
- Drain rate: sprint > running > idle
- Recovery: faster at rest, slower while moving
- Affects movement speed and action availability (tackles, sprints)

**DO NOT:**
- Access Ball or other players directly; use MatchWorldModel queries
- Set velocity outside of move_toward() patterns
- Mask layer 3 in collision matrix
- Query scene tree for spatial data; that is MatchWorldModel's job

---

## PlayerBrain.gd

**Contract:** Autonomous AI agent. Utility-scored decision making per role. Writes ONLY to `player.movement_intent` and `player.wants_sprint` — never velocity, acceleration, or the resolved `is_sprinting`.

**Key Exports:**
- `player_index: int` — World index (set by HeavyPlayerController._ready())
- `decision_interval: float` — Lerped by ManagerDirector (0.15 to 0.35s)
- `role: PlayerRole` — Enum (GOALKEEPER, DEFENDER, MIDFIELDER, OUTFIELD_ATTACKER); affects utility scoring

**Time-Slicing (Stagger):**
- Jitter formula: `ShouldUpdate(i, f) = ((i+f) % 15 == 0)`
- Frame `f` is global `MatchWorldModel.frame_counter`
- Spreads CPU AI across 15 frames; no 22-player decision spike

**Decision Loop (_physics_process if ShouldUpdate):**
1. Build `UtilityContext` from MatchWorldModel positions
2. Score actions: Pass, Chase, Space, Dribble, Formation
3. Pick highest-scoring action
4. Steer toward target via `movement_intent`

**Key Methods:**
- `_evaluate_pass_target()` → Candidate teammate + score
- `_evaluate_chase_ball()` → Ball position + score
- `_evaluate_space_run()` → Optimal off-ball space + score
- `_should_chase_ball()` — Role-budget gate for **outfield players only** (OUTFIELD_ATTACKER, MIDFIELDER, DEFENDER). GOALKEEPER is explicitly excluded via the `_:` default branch (`return false # Goalkeeper handled separately`) — GK movement is driven by the dedicated GoaliePatrol/GoalieDive actions in `evaluate_tactical_action()`, not by this gate.
- `_find_nearby_opponents()` — Scratch buffer for tactical occlusion

**Mood Integration:**
- SLUMP: lowers pass accuracy, movement speed, decision confidence
- STREAK: boosts accuracy, speed, confidence
- Affects kick scatter and action selection weights

**DO NOT:**
- Access ball.velocity directly; use MatchWorldModel.ball_node
- Allocate arrays/vectors in decision blocks; use class-level scratch buffers
- Query scene tree; route everything through MatchWorldModel
- Emit signals; use movement_intent to steer the controller
- Call `get_tree().get_nodes_in_group()` anywhere (instant O(n²) with 22 players)

---

## Player State Machine

States inherit from `PlayerState` and dispatch via `PlayerStateFactory`.

**Base State Pattern:**
```gdscript
class_name IdleState
extends PlayerState

func enter(player: HeavyPlayerController) -> void:
    player.is_charging_kick = false

func physics_update(player: HeavyPlayerController, delta: float) -> void:
    # apply friction, reset movement_intent, evaluate next action
    
func exit(player: HeavyPlayerController) -> void:
    # cleanup if needed
```

### State Enum

- **IdleState** — At rest; no input; waiting
- **DribbleState** — Possessing ball; moving under player input or AI
- **ChargeKickState** — Aiming pass/shot; charging power
- **ShotLockState** — Locked aim during shot; stronger magnetism
- **ThrowInState** — Special possess state for throw-in set piece
- **TackleState** — Challenging opponent; brief lock, snap back
- **AerialState** — Jumping for header; lifting z-axis
- **KnockedDownState** — Tackled/collided; brief recovery animation

**Rules:**
- Only one state active per player at any time
- State transitions happen via `player.change_state(NewState)`
- Physics behavior (friction, magnetism, drag) varies per state
- All state entry/exit is hooked via GameEvents

**Critical Contract:**
- PlayerBrain.movement_intent drives state transitions and target selection
- States apply movement_intent via velocity changes
- States emit GameEvents on significant actions

---

## Player Input (Human)

**Mapping (see CLAUDE.md for controls):**
- Move = left stick (analog) or WASD (binary, full stick if any key pressed)
- Aim = right stick or arrow keys
- Pass/Shot = A/Cross or Space (tap or hold to charge)
- Tackle = B/Circle or E
- Sprint = RT/R2 or Shift
- Super Cancel = RB/R1 or Escape
- Through Ball = X/Square or Q
- Lob = Y/Triangle or F
- Switch = LB/L1 or Tab

**Input Helper Contract:**
- InputHelper emits action signals (move, pass_aim, tackle, etc.)
- HeavyPlayerController listens and writes movement_intent
- PlayerBrain ignores raw input; uses MatchWorldModel state only

---

## Key Spatial Queries (DO NOT VIOLATE)

All position reads must route through MatchWorldModel:

```gdscript
# CORRECT
var ball_pos = MatchWorldModel.instance.ball_node.global_position

# CORRECT
var teammate_dist = MatchWorldModel.instance.nearest_teammate_dist_to(player_index)

# INCORRECT — scene tree polling
var nearby_players = get_tree().get_nodes_in_group("players").filter(...)
```

---

## Notes

- Each player registers itself in MatchWorldModel._ready() via a static counter
- Practice Arena frees 20 of 22 players mid-match; all cached node arrays must be `is_instance_valid()` guarded
- Mood system is stored per player in PlayerData but applied dynamically during AI evaluation
- Traits (planned) will modify utility scoring without creating parallel decision trees
