---
name: perf-benchmark
description: Micro-benchmarks core mathematical solvers, intercept bisections, and spatial query latency.
---

# Performance Benchmark & Solvers Profiling Skill

Use this workflow to profile execution times, algorithm regressions, and throughput across critical mathematical solvers and spatial hashing routines.

## Execution Commands

### 1. Mathematical Solvers Micro-Benchmark

```bash
python tools/benchmark_math.py --iterations 100000
```

Evaluates:
- `UtilityMath.calculate_intercept_point()` (8-step bisection ball intercept)
- `UtilityMath.sigmoid()` (Logistic transfer function)
- `UtilityMath.quadratic_decay()` (Proximity falloff curve)
- `UtilityMath.is_lane_blocked()` (Passing lane segment intersection)

### 2. Spatial Hash Grid Latency Benchmark

```bash
python tools/spatial_grid_bench.py
```

Evaluates:
- 22-entity spatial query latency across multiple grid cell sizes (120px, 160px, 200px, 240px).
- Zero-allocation scratch buffer throughput under 60Hz load.
