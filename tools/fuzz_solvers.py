#!/usr/bin/env python3
"""
fuzz_solvers.py — Property-Based Mathematical Solvers & Kinematic Fuzz Tester.

Executes 100,000+ randomized fuzz testing iterations against PowerFootball-2D
mathematical solvers (UtilityMath, Ballistics, Turning Penalty, Intercept Bisection)
to assert zero NaNs, zero division-by-zero errors, strict boundary convergence,
and invariant preservation.

Usage:
    python tools/fuzz_solvers.py [--iterations 100000] [--seed 42]
"""

from __future__ import annotations

import argparse
import math
import random
import sys
import time
from typing import Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")


class Vector2:
    __slots__ = ("x", "y")

    def __init__(self, x: float = 0.0, y: float = 0.0) -> None:
        self.x = float(x)
        self.y = float(y)

    def __add__(self, other: Vector2) -> Vector2:
        return Vector2(self.x + other.x, self.y + other.y)

    def __sub__(self, other: Vector2) -> Vector2:
        return Vector2(self.x - other.x, self.y - other.y)

    def __mul__(self, scalar: float) -> Vector2:
        return Vector2(self.x * scalar, self.y * scalar)

    def __truediv__(self, scalar: float) -> Vector2:
        return Vector2(self.x / scalar, self.y / scalar)

    def dot(self, other: Vector2) -> float:
        return self.x * other.x + self.y * other.y

    def length_squared(self) -> float:
        return self.x * self.x + self.y * self.y

    def length(self) -> float:
        return math.sqrt(self.x * self.x + self.y * self.y)

    def distance_to(self, other: Vector2) -> float:
        dx = self.x - other.x
        dy = self.y - other.y
        return math.sqrt(dx * dx + dy * dy)

    def distance_squared_to(self, other: Vector2) -> float:
        dx = self.x - other.x
        dy = self.y - other.y
        return dx * dx + dy * dy

    def normalized(self) -> Vector2:
        l = self.length()
        if l <= 0.00001:
            return Vector2(0.0, 0.0)
        return Vector2(self.x / l, self.y / l)

    def is_finite(self) -> bool:
        return not (math.isnan(self.x) or math.isnan(self.y) or math.isinf(self.x) or math.isinf(self.y))

    def __repr__(self) -> str:
        return f"Vector2({self.x:.3f}, {self.y:.3f})"


# ---------------------------------------------------------------------------
# Python Mirrors of UtilityMath & Kinematic Equations
# ---------------------------------------------------------------------------
MIN_PREDICT_SPEED = 10.0
INTERCEPT_ITERATIONS = 8


def clampf(v: float, min_val: float, max_val: float) -> float:
    return max(min_val, min(max_val, v))


def calculate_intercept_point(
    p_pos: Vector2,
    p_max_speed: float,
    b_pos: Vector2,
    b_vel: Vector2,
    friction: float,
    reaction_time: float = 0.08,
) -> Vector2:
    b_speed = b_vel.length()
    if b_speed < MIN_PREDICT_SPEED:
        return Vector2(b_pos.x, b_pos.y)

    b_dir = b_vel / b_speed
    safe_friction = max(friction, 10.0)
    t_actual_stop = b_speed / safe_friction
    t_stop = clampf(t_actual_stop, 0.0, 5.0)

    safe_speed = max(p_max_speed, 1.0)
    max_travel = (b_speed * b_speed) / (2.0 * safe_friction)

    lo = 0.0
    hi = t_stop

    for _ in range(INTERCEPT_ITERATIONS):
        mid = (lo + hi) * 0.5
        t_eval = min(mid, t_actual_stop)
        travel = clampf(b_speed * t_eval - 0.5 * safe_friction * t_eval * t_eval, 0.0, max_travel)
        point = b_pos + b_dir * travel
        t_player = p_pos.distance_to(point) / safe_speed + reaction_time
        if t_player <= mid:
            hi = mid
        else:
            lo = mid

    t_final = min(hi, t_actual_stop)
    final_travel = clampf(b_speed * t_final - 0.5 * safe_friction * t_final * t_final, 0.0, max_travel)
    return b_pos + b_dir * final_travel


def closest_point_on_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> Vector2:
    seg = seg_end - seg_start
    seg_len_sq = seg.length_squared()
    if seg_len_sq <= 0.0001:
        return Vector2(seg_start.x, seg_start.y)

    t = clampf((point - seg_start).dot(seg) / seg_len_sq, 0.0, 1.0)
    return seg_start + seg * t


