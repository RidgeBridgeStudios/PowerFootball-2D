---
name: formation-fuzzer
description: Executes 50,000 randomized property tests asserting tactical formation line depths, boundary clamping, and dynamic accordion stretching.
---

# Formation Anchor & Boundary Fuzzing Skill

Use this workflow to stress test `FormationAnchorMath.get_dynamic_anchor_position()` against 50,000 randomized ball coordinates, pitch bounds, and team tactical phases (`IN_POSSESSION`, `OUT_OF_POSSESSION`, `TRANSITION`).

## Execution Command

```bash
python tools/fuzz_formations.py --iterations 50000 --seed 42
```

## Evaluated Invariants

1. **Boundary Clamping**: Asserts dynamic anchors never breach pitch rect bounds under any extreme ball position or weighting.
2. **Defensive Line Depth Ordering**:
   - Asserts strict depth progression along the attacking axis ($GK \le DEF \le MID \le ATT$ for $+X$; $GK \ge DEF \ge MID \ge ATT$ for $-X$).
   - Guarantees zero line inversions across all tactical phases.
3. **Numerical Safety**: Asserts zero `NaN` or `Inf` floating-point anomalies.
