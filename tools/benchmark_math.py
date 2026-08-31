#!/usr/bin/env python3
"""
benchmark_math.py — Mathematical Solvers Micro-Benchmark Suite.

Micro-benchmarks critical decision-layer mathematical solvers:
1. `UtilityMath.calculate_intercept_point()` (8-step bisection ball intercept solver)
2. `UtilityMath.sigmoid()` (Logistic transfer function)
3. `UtilityMath.quadratic_decay()` (Proximity falloff curve)
4. `UtilityMath.is_lane_blocked()` (Passing lane segment intersection)

Reports throughput (ops/sec) and execution time.

Usage:
    python tools/benchmark_math.py [--iterations 100000]
"""

from __future__ import annotations

import argparse
import math
import sys
import time

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def clampf(v: float, min_val: float, max_val: float) -> float:
    return max(min_val, min(max_val, v))


def calculate_intercept_point_fast(
    p_x: float, p_y: float,
    p_max_speed: float,
    b_x: float, b_y: float,
    b_vx: float, b_vy: float,
    friction: float,
    reaction_time: float = 0.08,
) -> tuple[float, float]:
    b_speed = math.sqrt(b_vx * b_vx + b_vy * b_vy)
    if b_speed < 10.0:
        return b_x, b_y

    b_dir_x = b_vx / b_speed
    b_dir_y = b_vy / b_speed
    safe_friction = max(friction, 10.0)
    t_actual_stop = b_speed / safe_friction
    t_stop = clampf(t_actual_stop, 0.0, 5.0)

    safe_speed = max(p_max_speed, 1.0)
    max_travel = (b_speed * b_speed) / (2.0 * safe_friction)

    lo = 0.0
    hi = t_stop

    for _ in range(8):
        mid = (lo + hi) * 0.5
        t_eval = min(mid, t_actual_stop)
        travel = clampf(b_speed * t_eval - 0.5 * safe_friction * t_eval * t_eval, 0.0, max_travel)
        pt_x = b_x + b_dir_x * travel
        pt_y = b_y + b_dir_y * travel
        dx = p_x - pt_x
        dy = p_y - pt_y
        t_player = math.sqrt(dx * dx + dy * dy) / safe_speed + reaction_time
        if t_player <= mid:
            hi = mid
        else:
            lo = mid

    t_final = min(hi, t_actual_stop)
    final_travel = clampf(b_speed * t_final - 0.5 * safe_friction * t_final * t_final, 0.0, max_travel)
    return b_x + b_dir_x * final_travel, b_y + b_dir_y * final_travel


def sigmoid(value: float, midpoint: float, steepness: float) -> float:
    return 1.0 / (1.0 + math.exp(-steepness * (value - midpoint)))


def quadratic_decay(distance: float, max_distance: float) -> float:
    if max_distance <= 0.0 or distance >= max_distance:
        return 0.0
    ratio = distance / max_distance
    return clampf(1.0 - ratio * ratio, 0.0, 1.0)


def is_lane_blocked_fast(
    p_x: float, p_y: float,
    r_x: float, r_y: float,
    d_x: float, d_y: float,
    min_clearance: float,
) -> bool:
    if min_clearance <= 0.0:
        return False
    seg_x = r_x - p_x
    seg_y = r_y - p_y
    seg_len_sq = seg_x * seg_x + seg_y * seg_y
    if seg_len_sq <= 0.0001:
        return False

    def_x = d_x - p_x
    def_y = d_y - p_y
    unconstrained_t = (def_x * seg_x + def_y * seg_y) / seg_len_sq
    if unconstrained_t < -0.05 or unconstrained_t > 1.05:
        return False

    t = clampf(unconstrained_t, 0.0, 1.0)
    closest_x = p_x + seg_x * t
    closest_y = p_y + seg_y * t
    dx = closest_x - d_x
    dy = closest_y - d_y
    return (dx * dx + dy * dy) < (min_clearance * min_clearance)


def run_benchmarks(iterations: int = 100_000) -> None:
    print(f"=== PowerFootball-2D Mathematical Solvers Benchmark ===", flush=True)
    print(f"Iterations per benchmark: {iterations:,}\n", flush=True)

    # 1. Benchmark calculate_intercept_point
    t0 = time.perf_counter()
    for _ in range(iterations):
        calculate_intercept_point_fast(100.0, 200.0, 220.0, 0.0, 0.0, 300.0, 150.0, 180.0)
    t1 = time.perf_counter()
    dt_intercept = (t1 - t0) * 1000.0
    ops_intercept = iterations / max(t1 - t0, 1e-9)
    print(f"[1] calculate_intercept_point: {dt_intercept:6.2f} ms ({ops_intercept:,.0f} ops/sec)", flush=True)

    # 2. Benchmark sigmoid
    t0 = time.perf_counter()
    for i in range(iterations):
        sigmoid(float(i % 100) * 0.1, 5.0, 1.2)
    t1 = time.perf_counter()
    dt_sigmoid = (t1 - t0) * 1000.0
    ops_sigmoid = iterations / max(t1 - t0, 1e-9)
    print(f"[2] sigmoid:                  {dt_sigmoid:6.2f} ms ({ops_sigmoid:,.0f} ops/sec)", flush=True)

    # 3. Benchmark quadratic_decay
    t0 = time.perf_counter()
    for i in range(iterations):
        quadratic_decay(float(i % 300), 250.0)
    t1 = time.perf_counter()
    dt_decay = (t1 - t0) * 1000.0
    ops_decay = iterations / max(t1 - t0, 1e-9)
    print(f"[3] quadratic_decay:          {dt_decay:6.2f} ms ({ops_decay:,.0f} ops/sec)", flush=True)

    # 4. Benchmark is_lane_blocked
    t0 = time.perf_counter()
    for _ in range(iterations):
        is_lane_blocked_fast(-200.0, 0.0, 200.0, 100.0, 0.0, 40.0, 45.0)
    t1 = time.perf_counter()
    dt_lane = (t1 - t0) * 1000.0
    ops_lane = iterations / max(t1 - t0, 1e-9)
    print(f"[4] is_lane_blocked:          {dt_lane:6.2f} ms ({ops_lane:,.0f} ops/sec)", flush=True)

    print(f"\n=== All Mathematical Solver Benchmarks Completed Successfully ===", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="Micro-benchmark mathematical solvers.")
    parser.add_argument("--iterations", type=int, default=100_000, help="Number of iterations per solver (default: 100,000).")
    args = parser.parse_args()

    run_benchmarks(iterations=args.iterations)
    return 0


if __name__ == "__main__":
    sys.exit(main())
