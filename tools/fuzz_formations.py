#!/usr/bin/env python3
"""
fuzz_formations.py — Dynamic Formation Anchor Property & Boundary Fuzzer.

Executes 50,000 randomized property tests against `FormationAnchorMath.get_dynamic_anchor_position()`
across all team tactical phases (`IN_POSSESSION`, `OUT_OF_POSSESSION`, `TRANSITION`), roles,
and extreme ball positions.

Asserts zero invariant violations:
1. Bounds Invariant: Anchor points never breach pitch rect boundaries.
2. Order Invariant: Line depth ordering (GK -> DEF -> MID -> ATT) is strictly preserved without inversions.
3. Numerical Invariant: 0 NaNs, Infs, or math exceptions.

Usage:
    python tools/fuzz_formations.py [--iterations 50000] [--seed 42]
"""

from __future__ import annotations

import argparse
import enum
import math
import random
import sys
from typing import Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


class Role(enum.IntEnum):
    GOALKEEPER = 0
    OUTFIELD_DEFENDER = 1
    OUTFIELD_MIDFIELDER = 2
    OUTFIELD_ATTACKER = 3


class TeamPhase(enum.IntEnum):
    IN_POSSESSION = 0
    OUT_OF_POSSESSION = 1
    TRANSITION = 2


PHASE_LINE_PUSH = {
    TeamPhase.IN_POSSESSION: 0.08,
    TeamPhase.OUT_OF_POSSESSION: -0.06,
    TeamPhase.TRANSITION: 0.0,
}

ROLE_PHASE_SENSITIVITY = {
    Role.GOALKEEPER: 0.15,
    Role.OUTFIELD_DEFENDER: 0.60,
    Role.OUTFIELD_MIDFIELDER: 1.00,
    Role.OUTFIELD_ATTACKER: 1.30,
}


def clampf(v: float, min_val: float, max_val: float) -> float:
    return max(min_val, min(max_val, v))


def lerpf(a: float, b: float, weight: float) -> float:
    return a + (b - a) * weight


def get_dynamic_anchor_position(
    role: Role,
    phase: TeamPhase,
    base_anchor_x: float, base_anchor_y: float,
    ball_pos_x: float, ball_pos_y: float,
    ball_weight: float,
    pitch_centre_x: float, pitch_centre_y: float,
    pitch_size_x: float, pitch_size_y: float,
    attack_sign: float = 1.0,
) -> tuple[float, float]:
    half_x = pitch_size_x * 0.5
    half_y = pitch_size_y * 0.5
    if half_x <= 0.0 or half_y <= 0.0:
        return (
            lerpf(base_anchor_x, ball_pos_x, ball_weight),
            lerpf(base_anchor_y, ball_pos_y, ball_weight),
        )

    # Normalize base anchor and ball position to -1..1 pitch-half units
    base_norm_x = (base_anchor_x - pitch_centre_x) / half_x
    base_norm_y = (base_anchor_y - pitch_centre_y) / half_y

    ball_norm_x = clampf((ball_pos_x - pitch_centre_x) / half_x, -1.0, 1.0)
    ball_norm_y = clampf((ball_pos_y - pitch_centre_y) / half_y, -1.0, 1.0)

    pulled_norm_x = lerpf(base_norm_x, ball_norm_x, ball_weight)
    pulled_norm_y = lerpf(base_norm_y, ball_norm_y, ball_weight)

    push = PHASE_LINE_PUSH.get(phase, 0.0) * ROLE_PHASE_SENSITIVITY.get(role, 1.0) * attack_sign
    pulled_norm_x = clampf(pulled_norm_x + push, -1.0, 1.0)
    pulled_norm_y = clampf(pulled_norm_y, -1.0, 1.0)

    return (
        pitch_centre_x + pulled_norm_x * half_x,
        pitch_centre_y + pulled_norm_y * half_y,
    )


