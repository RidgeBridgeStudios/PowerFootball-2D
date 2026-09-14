---
name: eval-sim
description: Executes 60-second headless simulation assertion harness and validates runtime invariants (NaNs, escapes, decision stalls, anchor variance).
---

> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.** This skill governed the
> 22-player physics match engine, which is now archived under `legacy/` behind
> `legacy/.gdignore`. Retained as historical reference for `QuickSimEngine`
> depth work; **do not apply it to current code**. See
> `docs/agent-errata/architecture-pivot.md` and `docs/CORE_INVARIANTS.md`.

# Headless Simulation Evaluation Skill

Use this workflow to run headless simulation verification on match kinematics and AI behavior.

## Execution Command

```bash
py -3 tools/eval_simulation.py --duration=60
```

## Assertion Thresholds & Failure Criteria

The simulation harness verifies:
1. **NaN / Inf floats == 0**: All 22 player positions, velocities, and ball coordinates must remain strictly finite.
2. **Boundary Escapes == 0**: No player or ball may drift outside pitch boundaries without triggering out-of-bounds recovery.
3. **AI Decision Cadence Violations == 0**: 15-frame time-slicing must remain strictly periodic: `(player_index + frame_count) % 15 == 0`.
4. **Anchor Variance Integrity**: Dynamic anchor calculations must remain bounded and stable without jitter.

## Post-Run Actions

- Inspect `eval_report.json` for score, possession, and pass completion telemetry.
- If visual inspection is needed, generate match slices with:
  ```bash
  py -3 tools/dump_match_frames.py --frames=5
  ```
