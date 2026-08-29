# entities/ball/ — Ball Physics & Possession State

The ball is the core simulation object. Pseudo-3D (z-axis for height), asymmetric friction, collision detection via Area2D (not CharacterBody2D), and possession state machine.

## Architecture Overview

```
Pseudo3DBall (Area2D + AnimatedSprite2D)
  ├─ x,y velocity (horizontal ground plane)
  ├─ z height (vertical axis, rendered as Y offset)
  ├─ vz velocity (vertical axis, gravity solver)
  ├─ possessor (Node2D — active carrier, null if loose)
  ├─ last_touched_by (HeavyPlayerController — who kicked last)
  ├─ state machine (FreeBall, DribblingState, AirborneState, etc.)
  └─ prediction trajectory (for aim visualization)
```

---

## Pseudo3DBall.gd

**Contract:** Single physics solver for ball. Area2D for goal/boundary detection. No collision masking against CharacterBody2D (possession is bookkeeping, not physics).

**Critical Exports:**
- `pitch_friction: float` — Coefficient, not deceleration (default 0.45)
- `bounce_damping: float` — Elasticity on rebound (default 0.6)
- `max_height: float` — Z-axis limit (default 400px, for heading arcs)
- `gravity: float` — Pseudo-gravity acceleration (default 1500 px/s²)

**Ownership Properties (DIFFERENT MEANINGS):**

| Property | Meaning | Usage |
|---|---|---|
| `possessor: Node2D` | Active carrier (set by DribbleState) | Who is dribbling NOW |
| `last_touched_by: HeavyPlayerController` | Who kicked last | Differentiates goal kicks from corners |

**Critical:** Do not guess one from the other.

```gdscript
var holder: Node2D = ball.possessor
if holder == null:
    holder = ball.last_touched_by  # Fallback to last kicker
```

**Physics Formulas:**

Horizontal velocity with friction:
```
v_xy(t+Δt) = move_toward(v_xy, Vector2.ZERO, pitch_friction * FRICTION_SCALE * delta)
where FRICTION_SCALE = 200.0
```

Vertical velocity with gravity:
```
z(t+Δt) = z(t) + vz(t)*Δt - 0.5*g*(Δt)²
vz(t+Δt) = vz(t) - g*Δt
```

**Key Methods:**
- `apply_kick(impulse_xy, impulse_z, kicker)` — Receives foot sensor impulse; clears possessor; sets last_touched_by
- `release_possession()` — Breaks dribble link; possessor = null
- `set_possessor(carrier)` — Dribble binding; typically called by DribbleState
- `predict_trajectory(steps, delta)` → `Array[Vector2]` — Render points for aim arc
- `simulate_xy_axis(delta)` — Apply horizontal friction
- `simulate_z_axis(delta)` — Apply gravity and ground bounce

**Rendering:**
- Sprite Y offset = -z (height baked into Y coordinate)
- Shadow scale = clamp(1.0 - z/300.0, 0.35, 1.0)
- Ball appears to rise and fall as z changes

**Collision Layers:**
- Ball is on Layer 3 (Ball)
- Area2D senses Layer 1 (Terrain) for boundaries, Layer 2 (Player) for foot contact
- CharacterBody2D MUST NOT mask Layer 3 (would zero velocity in solver)

**DO NOT:**
- Access ball.velocity directly for AI logic; use MatchWorldModel.ball_node
- Assume possessor is always valid; check null first
- Directly assign velocity; always use physics methods
- Keep stale references to the ball in other systems; query MatchWorldModel every frame

---

## Ball State Machine

States inherit from `BallState` and dispatch via `BallStateFactory`.

### FreeBall

**Entered:** apply_kick() or release_possession()
**Responsibilities:**
- Apply friction to xy velocity
- Apply gravity to z velocity
- Detect ground impact (z <= 0); bounce if vz < -bounce_threshold
- Check out-of-bounds via PitchBoundary or emit GameEvents.ball_out_of_bounds

