---
name: perf-benchmark
description: Profile execution latency and throughput for core mathematical solvers in the shared maths layer when assessing performance regressions.
---

# Performance Benchmark & Solvers Profiling Skill

Benchmark and profile execution times, algorithmic regressions, and throughput across critical mathematical solvers.

## When to Use
- When profiling execution times, algorithmic changes, or throughput in `shared/UtilityMath.gd`.
- When verifying zero transient allocations in mathematical hot paths.
- When validating latency budgets across mathematical solver functions.

## When NOT to Use
- For high-level career world state logic or UI components.
- For quick-sim statistical tuning (use `tools/test_quick_sim.py` instead).
- For general GDScript syntax verification (use `tools/verify_gate.py --fast`).

## Step-by-Step Workflow

1. **Verify Tooling Prerequisite**:
   ```bash
   set -euo pipefail
   test -f tools/benchmark_math.py || { echo "Error: tools/benchmark_math.py missing"; exit 1; }
   ```

2. **Execute Solvers Micro-Benchmark**:
   Run the benchmark harness with configurable sample iterations (choose 10,000 for quick smoke test or 100,000 for rigorous profiling):
   ```bash
   set -euo pipefail
   # Expected output: Benchmark metrics per solver (iterations, elapsed time, throughput ops/sec)
   py -3 tools/benchmark_math.py --iterations 100000 || exit 1
   ```

   Evaluates:
   - `UtilityMath.calculate_intercept_point()` (8-step bisection ball intercept)
   - `UtilityMath.sigmoid()` (Logistic transfer function)
   - `UtilityMath.quadratic_decay()` (Proximity falloff curve)
   - `UtilityMath.is_lane_blocked()` (Passing lane segment intersection)

3. **Validation Check**:
   - Confirm the micro-benchmark output reports 100% completed iterations without `NaN` or `Inf` timing readings before proceeding.
   - Assert all solver latency readings remain within sub-microsecond thresholds.

4. **Optional: Spatial Hash Grid Latency Benchmark (archived real-time engine)**:
   > The 22-entity spatial hash grid was retired with the real-time match layer;
   > `tools/spatial_grid_bench.py` is a retirement candidate, not a current gate.
   ```bash
   set -euo pipefail
   if [ -f tools/spatial_grid_bench.py ]; then
       # Expected output: 22-entity spatial query latency across cell sizes
       py -3 tools/spatial_grid_bench.py || exit 1
   else
       echo "Notice: tools/spatial_grid_bench.py not found (retired legacy engine tool); skipping."
   fi
   ```

