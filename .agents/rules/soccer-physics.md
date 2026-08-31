---
description: Kinematic weight, turning arcs, and pseudo-3D trajectory rules
paths: ["**/entities/**", "**/pitch/**"]
---
## PowerFootball-2d Physics Invariants

CHARACTER KINEMATICS:
  Direct velocity assignment is FORBIDDEN.
  Use: v_t = move_toward(v_{t-1}, v_target, a_eff * delta)
  Turning penalty: a_eff = a_base * (1.0 - gamma * (theta / pi))
    where theta = arccos(v_current . v_target)

PSEUDO-3D BALL:
  z(t+delta) = z(t) + vz(t)*delta - 0.5*g*(delta)^2
  Sprite Y offset = -z.  Shadow scale = clamp(1.0 - z/300.0, 0.35, 1.0)

COLLISION MATRIX (INVARIANT):
  CharacterBody2D masks Layer 1 + Layer 2 ONLY.
  Ball interaction -> Area2D on Layer 4 sensing Layer 3.
  NEVER mask Layer 3 in CharacterBody2D — causes solver velocity zeroing.
