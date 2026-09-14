# entities/ball/ — Ball Physics & Possession State

The ball is the core simulation object. Pseudo-3D (z-axis for height), proportional friction and flat drag, collision with pitch boundaries and posts via CharacterBody2D (Layer 3), and possession state machine.

## Architecture Overview

```
Pseudo3DBall (CharacterBody2D + Sprite2D + Shadow Sprite)
  ├─ x,y velocity (horizontal ground plane)
  ├─ z height (vertical axis, rendered as Y offset on Sprite2D)
  ├─ vz velocity (vertical axis, gravity solver)
  ├─ possessor (Node2D — active carrier, null if loose)
  ├─ last_touched_by (HeavyPlayerController — who kicked/touched last)
  ├─ restart_taker (HeavyPlayerController — set piece taker for double-touch rules)
  ├─ state machine (FlightState, GroundRollState, PossessionState, DeadBallState)
  └─ prediction trajectory (for aim visualization)
```

---

## Pseudo3DBall.gd

**Contract:** Single physics solver for ball. Extends `CharacterBody2D` on `CollisionLayers.LAYER_BALL_PHYSICS` (Layer 3) masking `CollisionLayers.MASK_BALL_PHYSICS` (Layer 1 `PitchWorld` only). Never masks Layer 2 (`PlayerBodies`) to preserve player momentum.

**Critical Exports & Constants:**
- `gravity: float = 580.0` — Pseudo-gravity acceleration pulling ball to turf (px/s²)
- `pitch_friction: float = 0.90` — Ground drag coefficient applied while rolling
- `air_resistance: float = 0.08` — Air drag coefficient applied while airborne
- `surface_wetness: float = 0.0` — 0 = dry, 1 = soaked (scales rolling friction down)
- `restitution: float = 0.68` — Bounce elasticity on ground contact and post rebounds
- `bounce_threshold: float = 40.0` — Vertical speed below which bounce stops and ball settles
- `bounce_friction_loss: float = 0.85` — Horizontal speed retained through bounce
- `rest_speed: float = 4.0` — Speed below which rolling ball is treated as stationary
- `FRICTION_SCALE: float = 200.0` — Scales `pitch_friction` into px/s deceleration
- `REST_DRAG_FLAT: float = 18.0` — Flat deceleration added so ball settles cleanly

**Ownership Properties (DIFFERENT MEANINGS):**

| Property | Meaning | Usage |
|---|---|---|
| `possessor: Node2D` | Active carrier (set by DribbleState) | Who is dribbling NOW |
| `last_touched_by: HeavyPlayerController` | Who touched or kicked last | Differentiates goal kicks from corners |
| `restart_taker: HeavyPlayerController` | Who took the dead-ball restart | Enforces anti-double-touch rules |

**Critical:** Do not guess one from the other.

```gdscript
var holder: Node2D = ball.possessor
if holder == null:
    holder = ball.last_touched_by  # Fallback to last kicker
```

**Physics Formulas:**

Horizontal ground roll deceleration:
```
effective_friction = pitch_friction * FRICTION_SCALE * (1.0 - surface_wetness * 0.45)
total_deceleration = effective_friction + REST_DRAG_FLAT
v_xy(t+Δt) = move_toward(v_xy, Vector2.ZERO, total_deceleration * delta)
```

Vertical height integration:
```
vz(t+Δt) = vz(t) - gravity * delta - vz(t) * air_resistance * delta
z(t+Δt)  = z(t) + 0.5 * (vz(t) + vz(t+Δt)) * delta
```

**Key Methods:**
- `apply_kick(impulse_xy, impulse_z, kicker)` — Strikes ball; clears possessor; sets last_touched_by
- `apply_impulse(impulse_xy, impulse_z)` — Adds momentum without replacing (dribble touches / deflections)
- `release_possession()` — Breaks dribble link; possessor = null
- `set_possessor(carrier)` — Dribble binding; called by DribbleState
- `predict_trajectory(impulse_xy, impulse_z, steps, dt)` → `Array[Vector2]` — Discrete trajectory preview
- `mark_set_piece_restart(taker)` — Arms anti-double-touch constraint for set piece taker
- `register_player_touch(player)` → `bool` — Registers player touch and checks double-touch legality
- `can_player_touch(player)` → `bool` — Checks if player is allowed to touch the ball
- `reset_at(spot)` — Places ball for restart and zeroes velocities
- `freeze()` / `unfreeze()` — Freezes simulation during stoppages

