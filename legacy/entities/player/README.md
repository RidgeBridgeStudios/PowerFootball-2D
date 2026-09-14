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

**Critical Exports & Defaults:**
- `player_mass: float = 75.0` — Mass in kg (70kg neutral reference; scales acceleration and friction)
- `top_speed: float = 240.0` — Pixels per second at full stick deflection
- `acceleration_time: float = 0.22` — Seconds to reach top speed from standstill
- `friction_time: float = 0.12` — Seconds to coast to a stop from top speed with no input
- `turning_penalty_factor: float = 0.35` — Turning penalty multiplier (0.0 = snappy, 1.0 = heavy penalty)
- `sprint_multiplier: float = 1.45` — Speed multiplier during sprint
- `stamina_max: float = 100.0`, `stamina_drain_rate: float = 18.0`, `stamina_recover_rate: float = 9.0`
- `stamina_sprint_unlock: float = 20.0` — Threshold to unlock sprint after exhaustion
- `stamina: float` — Current stamina level (0.0 to 100.0)

**Key Methods:**
- `apply_kinematic_weight(input_dir, delta)` — Applies weight curve, turning penalty, and momentum
- `apply_external_impulse(impulse)` — Knockback from tackles, aerial duels, and collisions
- `apply_player_data(p, reset_stamina)` — Re-applies squad attributes during substitutions
- `get_current_top_speed()` → `float` — Returns sprinting or base top speed
- `get_ball_in_foot_range()` / `get_ball_in_aerial_range()` → `Pseudo3DBall`

**Key Signals:**
- `stamina_state_changed(ratio: float)`
- `possession_gained` / `possession_lost`

**Movement Contract:**
- Velocity is NEVER directly assigned. Always use `move_toward(target_velocity, rate * delta)`
- Turning penalty:
  ```gdscript
  turn_severity = clampf((1.0 - dot_heading) * 0.5, 0.0, 1.0)
  penalty = turning_penalty_factor * turn_severity
  effective_accel = base_acceleration * maxf(1.0 - penalty, MIN_ACCELERATION_RATIO)
  ```
- Sharp reversals and braking engage scaled friction brake rate.

**Physics Layers:**
- Masks Layer 1 (`PitchWorld`) + Layer 2 (`PlayerBodies`) ONLY.
- MUST NOT mask Layer 3 (`BallPhysicsBody`) — zeroes velocity in solver.

**Stamina:**
- Drains while sprinting (`wants_sprint` and moving).
- Exhaustion latches `sprint_locked = true` and emits `GameEvents.stamina_depleted`.
- Recovers while jogging or idle; unlocks sprint once stamina $\ge 20.0$.

**DO NOT:**
- Access Ball or other players directly; use MatchWorldModel queries
- Set velocity outside of `move_toward()` patterns
- Mask layer 3 in collision matrix
- Query scene tree for spatial data; that is MatchWorldModel's job

---

## PlayerBrain.gd

**Contract:** Autonomous AI agent. Utility-scored decision making per role. Writes ONLY to `player.movement_intent` and `player.wants_sprint` — never velocity, acceleration, or the resolved `is_sprinting`.

**Key Exports:**
- `player_index: int` — World index (set by HeavyPlayerController._ready())
- `decision_interval: float` — Retained for backward-compat; setter drives `set_pressing_intensity()`
- `role: Role` — Enum (`OUTFIELD_ATTACKER`, `OUTFIELD_MIDFIELDER`, `OUTFIELD_DEFENDER`, `GOALKEEPER`)
- `role_config: PlayerRoleConfig` — Resource with `anchor_weight` (1.0 = rigid, 0.0 = free roam; roam alpha = `1.0 - anchor_weight`)

**Time-Slicing (Stagger):**
- Jitter formula: `ShouldUpdate(i, f) = ((i + f) % UPDATE_INTERVAL == 0)`
- Frame `f` is local `_frame_counter` synced to `MatchWorldModel`
- Spreads CPU AI across 15 frames (`UPDATE_INTERVAL = 15`); max 2 brains think per tick

**Decision Loop (_physics_process if ShouldUpdate):**
1. Build `UtilityContext` from MatchWorldModel positions
2. Score actions: Pass, Chase, Space, Dribble, Formation, Shoot
3. Pick highest-scoring action
4. Steer toward target via `movement_intent`

**Key Methods:**
- `_find_best_pass_target()` → Candidate teammate + score via `PassUtilityScorer`
- `_score_chase()` → Ball position + pressing trigger bonuses + score
- `_evaluate_off_ball_target()` → Optimal off-ball channel space + score
- `_should_chase_ball()` — Role-budget gate for **outfield players only** (OUTFIELD_ATTACKER, MIDFIELDER, DEFENDER). GOALKEEPER is explicitly excluded via the `_:` default branch (`return false # Goalkeeper handled separately`) — GK movement is driven by the dedicated GoaliePatrol/GoalieDive actions in `evaluate_tactical_action()`, not by this gate.
- `_find_nearby_opponents()` — Scratch buffer for tactical occlusion

**Mood Integration:**
- SLUMP: lowers pass accuracy, increases risk aversion in pass target selection, lowers composure
- STREAK: boosts accuracy, increases ambition on progressive passes, raises composure
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

### State Names & Classes

- **IdleState (`PlayerState.IDLE`)** — At rest; no input; deceleration to rest
- **MoveState (`PlayerState.MOVE`)** — Off-ball pursuit and running
- **DribbleState (`PlayerState.DRIBBLE`)** — Close possession and continuous micro-magnetism
- **ChargeKickState (`PlayerState.CHARGE_KICK`)** — Aiming and power charge for passes and shots
- **ShotLockState (`PlayerState.SHOT_LOCK`)** — Locked travel-direction carry before striking
- **ThrowInState (`PlayerState.THROW_IN`)** — Sideline throw-in execution
- **TackleState (`PlayerState.TACKLE`)** — Slide/standing tackle challenge with recovery stumble
- **AerialState (`PlayerState.AERIAL`)** — Header, volley, and bicycle kick timing window
- **GoalkeeperDiveState (`PlayerState.GOALKEEPER_DIVE`)** — Goalkeeper commitment, dive velocity, and save window
- **PenaltyKickState (`PlayerState.PENALTY_KICK`)** — Fixed-power penalty kick execution
- **SetPieceFreezeState (`PlayerState.SET_PIECE_FREEZE`)** — Defensive wall and teammate freeze during dead balls

**Rules:**
- Only one state active per player at any time
- State transitions happen via `state_factory.transition_to(NewState)`
- Physics behavior (friction, magnetism, drag) varies per state
- All state entry/exit hooks GameEvents where appropriate

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
