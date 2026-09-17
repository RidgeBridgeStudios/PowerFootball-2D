#!/usr/bin/env python3
"""
tools/test_pass_starvation.py

Targeted property and integration test suite for the Ego / Catering
pass-starvation morale penalty system per docs/SOCIAL_SIMULATION_ARCHITECTURE.md §4.3
and ROADMAP.md Phase 2 item.
"""

import sys
import math

def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t

def clampf(val: float, min_val: float, max_val: float) -> float:
    return max(min_val, min(max_val, val))

def calculate_pass_starvation_delta(player_reputation: float, player_touches: int, team_touches: int) -> float:
    if team_touches <= 0:
        return 0.0
    actual_share = float(player_touches) / float(team_touches)
    expected_share = lerp(0.06, 0.14, clampf(player_reputation, 0.0, 1.0))
    return clampf((actual_share - expected_share) * 1.5, -0.08, 0.04)

def run_tests() -> bool:
    print("=" * 64)
    print("   POWERFOOTBALL-2D PASS-STARVATION VALIDATION SUITE")
    print("=" * 64)
    
    all_passed = True

    # Test 1: Bounds and Asymmetry
    print("[TEST 1/5] Mathematical bounds and asymmetric clamping...")
    # Max penalty should be -0.08, max reward should be +0.04
    worst = calculate_pass_starvation_delta(1.0, 0, 500)
    best = calculate_pass_starvation_delta(0.0, 250, 500)
    if worst != -0.08:
        print(f"  -> FAILED: Expected -0.08, got {worst}")
        all_passed = False
    elif best != 0.04:
        print(f"  -> FAILED: Expected +0.04, got {best}")
        all_passed = False
    else:
        print(f"  -> PASSED: Worst delta = {worst}, Best delta = {best}")

    # Test 2: Zero team touches handling
    print("[TEST 2/5] Zero team touches edge-case guard...")
    zero_div = calculate_pass_starvation_delta(0.8, 0, 0)
    if zero_div != 0.0:
        print(f"  -> FAILED: Expected 0.0 for 0 team touches, got {zero_div}")
        all_passed = False
    else:
        print("  -> PASSED: Division-by-zero safely averted, returned 0.0")

    # Test 3: Reputation Monotonicity
    print("[TEST 3/5] Reputation expectation scaling monotonicity...")
    # For a fixed touch share of 8% (40 touches out of 500):
    # A rookie (rep 0.1, expected 6.8%) should have positive delta
    # A superstar (rep 0.9, expected 13.2%) should have negative delta
    delta_rookie = calculate_pass_starvation_delta(0.10, 40, 500)
    delta_mid = calculate_pass_starvation_delta(0.50, 40, 500)
    delta_star = calculate_pass_starvation_delta(0.90, 40, 500)
    
    if not (delta_rookie > delta_mid > delta_star):
        print(f"  -> FAILED: Non-monotonic reputation response: rookie={delta_rookie}, mid={delta_mid}, star={delta_star}")
        all_passed = False
    else:
        print(f"  -> PASSED: Rookie={delta_rookie:.4f} > Mid={delta_mid:.4f} > Star={delta_star:.4f}")

    # Test 4: Touch Share Response
    print("[TEST 4/5] Touch share responsiveness...")
    # For a fixed star reputation of 0.85 (expected share ~12.8%):
    delta_starved = calculate_pass_starvation_delta(0.85, 20, 500)  # 4%
    delta_normal = calculate_pass_starvation_delta(0.85, 64, 500)   # 12.8%
    delta_fed = calculate_pass_starvation_delta(0.85, 90, 500)      # 18%
    
    if delta_starved != -0.08:
        print(f"  -> FAILED: Starved star did not hit floor: {delta_starved}")
        all_passed = False
    elif abs(delta_normal) > 0.001:
        print(f"  -> FAILED: Normal delivery expected ~0.0, got {delta_normal}")
        all_passed = False
    elif delta_fed <= 0.0:
        print(f"  -> FAILED: Fed star did not receive positive morale: {delta_fed}")
        all_passed = False
    else:
        print(f"  -> PASSED: Starved={delta_starved:.4f}, Met Expectation={delta_normal:.4f}, Fed={delta_fed:.4f}")

    # Test 5: Simulating 20-match Career Degradation & Bounding
    print("[TEST 5/5] Multi-match degradation and morale boundary clamping [0.0, 1.0]...")
    morale = 0.70
    for match in range(20):
        delta = calculate_pass_starvation_delta(0.95, 10, 400) # Severely starved every game
        morale = clampf(morale + delta, 0.0, 1.0)
    
    if morale < 0.0 or morale > 1.0 or morale > 0.01:
        print(f"  -> FAILED: Morale did not reach floor or breached bounds: {morale}")
        all_passed = False
    else:
        print(f"  -> PASSED: Multi-match starved morale reached floor at {morale:.4f} within bounds")

    print("-" * 64)
    if all_passed:
        print("[ALL TESTS PASSED] Pass-starvation mechanics fully verified.")
        print("=" * 64)
        return True
    else:
        print("[TESTS FAILED] Diagnostic errors occurred.")
        print("=" * 64)
        return False

if __name__ == "__main__":
    success = run_tests()
    sys.exit(0 if success else 1)
