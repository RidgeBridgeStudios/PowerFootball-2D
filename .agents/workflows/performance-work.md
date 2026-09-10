---
name: performance-work
description: Systematic performance optimization workflow enforcing baseline profiling, zero-allocation invariants, bounded wins, and verification gates.
---

# Workflow: performance-work

Adaptive protocol for profiling, optimizing, and validating hot paths across the 5-layer simulation stack.

## Execution Protocol

1. **Empirical Baseline Measurement:**
   - Measure baseline before touching any code. No modifications without an empirical baseline metric.
   - Delegate to `.agents/skills/perf-benchmark/SKILL.md` for micro-benchmarks:
     - Math solvers: `py -3 tools/benchmark_math.py --iterations 100000`
     - Spatial hash grid: `py -3 tools/spatial_grid_bench.py`
   - For match simulation throughput and frame pacing: `py -3 tools/eval_simulation.py --duration=60`.

2. **Reconnaissance & Invariant Scoping (Zero Unnecessary File Reads):**
   - Never dump reference files like `docs/MATH_SOLVERS.md` or `POWERFOOTBALL_MASTER_VISION.md`.
   - Inspect layer constraints via `py -3 tools/layer_context.py 1` (Physics/Math) or `[1-5]`.
   - Search mathematical solver formulas via `py -3 tools/semantic_search.py "<routine>"`.
   - Extract targeted function logic via `py -3 tools/codebase_slice.py <file> --func <name>`.
   - Check pending roadmap performance items via `py -3 tools/next_task.py`.

3. **Hot-Path Identification & Blast Radius:**
   - Identify candidate bottlenecks with empirical evidence (profiler output, benchmarks, or `eval_simulation.py` telemetry) — never intuition.
   - Calculate static blast radius for candidate files: `py -3 tools/dump_dep_graph.py --blast-radius <target>`.
   - Audit allocation rules: `py -3 tools/lint_allocations.py` to ensure zero allocations and `distance_squared_to()` compliance.

4. **Optimization Proposal (Approval Gate):**
   - Propose bounded, ranked changes with expected latency or throughput impact for each.
   - Enforce invariants: preserve choke points (`MatchWorldModel`, `PlayerBrain`, `HeavyPlayerController`), strict typing, and zero heap allocations (`.new()`, `[]`, `{}`) in 60Hz hot paths.
   - Await user approval before modifying code (Planning Mode).

5. **Incremental Implementation & Benchmark Loop:**
   - Implement one change at a time adhering to strict typing and zero hot-path allocations.
   - Re-benchmark immediately using the relevant benchmark from step 1.
   - Keep only measurable wins; revert neutral or regressive changes immediately.
   - Report empirical before/after numbers (execution time, throughput, or allocation count).

6. **Verification Gate:**
   - Post-write / Fast Gate (10 static linters):
     `py -3 tools/verify_gate.py --fast || python tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast`
   - Pre-turn / Full Battery (linters + fuzzers + simulation):
     `py -3 tools/verify_gate.py --full || python tools/verify_gate.py --full || py -3 tools/verify_gate.py --full`