**Rendering:**
- Sprite Y offset = `-position_z` (height baked into Y coordinate)
- Shadow scale = `clamp(1.0 - (position_z / 300.0), 0.35, 1.0)`
- Shadow alpha = `clamp(0.8 - (position_z / 400.0), 0.2, 0.8)`

**Collision Layers:**
- Ball is on Layer 3 (`LAYER_BALL_PHYSICS`)
- Masks Layer 1 (`MASK_BALL_PHYSICS` = `LAYER_PITCH_WORLD`) for walls and goal frames
- CharacterBody2D on Layer 2 (`PlayerBodies`) MUST NOT mask Layer 3

**DO NOT:**
- Access ball.velocity directly for AI logic; use MatchWorldModel.ball_node
- Assume possessor is always valid; check null first
- Directly assign velocity; always use physics methods
- Keep stale references to the ball in other systems; query MatchWorldModel every frame

---

## Ball State Machine

States inherit from `BallState` and dispatch via `BallStateFactory`.

### FlightState (`&"Flight"`)
**Entered:** `is_airborne() == true` (z > 0 or vz > 0)
- Full gravity and air resistance simulation
- Detects ground bounce (`restitution` and `bounce_friction_loss`)
- Detects aerial heading contests via player `AerialHitbox` (Layer 5)

### GroundRollState (`&"GroundRoll"`)
**Entered:** Ball settles on ground (`position_z <= 0` and no possessor)
- Applies rolling friction (`pitch_friction * FRICTION_SCALE + REST_DRAG_FLAT`)
- Settles to complete stop below `rest_speed` (4.0 px/s)

### PossessionState (`&"Possession"`)
**Entered:** Player dribble state binds possession
- Dampens ball velocity and keeps ball offset relative to player
- Loosely bound; turning and tackles allow natural separation

### DeadBallState (`&"DeadBall"`)
**Entered:** `is_frozen == true` during set pieces, fouls, and celebrations
- Motion paused until restart

---

## Foot Sensor (Layer 4) & Aerial Hitbox (Layer 5)

- **Foot Sensor (Layer 4):** Area2D at player feet sensing Layer 3 (Ball). Pure signal detection for ball capture (`MAX_CAPTURE_HEIGHT = 25.0`).
- **Aerial Hitbox (Layer 5):** Area2D above player shoulders sensing Layer 3 (Ball). Triggers `AerialState` for headers and volleys when ball `z > 25.0`.

---

## Prediction & Aim Arc

**Method:** `predict_trajectory(impulse_xy, impulse_z, steps, dt)` → `Array[Vector2]`

**Returns:** Render points where each point is `(sim_pos_xy + Vector2(0, -sim_pos_z))`
- Height is already baked into Y; suitable for drawing aim preview
- NOT suitable for ground-plane intercept on airborne ball

**For ground intercept on airborne ball:**
- Use `UtilityMath.calculate_intercept_point()` instead
- Returns true ground position, not render position

---

## Friction Model (Critical for AI)

Ball friction deceleration is a PRODUCT:

```gdscript
# CORRECT — passes deceleration in px/s², not bare coefficient
UtilityMath.calculate_intercept_point(
    player_pos, player_speed,
    ball_pos, ball_velocity,
    ball.pitch_friction * Pseudo3DBall.FRICTION_SCALE,  # ← 180.0 px/s² at defaults
    0.08)
```

---

## Possession State Transitions

```
DeadBallState (stoppages / set pieces)
  ↓ (unfreeze)
GroundRollState / FlightState
  ↓ (foot sensor overlap)
PossessionState (player dribble)
  ├─ (strike / pass) → apply_kick() → FlightState / GroundRollState
  ├─ (turn separation) → release_possession() → GroundRollState
  └─ (tackle) → tackle impulse → GroundRollState
```

---

## Key Spatial Queries

**AI intercept:**
```gdscript
var intercept_pos = UtilityMath.calculate_intercept_point(
    player_pos, player_speed,
    ball_pos, ball_velocity,
    ball.pitch_friction * Pseudo3DBall.FRICTION_SCALE,
    0.08)
```

**Ball height:**
```gdscript
var ball_height = MatchWorldModel.instance.ball_position_z
```

**Possession holder:**
```gdscript
var carrier = MatchWorldModel.instance.ball_node.possessor
if carrier == null:
    carrier = MatchWorldModel.instance.ball_node.last_touched_by
```

---

## Notes

- Ball never has a parent; all motion is driven by the physics solver and possessor offsets.
- Ball is a `CharacterBody2D` colliding with Layer 1 (`PitchWorld`) via `move_and_collide()` with elastic rebound.
- Players interact with the ball exclusively through foot sensors (Layer 4) and aerial hitboxes (Layer 5).