def distance_squared_to_segment(point: Vector2, seg_start: Vector2, seg_end: Vector2) -> float:
    closest = closest_point_on_segment(point, seg_start, seg_end)
    return closest.distance_squared_to(point)


def is_lane_blocked(passer: Vector2, receiver: Vector2, defender: Vector2, min_clearance: float) -> bool:
    if min_clearance <= 0.0:
        return False
    seg = receiver - passer
    seg_len_sq = seg.length_squared()
    if seg_len_sq <= 0.0001:
        return False

    unconstrained_t = (defender - passer).dot(seg) / seg_len_sq
    if unconstrained_t < -0.05 or unconstrained_t > 1.05:
        return False

    t = clampf(unconstrained_t, 0.0, 1.0)
    closest = passer + seg * t
    return closest.distance_squared_to(defender) < min_clearance * min_clearance


def quadratic_decay(distance: float, max_distance: float) -> float:
    if max_distance <= 0.0 or distance >= max_distance:
        return 0.0
    if distance <= 0.0:
        return 1.0
    ratio = distance / max_distance
    return clampf(1.0 - ratio * ratio, 0.0, 1.0)


def sigmoid(value: float, midpoint: float, steepness: float) -> float:
    try:
        exp_arg = -steepness * (value - midpoint)
        if exp_arg > 700.0:
            return 0.0
        if exp_arg < -700.0:
            return 1.0
        return 1.0 / (1.0 + math.exp(exp_arg))
    except OverflowError:
        return 0.0 if steepness * (value - midpoint) < 0 else 1.0


def turning_penalty_rate(curr_vel: Vector2, intent: Vector2, base_accel: float, turn_penalty_factor: float = 0.35) -> float:
    curr_speed = curr_vel.length()
    if curr_speed <= 20.0 or intent.length_squared() <= 0.0001:
        return base_accel
    dot = curr_vel.normalized().dot(intent.normalized())
    turn_severity = clampf((1.0 - dot) * 0.5, 0.0, 1.0)
    return base_accel * max(0.1, 1.0 - turn_penalty_factor * turn_severity)


def ballistic_trajectory_z(z0: float, vz0: float, g: float, t: float) -> float:
    return max(0.0, z0 + vz0 * t - 0.5 * g * t * t)


def calculate_xg_logit(
    shooter_pos: Vector2,
    goal_centre: Vector2,
    post_left: Vector2,
    post_right: Vector2,
    defender_positions: list[Vector2],
    is_header: bool = False,
) -> float:
    d = shooter_pos.distance_to(goal_centre)
    v_l = post_left - shooter_pos
    v_r = post_right - shooter_pos
    l_l = v_l.length()
    l_r = v_r.length()
    theta = 0.0
    if l_l > 0.0001 and l_r > 0.0001:
        cos_val = clampf(v_l.dot(v_r) / (l_l * l_r), -1.0, 1.0)
        theta = math.acos(cos_val)

    n_block = 0
    for d_pos in defender_positions:
        if is_point_in_triangle(d_pos, shooter_pos, post_left, post_right):
            n_block += 1

    header_val = 1.0 if is_header else 0.0
    return 1.85 - (0.0085 * d) + (1.42 * theta) - (0.45 * float(n_block)) - (0.35 * header_val)


