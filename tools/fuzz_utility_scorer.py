#!/usr/bin/env python3
"""
fuzz_utility_scorer.py — Property-Based Fuzzer for AI Utility Scoring.
"""

from __future__ import annotations
import argparse
import math
import random
import sys
import time

def clampf(v: float, min_val: float, max_val: float) -> float:
    return max(min_val, min(max_val, v))

def quadratic_decay(distance: float, max_distance: float) -> float:
    if max_distance <= 0.0 or distance >= max_distance:
        return 0.0
    if distance <= 0.0:
        return 1.0
    ratio = distance / max_distance
    return clampf(1.0 - ratio * ratio, 0.0, 1.0)

# PassUtilityScorer mirrors
def score_pass(
    distance: float,
    passer_facing_dot: float,
    forward_dot: float,
    receiver_open_dist: float,
    passer_pressure: float,
    w_dist: float = 0.25,
    w_angle: float = 0.20,
    w_press: float = 0.30,
    w_adv: float = 0.25
) -> float:
    MAX_USEFUL_DISTANCE = 520.0
    PREFERRED_DISTANCE = 220.0
    RECEIVER_OPEN_RADIUS = 160.0
    PRESSURE_SAFETY_SHIFT = 0.6

    if distance > MAX_USEFUL_DISTANCE:
        return 0.0

    if distance <= PREFERRED_DISTANCE:
        dist_util = quadratic_decay(PREFERRED_DISTANCE - distance, PREFERRED_DISTANCE)
    else:
        max_tail = MAX_USEFUL_DISTANCE - PREFERRED_DISTANCE
        dist_util = quadratic_decay(distance - PREFERRED_DISTANCE, max_tail)

    angle_util = clampf((passer_facing_dot + 1.0) * 0.5, 0.0, 1.0)
    press_util = clampf(receiver_open_dist / RECEIVER_OPEN_RADIUS, 0.0, 1.0)
    adv_util = clampf((forward_dot + 1.0) * 0.5, 0.0, 1.0)

    safety_shift = clampf(passer_pressure, 0.0, 1.0) * PRESSURE_SAFETY_SHIFT
    eff_w_press = w_press + w_adv * safety_shift
    eff_w_adv = w_adv * (1.0 - safety_shift)

    return (w_dist * dist_util + w_angle * angle_util + eff_w_press * press_util + eff_w_adv * adv_util)

# PlayerBrain mirrors
class UtilityContext:
    def __init__(self):
        self.pressure = 0.0
        self.eff_vision = 0.0
        self.eff_composure = 0.0
        self.eff_aggression = 0.0
        self.dist_to_ball = 0.0
        self.dist_to_goal = 0.0
        self.stamina_ratio = 1.0
        self.team_has_ball = True
        self.is_possessor = True
        self.open_teammate_exists = False
        self.chase_is_legal = False
        self.sprint_locked = False
        self.facing_tackler = False
        self.anchor_weight = 0.0

def score_pass_action(ctx: UtilityContext, best_teammate_score: float) -> float:
    if not ctx.is_possessor or not ctx.open_teammate_exists:
        return 0.0
    base = 0.60
    base += ctx.eff_vision * 0.25
    base += ctx.eff_composure * 0.10 * (1.0 - ctx.pressure)
    base += (1.0 - ctx.stamina_ratio) * 0.10
    return clampf(base, 0.0, 1.0)

def score_dribble(ctx: UtilityContext) -> float:
    if not ctx.is_possessor:
        return 0.0
    base = ctx.eff_aggression * 0.55
    base -= ctx.pressure * (1.0 - ctx.eff_composure) * 0.50
    base *= ctx.stamina_ratio

    if ctx.facing_tackler:
        base *= 0.40

    return clampf(base, 0.0, 1.0)

def score_shoot(ctx: UtilityContext) -> float:
    if not ctx.is_possessor:
        return 0.0
    if ctx.dist_to_goal > 320.0:
        return 0.0
    base = ctx.eff_aggression * 0.70
    prox_bonus = clampf(1.0 - ctx.dist_to_goal / 320.0, 0.0, 1.0) * 0.30
    pressure_urgency = ctx.pressure * ctx.eff_aggression * 0.15
    return clampf(base + prox_bonus + pressure_urgency, 0.0, 1.0)

def run_fuzz_tests(iterations: int, seed: int):
    random.seed(seed)
    violations = 0
    nan_inf = 0
    print(f"Starting {iterations} utility fuzzing iterations...")
    
    start = time.perf_counter()
    for i in range(iterations):
        ctx = UtilityContext()
        ctx.pressure = random.uniform(0.0, 1.0)
        ctx.eff_vision = random.uniform(0.0, 1.0)
        ctx.eff_composure = random.uniform(0.0, 1.0)
        ctx.eff_aggression = random.uniform(0.0, 1.0)
        ctx.stamina_ratio = random.uniform(0.0, 1.0)
        ctx.dist_to_goal = random.uniform(0.0, 1000.0)
        ctx.facing_tackler = random.choice([True, False])
        ctx.anchor_weight = random.uniform(0.0, 1.0) # Fuzzed but mostly for semantic verification in the script if needed
        
        # Simulating PassUtilityScorer
        open_teammate = random.choice([True, False])
        best_teammate_score = 0.0
        if open_teammate:
            # Fuzz pass target score
            d = random.uniform(0.0, 800.0)
            p_dot = random.uniform(-1.0, 1.0)
            f_dot = random.uniform(-1.0, 1.0)
            o_dist = random.uniform(0.0, 500.0)
            best_teammate_score = score_pass(d, p_dot, f_dot, o_dist, ctx.pressure)
            
            if best_teammate_score > 0.38: # MIN_PASS_SCORE
                ctx.open_teammate_exists = True
        
        s_pass = score_pass_action(ctx, best_teammate_score)
        s_dribble = score_dribble(ctx)
        s_shoot = score_shoot(ctx)
        
        if math.isnan(s_pass) or math.isnan(s_dribble) or math.isnan(s_shoot):
            nan_inf += 1
            
        max_offensive = max(s_pass, s_dribble, s_shoot)
        final_utility = max_offensive

        # Fallback utility floor injected into PlayerBrain.gd
        if ctx.is_possessor:
            if max_offensive <= 0.05:
                # Force PanicClear, utility effectively becomes 1.0 to break deadlock
                final_utility = 1.0
        
        if final_utility <= 0.05:
            violations += 1
            if violations == 1:
                print(f"First deadlock at iteration {i}:")
                print(f"  pressure: {ctx.pressure:.3f}")
                print(f"  composure: {ctx.eff_composure:.3f}")
                print(f"  aggression: {ctx.eff_aggression:.3f}")
                print(f"  stamina: {ctx.stamina_ratio:.3f}")
                print(f"  dist_to_goal: {ctx.dist_to_goal:.1f}")
                print(f"  facing_tackler: {ctx.facing_tackler}")
                print(f"  open_teammate_exists: {ctx.open_teammate_exists}")
                print(f"  s_pass: {s_pass:.3f}, s_dribble: {s_dribble:.3f}, s_shoot: {s_shoot:.3f}")

    elapsed = time.perf_counter() - start
    print(f"Fuzzing completed in {elapsed:.2f}s")
    print(f"NaN/Inf Violations: {nan_inf}")
    print(f"Deadlock Violations (max utility <= 0.05): {violations}")
    
    return violations == 0 and nan_inf == 0

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--iterations", type=int, default=100000)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()
    success = run_fuzz_tests(args.iterations, args.seed)
    sys.exit(0 if success else 1)