**Key Signals:**
- ball_bounced if z < 0
- ball_out_of_bounds if outside pitch

---

### DribblingState

**Entered:** DribbleState (player) enters on possession grab
**Responsibilities:**
- Dampen ball velocity (heavy possession drag)
- Keep ball offset relative to player (foot sensor position)
- Apply continuous micro-possession magnetism (loose grip, allows sharp turns)

**Magnetism Contract:**
- Position pull = `lerp(ball_pos, foot_pos, magnetism_factor * delta)`
- Magnetism factor varies by state (DribbleState < ShotLockState)
- Player is never parented to ball; separation happens naturally via turning

---

### AirborneState

**Entered:** vz > 0 or z > ground_threshold
**Responsibilities:**
- Full gravity simulation
- Aerodynamic drag (optional; currently linear)
- Detect peak (vz crosses zero) for heading contests
- Detect ground impact

**Notes:**
- No magnetism while airborne (loose ball)
- Area2D collision senses aerial hitbox (Layer 5) for head challenges

---

## Foot Sensor (Layer 4)

The foot sensor is an invisible Area2D child of HeavyPlayerController that fires contact signals for possession and kicks.

**Contract:**
- Detects ball entrance (foot overlaps ball) → DribbleState entry
- Detects ball exit (foot separates) → FreeBall state (graceful separation on sharp turns)
- Foot sensor is NOT a physics layer (no mask/collision); pure signal detection
- Protected in SetPieceState.enter() to prevent re-grab during set pieces

**DO NOT:**
- Query foot sensor position directly; it is an internal detail of possession
- Override foot sensor collision; it is tuned per role (tighter for FWD, wider for DEF)

---

## Prediction & Aim Arc

**Method:** `predict_trajectory(steps, delta)` → `Array[Vector2]`

**Returns:** Render points where each point is `(sim_pos_xy + Vector2(0, -sim_pos_z))`
- Height is already baked into Y; suitable for drawing aim preview
- NOT suitable for ground-plane intercept on airborne ball

**For ground intercept on airborne ball:**
- Use `UtilityMath.calculate_intercept_point()` instead
- Returns true ground position, not render position

---

## Friction Model (Critical for AI)

Ball friction is a PRODUCT, not a coefficient:

```gdscript
# CORRECT — passes acceleration, not coefficient
UtilityMath.calculate_intercept_point(
    player_pos, player_speed,
    ball_pos, ball_velocity,
    ball.pitch_friction * Pseudo3DBall.FRICTION_SCALE,  # ← product (90.0 at defaults)
    delta)

# INCORRECT — coefficient alone under-decelerates 200x
UtilityMath.calculate_intercept_point(..., ball.pitch_friction, delta)
```

---

## Possession State Transitions

```
FreeBall
  ↓ (foot touches)
DribbleState (player grabs)
  ├─ (player passes/shoots) → apply_kick() → FreeBall
  ├─ (sharp turn) → separation → FreeBall
  └─ (tackle interrupts) → TackleState (opponent) → FreeBall

AirborneState
  ↓ (z > threshold or vz > 0)
  ├─ (heading contest) → AerialState (player)
  └─ (ground impact) → FreeBall (bounce or rest)
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

**Ball visibility (for offsides, etc.):**
```gdscript
var ball_height = MatchWorldModel.instance.ball_node.z
if ball_height > AERIAL_THRESHOLD:
    # Ball is in air; different contest rules
```

**Possession holder:**
```gdscript
var carrier = MatchWorldModel.instance.ball_node.possessor
if carrier == null:
    carrier = MatchWorldModel.instance.ball_node.last_touched_by
```

---

## Notes

- Ball never has a parent; all motion is driven by the physics solver and possessor offsets
- Collision detection does NOT use CharacterBody2D to avoid velocity zeroing
- Bounce is controlled by angle and damping; spin is not yet implemented
- Airborne prediction is used for aim visualization; ground intercept uses UtilityMath
- Friction model is a known complexity; document thoroughly if ever changed
