---
description: Kinematic weight, turning arcs, and pseudo-3D trajectory rules
paths: ["**/entities/**", "**/pitch/**"]
---
## PowerFootball-2d Physics Invariants

CHARACTER KINEMATICS:
  Direct velocity assignment is FORBIDDEN.
  Use: v_t = move_toward(v_{t-1}, v_target, a_eff * delta)
  Turning penalty: a_eff = a_base * (1.0 - γ * (θ / π))
    where θ = arccos(v̂_current · v̂_target)

PSEUDO-3D BALL:
  z(t+Δt) = z(t) + vz(t)*Δt - 0.5*g*(Δt)²
  Sprite Y offset = -z.  Shadow scale = clamp(1.0 - z/300.0, 0.35, 1.0)

COLLISION MATRIX (INVARIANT):
  CharacterBody2D masks Layer 1 + Layer 2 ONLY.
  Ball interaction → Area2D on Layer 4 sensing Layer 3.
  NEVER mask Layer 3 in CharacterBody2D — causes solver velocity zeroing.

## Compounded corrections — verified against the source

### Ball friction is PROPORTIONAL, not a constant deceleration
`Pseudo3DBall.pitch_friction` (default 0.90) scales a velocity-proportional
drag term, plus a flat rest drag:

```gdscript
# Pseudo3DBall.simulate_xy_axis()
var effective_friction: float = pitch_friction * (1.0 - surface_wetness * 0.45)
var drag_force: float = effective_friction * velocity.length()
velocity = velocity.move_toward(Vector2.ZERO, (drag_force + REST_DRAG_FLAT) * delta)
```

The old `FRICTION_SCALE` constant-deceleration `pitch_friction * FRICTION_SCALE * delta`
model has been replaced by the proportional form above. `FRICTION_SCALE` is no
longer used by `simulate_xy_axis()`.

### The ball has TWO ownership properties and they mean different things
Do not guess one from the other:

- `var possessor: Node2D` — who is actively carrying it right now. Set by
  `set_possessor()` from DribbleState/TackleState, cleared by
  `release_possession()`, which `apply_kick()` always calls. Null while the
  ball is loose or in flight.
- `var last_touched_by: HeavyPlayerController` — who struck it last. Set by
  `apply_kick(impulse_xy, impulse_z, kicker)`. Survives the ball going loose,
  which is why PitchBoundary uses it to tell a goal kick from a corner.

"Who has the ball" resolves `possessor` first and only falls back to
`last_touched_by`. Note the differing static types: `possessor` is `Node2D`.

```gdscript
var holder: Node2D = ball_node.possessor
if holder == null:
    holder = ball_node.last_touched_by
```

### Pseudo3DBall.predict_trajectory() returns RENDER points, not ground points
Each point is `sim_pos_xy + Vector2(0.0, -sim_pos_z)` — the height is already
baked into Y. That is correct for drawing an aim arc and wrong for a ground
intercept on an airborne ball. `UtilityMath.calculate_intercept_point()`
returns a true ground position instead.

## FEEL pass (proportional friction / gaussian scatter)

Ball friction is proportional (velocity * coefficient + REST_DRAG_FLAT), not constant. See Pseudo3DBall.simulate_xy_axis(). Surface wetness scales effective_friction. Scatter on shots is Gaussian, not uniform — see ChargeKickState._gaussian_scatter().
