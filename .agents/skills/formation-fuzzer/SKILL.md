---
name: formation-fuzzer
description: Executes 50,000 randomized property tests asserting tactical formation line depths, boundary clamping, and dynamic accordion stretching when stress-testing spatial math.
---

> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.** This skill governed the
> 22-player physics match engine, which is now archived under `legacy/` behind
> `legacy/.gdignore`. Retained as historical reference for `QuickSimEngine`
> depth work; **do not apply it to current code**. See
> `docs/agent-errata/architecture-pivot.md` and `docs/CORE_INVARIANTS.md`.

# Formation Anchor & Boundary Fuzzing Skill

Stress test `FormationAnchorMath.get_dynamic_anchor_position()` against randomized ball coordinates, pitch bounds, and team tactical phases (`IN_POSSESSION`, `OUT_OF_POSSESSION`, `TRANSITION`).

## When to Use
- When stress-testing formation coordinate calculations against edge-case coordinates in `legacy/`.
- When verifying boundary clamping and numerical stability in spatial algorithms.

## When NOT to Use
- For live quick-sim match validation (use `tools/test_quick_sim.py` instead).
- For general GDScript syntax verification (use `tools/verify_gate.py --fast`).

## Step-by-Step Workflow

1. **Verify Tooling Prerequisite**:
   ```bash
   set -euo pipefail
   test -f tools/fuzz_formations.py || { echo "Error: tools/fuzz_formations.py missing"; exit 1; }
   ```

2. **Execute Property-Based Fuzzer**:
   Run the fuzzer specifying iteration count (choose 10,000 for rapid testing or 50,000 for full verification):
   ```bash
   set -euo pipefail
   # Expected output: 50,000 randomized iterations completing with 0 assertion failures
   py -3 tools/fuzz_formations.py --iterations 50000 --seed 42 || exit 1
   ```

3. **Validation Check**:
   - Confirm 50,000 iterations finish with 0 boundary breaches, 0 line inversions, and 0 NaN/Inf anomalies before proceeding.

## Evaluated Invariants

1. **Boundary Clamping**: Asserts dynamic anchors never breach pitch rect bounds under any extreme ball position or weighting.
2. **Defensive Line Depth Ordering**:
   - Asserts strict depth progression along the attacking axis ($GK \le DEF \le MID \le ATT$ for $+X$; $GK \ge DEF \ge MID \ge ATT$ for $-X$).
   - Guarantees zero line inversions across all tactical phases.
3. **Numerical Safety**: Asserts zero `NaN` or `Inf` floating-point anomalies.