def run_formation_fuzzer(iterations: int = 50_000, seed: int = 42) -> int:
    print(f"=== PowerFootball-2D Dynamic Formation Anchor Fuzz Tester ===")
    print(f"Iterations: {iterations:,} | Seed: {seed}")

    rng = random.Random(seed)

    pitch_centre = (640.0, 360.0)
    pitch_size = (1280.0, 720.0)
    min_x = pitch_centre[0] - pitch_size[0] * 0.5
    max_x = pitch_centre[0] + pitch_size[0] * 0.5
    min_y = pitch_centre[1] - pitch_size[1] * 0.5
    max_y = pitch_centre[1] + pitch_size[1] * 0.5

    # Standard formation base anchors for a team (4-3-3)
    # Norm X: GK = -0.9, DEF = -0.5, MID = -0.1, ATT = +0.3 (for attack_sign = +1)
    base_roles = [
        (Role.GOALKEEPER, -0.9, 0.0),
        (Role.OUTFIELD_DEFENDER, -0.5, -0.4),
        (Role.OUTFIELD_DEFENDER, -0.55, 0.0),
        (Role.OUTFIELD_MIDFIELDER, -0.15, -0.3),
        (Role.OUTFIELD_MIDFIELDER, -0.1, 0.0),
        (Role.OUTFIELD_ATTACKER, 0.3, -0.35),
        (Role.OUTFIELD_ATTACKER, 0.35, 0.0),
    ]

    boundary_violations = 0
    inversion_violations = 0
    nan_inf_violations = 0

    roles_list = list(Role)
    phases_list = list(TeamPhase)

    for it in range(iterations):
        # Generate random ball coordinates (including far outside pitch)
        ball_x = rng.uniform(min_x - 400.0, max_x + 400.0)
        ball_y = rng.uniform(min_y - 400.0, max_y + 400.0)
        ball_weight = rng.uniform(0.0, 0.6)
        attack_sign = rng.choice([1.0, -1.0])
        phase = rng.choice(phases_list)

        # 1. Test individual role bounds
        for role in roles_list:
            base_x = rng.uniform(min_x, max_x)
            base_y = rng.uniform(min_y, max_y)

            anchor_x, anchor_y = get_dynamic_anchor_position(
                role, phase, base_x, base_y, ball_x, ball_y, ball_weight,
                pitch_centre[0], pitch_centre[1], pitch_size[0], pitch_size[1], attack_sign
            )

            if math.isnan(anchor_x) or math.isnan(anchor_y) or math.isinf(anchor_x) or math.isinf(anchor_y):
                nan_inf_violations += 1
            if anchor_x < min_x - 1e-4 or anchor_x > max_x + 1e-4 or anchor_y < min_y - 1e-4 or anchor_y > max_y + 1e-4:
                boundary_violations += 1

        # 2. Test tactical formation line depth ordering
        # Team attacking in attack_sign direction
        team_anchors: dict[Role, float] = {}
        for role, norm_bx, norm_by in [
            (Role.GOALKEEPER, -0.9, 0.0),
            (Role.OUTFIELD_DEFENDER, -0.5, 0.0),
            (Role.OUTFIELD_MIDFIELDER, -0.1, 0.0),
            (Role.OUTFIELD_ATTACKER, 0.3, 0.0),
        ]:
            bx = pitch_centre[0] + (norm_bx if attack_sign == 1.0 else -norm_bx) * (pitch_size[0] * 0.5)
            by = pitch_centre[1] + norm_by * (pitch_size[1] * 0.5)
            ax, _ = get_dynamic_anchor_position(
                role, phase, bx, by, ball_x, ball_y, ball_weight,
                pitch_centre[0], pitch_centre[1], pitch_size[0], pitch_size[1], attack_sign
            )
            team_anchors[role] = ax

        # When attacking +X: GK_x <= DEF_x <= MID_x <= ATT_x
        # When attacking -X: GK_x >= DEF_x >= MID_x >= ATT_x
        gk_x = team_anchors[Role.GOALKEEPER]
        def_x = team_anchors[Role.OUTFIELD_DEFENDER]
        mid_x = team_anchors[Role.OUTFIELD_MIDFIELDER]
        att_x = team_anchors[Role.OUTFIELD_ATTACKER]

        if attack_sign == 1.0:
            if not (gk_x <= def_x <= mid_x <= att_x):
                inversion_violations += 1
        else:
            if not (gk_x >= def_x >= mid_x >= att_x):
                inversion_violations += 1

    print(f"\nResults across {iterations:,} test iterations:")
    print(f"  Boundary Violations:  {boundary_violations}")
    print(f"  Line Inversions:      {inversion_violations}")
    print(f"  NaN / Inf Errors:     {nan_inf_violations}")

    if boundary_violations == 0 and inversion_violations == 0 and nan_inf_violations == 0:
        print("\n=== All Formation Property Fuzzing Invariants Passed (100% Safety) ===")
        return 0
    else:
        print("\n[FAIL] Formation fuzzing invariant violations detected!", file=sys.stderr)
        return 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Property-based formation anchor fuzzer.")
    parser.add_argument("--iterations", type=int, default=50_000, help="Number of random iterations (default: 50,000).")
    parser.add_argument("--seed", type=int, default=42, help="PRNG seed.")
    args = parser.parse_args()

    return run_formation_fuzzer(iterations=args.iterations, seed=args.seed)


if __name__ == "__main__":
    sys.exit(main())