def is_point_in_triangle(pt: Vector2, v1: Vector2, v2: Vector2, v3: Vector2) -> bool:
    d1 = (pt.x - v2.x) * (v1.y - v2.y) - (v1.x - v2.x) * (pt.y - v2.y)
    d2 = (pt.x - v3.x) * (v2.y - v3.y) - (v2.x - v3.x) * (pt.y - v3.y)
    d3 = (pt.x - v1.x) * (v3.y - v1.y) - (v3.x - v1.x) * (pt.y - v1.y)
    has_neg = (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
    has_pos = (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
    return not (has_neg and has_pos)


def calculate_xg(
    shooter_pos: Vector2,
    goal_centre: Vector2,
    post_left: Vector2,
    post_right: Vector2,
    defender_positions: list[Vector2],
    is_header: bool = False,
) -> float:
    z = calculate_xg_logit(shooter_pos, goal_centre, post_left, post_right, defender_positions, is_header)
    z_clamped = clampf(z, -40.0, 40.0)
    return 1.0 / (1.0 + math.exp(-z_clamped))


def calculate_psxg(
    base_xg_logit: float,
    shot_speed: float,
    gk_pos: Vector2,
    goal_centre: Vector2,
    is_on_target: bool,
) -> float:
    if not is_on_target:
        return 0.0
    d_gk = gk_pos.distance_to(goal_centre)
    z_ps = base_xg_logit + (0.003 * shot_speed) - (1.20 * (d_gk / 100.0))
    z_clamped = clampf(z_ps, -40.0, 40.0)
    return 1.0 / (1.0 + math.exp(-z_clamped))


def calculate_packing(
    orig_pos: Vector2,
    dest_pos: Vector2,
    defender_positions: list[Vector2],
    attack_sign: float,
    opp_defensive_line_x: float,
) -> dict:
    packing_count = 0
    impect_count = 0
    x_orig = orig_pos.x * attack_sign
    x_dest = dest_pos.x * attack_sign
    min_x = min(x_orig, x_dest)
    max_x = max(x_orig, x_dest)
    y_orig = orig_pos.y
    y_dest = dest_pos.y
    corridor_half_width = 160.0

    for d_pos in defender_positions:
        d_x = d_pos.x * attack_sign
        if d_x > min_x and d_x < max_x:
            t = (d_x - min_x) / (max_x - min_x) if (max_x - min_x) > 0.0001 else 0.0
            corridor_y = y_orig + (y_dest - y_orig) * t
            if abs(d_pos.y - corridor_y) <= corridor_half_width:
                packing_count += 1
                if (d_pos.x * attack_sign) >= (opp_defensive_line_x * attack_sign - 50.0):
                    impect_count += 1

    return {"packing": packing_count, "impect": impect_count}


def is_progressive_action(
    start_pos: Vector2,
    end_pos: Vector2,
    opp_goal_centre: Vector2,
    in_penalty_start: bool = False,
    in_penalty_end: bool = False,
) -> bool:
    if not in_penalty_start and in_penalty_end:
        return True
    d_start = start_pos.distance_to(opp_goal_centre)
    d_end = end_pos.distance_to(opp_goal_centre)
    if d_start <= 0.0001:
        return False
    return (d_start - d_end) / d_start >= 0.25


def calculate_vaep_value(
    action_type: str,
    orig_xt: float,
    dest_xt: float,
    success: bool,
    is_progressive: bool = False,
    shot_xg: float = 0.0,
    shot_psxg: float = 0.0,
) -> float:
    if action_type == "shot":
        if success:
            return 0.15 + (0.85 * shot_psxg)
        return -0.05 + (0.40 * shot_xg)
    elif action_type == "pass":
        if success:
            delta_xt = dest_xt - orig_xt
            base_val = max(delta_xt, -0.02)
            return (base_val + 0.05) if is_progressive else base_val
        return -(orig_xt * 0.5) - 0.03
    elif action_type == "carry":
        delta_xt = dest_xt - orig_xt
        base_val = max(delta_xt, -0.01)
        return (base_val + 0.04) if is_progressive else base_val
    elif action_type == "tackle":
        return 0.08 + (orig_xt * 0.3)
    elif action_type == "interception":
        return 0.07 + (orig_xt * 0.35)
    elif action_type == "foul":
        return -0.06 - (orig_xt * 0.4)
    return 0.0


# ---------------------------------------------------------------------------
# Fuzz Suite
# ---------------------------------------------------------------------------
def run_fuzz_tests(num_iterations: int = 100000, seed: int = 42) -> bool:
    print(f"[fuzz_solvers] Starting {num_iterations:,} property fuzzing iterations (seed={seed})...")
    random.seed(seed)
    start_time = time.perf_counter()

    nan_inf_violations = 0
    boundary_violations = 0
    monotonicity_violations = 0

    for i in range(1, num_iterations + 1):
        # 1. Randomized Player and Ball states (including degenerate edges)
        p_pos = Vector2(random.uniform(-1000.0, 1000.0), random.uniform(-600.0, 600.0))
        p_speed = random.choice([0.0, 0.1, 1.0, 150.0, 240.0, random.uniform(10.0, 500.0)])
        b_pos = Vector2(random.uniform(-1000.0, 1000.0), random.uniform(-600.0, 600.0))

        # Ball velocities including zeros, tiny values, high speeds
        b_speed = random.choice([0.0, 0.001, 5.0, 9.9, 10.0, 150.0, 800.0, random.uniform(0.0, 1500.0)])
        angle = random.uniform(0.0, 2.0 * math.pi)
        b_vel = Vector2(math.cos(angle) * b_speed, math.sin(angle) * b_speed)

        friction = random.choice([0.0, 1.0, 10.0, 180.0, random.uniform(5.0, 500.0)])
        reaction_time = random.uniform(0.0, 0.5)

        # Fuzz calculate_intercept_point
        pt = calculate_intercept_point(p_pos, p_speed, b_pos, b_vel, friction, reaction_time)
        if not pt.is_finite():
            nan_inf_violations += 1
            print(f"[FAIL] calculate_intercept_point returned NaN/Inf: {pt}")
            break

        # Invariant check: Intercept must lie on ball ray
        if b_speed >= MIN_PREDICT_SPEED:
            b_dir = b_vel.normalized()
            displacement = pt - b_pos
            if displacement.length() > 0.001:
                disp_dir = displacement.normalized()
                # Must be collinear with b_dir (dot close to 1.0)
                if disp_dir.dot(b_dir) < 0.999:
                    boundary_violations += 1

        # 2. Fuzz closest_point_on_segment & distance
        s_start = Vector2(random.uniform(-1000.0, 1000.0), random.uniform(-600.0, 600.0))
        s_end = Vector2(random.uniform(-1000.0, 1000.0), random.uniform(-600.0, 600.0))
        q_pt = Vector2(random.uniform(-1000.0, 1000.0), random.uniform(-600.0, 600.0))

        # Degenerate zero-length segment check
        if random.random() < 0.05:
            s_end = Vector2(s_start.x, s_start.y)

        c_pt = closest_point_on_segment(q_pt, s_start, s_end)
        d_sq = distance_squared_to_segment(q_pt, s_start, s_end)

        if not c_pt.is_finite() or math.isnan(d_sq) or math.isinf(d_sq) or d_sq < -1e-6:
            nan_inf_violations += 1
            print(f"[FAIL] closest_point_on_segment failed: {c_pt}, d_sq={d_sq}")
            break

        # 3. Fuzz is_lane_blocked
        defender = Vector2(random.uniform(-1000.0, 1000.0), random.uniform(-600.0, 600.0))
        clearance = random.choice([-5.0, 0.0, 0.001, 30.0, 100.0, random.uniform(0.0, 200.0)])
        blocked = is_lane_blocked(s_start, s_end, defender, clearance)
        if not isinstance(blocked, bool):
            nan_inf_violations += 1

        # 4. Fuzz quadratic_decay
        d1 = random.uniform(0.0, 500.0)
        d2 = d1 + random.uniform(0.01, 200.0)
        max_d = random.choice([0.0, -10.0, 100.0, 500.0])
        u1 = quadratic_decay(d1, max_d)
        u2 = quadratic_decay(d2, max_d)

        if math.isnan(u1) or math.isnan(u2) or not (0.0 <= u1 <= 1.0) or not (0.0 <= u2 <= 1.0):
            nan_inf_violations += 1
            print(f"[FAIL] quadratic_decay out of bounds: u1={u1}, u2={u2}")
            break
        if max_d > 0.0 and d2 < max_d and u2 > u1 + 1e-9:
            monotonicity_violations += 1

        # 5. Fuzz sigmoid
        val = random.uniform(-1000.0, 1000.0)
        mid = random.uniform(-200.0, 200.0)
        steep = random.uniform(-10.0, 10.0)
        sig_val = sigmoid(val, mid, steep)
        if math.isnan(sig_val) or not (0.0 <= sig_val <= 1.0):
            nan_inf_violations += 1
            print(f"[FAIL] sigmoid NaN or out of [0, 1]: {sig_val}")
            break

        # 6. Fuzz turning penalty rate
        v_curr = Vector2(random.uniform(-300.0, 300.0), random.uniform(-300.0, 300.0))
        v_intent = Vector2(random.uniform(-1.0, 1.0), random.uniform(-1.0, 1.0))
        base_a = random.uniform(100.0, 2000.0)
        eff_a = turning_penalty_rate(v_curr, v_intent, base_a, 0.35)
        if math.isnan(eff_a) or eff_a <= 0.0:
            nan_inf_violations += 1
            print(f"[FAIL] turning_penalty_rate invalid: {eff_a}")
            break

        # 7. Fuzz Ballistic Trajectory
        z0 = random.choice([0.0, 50.0, random.uniform(0.0, 300.0)])
        vz0 = random.uniform(-500.0, 1200.0)
        t_flight = random.uniform(0.0, 5.0)
        z_t = ballistic_trajectory_z(z0, vz0, 980.0, t_flight)
        if math.isnan(z_t) or z_t < 0.0:
            nan_inf_violations += 1
            print(f"[FAIL] ballistic_trajectory_z invalid: {z_t}")
            break

        # 8. Fuzz xG and PSxG Solvers
        g_centre = Vector2(800.0, 0.0)
        p_left = Vector2(800.0, -100.0)
        p_right = Vector2(800.0, 100.0)
        defenders = [Vector2(random.uniform(-800.0, 800.0), random.uniform(-450.0, 450.0)) for _ in range(random.randint(0, 5))]
        is_hdr = random.choice([True, False])
        xg_val = calculate_xg(p_pos, g_centre, p_left, p_right, defenders, is_hdr)
        if math.isnan(xg_val) or not (0.0 <= xg_val <= 1.0):
            nan_inf_violations += 1
            print(f"[FAIL] calculate_xg out of bounds: {xg_val}")
            break

        z_logit = calculate_xg_logit(p_pos, g_centre, p_left, p_right, defenders, is_hdr)
        gk_pos = Vector2(random.uniform(700.0, 850.0), random.uniform(-100.0, 100.0))
        is_on_tgt = random.choice([True, False])
        psxg_val = calculate_psxg(z_logit, b_speed, gk_pos, g_centre, is_on_tgt)
        if math.isnan(psxg_val) or not (0.0 <= psxg_val <= 1.0):
            nan_inf_violations += 1
            print(f"[FAIL] calculate_psxg out of bounds: {psxg_val}")
            break

        # 9. Fuzz Packing and Impect Solvers
        att_sign = random.choice([1.0, -1.0])
        def_line = random.uniform(-600.0, 600.0)
        pack_res = calculate_packing(s_start, s_end, defenders, att_sign, def_line)
        p_cnt = pack_res["packing"]
        i_cnt = pack_res["impect"]
        if p_cnt < 0 or i_cnt < 0 or i_cnt > p_cnt:
            boundary_violations += 1
            print(f"[FAIL] calculate_packing invariant violation: pack={p_cnt}, imp={i_cnt}")
            break

        # 10. Fuzz Progressive Action Solver
        is_prog = is_progressive_action(s_start, s_end, g_centre, random.choice([True, False]), random.choice([True, False]))
        if not isinstance(is_prog, bool):
            nan_inf_violations += 1
            break

        # 11. Fuzz VAEP Solver
        act_type = random.choice(["shot", "pass", "carry", "tackle", "interception", "foul"])
        o_xt = random.uniform(0.0, 1.0)
        d_xt = random.uniform(0.0, 1.0)
        vaep_val = calculate_vaep_value(act_type, o_xt, d_xt, True, is_prog, xg_val, psxg_val)
        if math.isnan(vaep_val) or math.isinf(vaep_val):
            nan_inf_violations += 1
            print(f"[FAIL] calculate_vaep_value returned NaN/Inf: {vaep_val}")
            break

        if i % 25000 == 0:
            elapsed = time.perf_counter() - start_time
            print(f"  ... verified {i:,} / {num_iterations:,} iterations ({i / elapsed:,.0f} ops/sec)")

    elapsed = time.perf_counter() - start_time
    is_success = (nan_inf_violations == 0 and boundary_violations == 0 and monotonicity_violations == 0)

    print("\n" + "=" * 65)
    print(f"         POWERFOOTBALL-2D PROPERTY FUZZING REPORT            ")
    print("=" * 65)
    print(f" Total Iterations:        {num_iterations:,}")
    print(f" Execution Time:          {elapsed:.2f}s ({num_iterations / elapsed:,.0f} ops/sec)")
    print(f" NaN / Inf Violations:    {nan_inf_violations}")
    print(f" Boundary Violations:     {boundary_violations}")
    print(f" Monotonicity Violations: {monotonicity_violations}")
    print(f" Final Verdict:           {'PASSED (0 errors)' if is_success else 'FAILED'}")
    print("=" * 65 + "\n")

    return is_success


def main() -> int:
    parser = argparse.ArgumentParser(description="Property-Based Mathematical Solvers Fuzz Tester")
    parser.add_argument("--iterations", type=int, default=100000, help="Number of fuzz iterations (default: 100,000)")
    parser.add_argument("--seed", type=int, default=42, help="RNG seed for reproducibility (default: 42)")
    args = parser.parse_args()

    success = run_fuzz_tests(num_iterations=args.iterations, seed=args.seed)
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
