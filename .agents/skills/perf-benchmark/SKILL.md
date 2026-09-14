---
name: perf-benchmark
description: Micro-benchmarks the core mathematical solvers used by the shared maths layer.
---

# Performance Benchmark & Solvers Profiling Skill

Use this workflow to profile execution times, algorithm regressions, and throughput across the critical mathematical solvers.

## Execution Commands

### 1. Mathematical Solvers Micro-Benchmark

```bash
py -3 tools/benchmark_math.py --iterations 100000
```

Evaluates:
- `UtilityMath.calculate_intercept_point()` (8-step bisection ball intercept)
- `UtilityMath.sigmoid()` (Logistic transfer function)
- `UtilityMath.quadratic_decay()` (Proximity falloff curve)
- `UtilityMath.is_lane_blocked()` (Passing lane segment intersection)

### 2. Spatial Hash Grid Latency Benchmark (archived real-time engine)

> The 22-entity spatial hash grid was retired with the real-time match layer;
> `tools/spatial_grid_bench.py` is a retirement candidate, not a current gate.

```bash
py -3 tools/spatial_grid_bench.py
```

Evaluates:
- 22-entity spatial query latency across multiple grid cell sizes (120px, 160px, 200px, 240px).
- Zero-allocation scratch buffer throughput under 60Hz load.
