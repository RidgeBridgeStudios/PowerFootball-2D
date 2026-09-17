---
name: eval-sim
description: Execute 60-second headless simulation assertion harness and validate runtime invariants (NaNs, escapes, decision stalls, anchor variance) when inspecting legacy match kinematics.
---

> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.** This skill governed the
> 22-player physics match engine, which is now archived under `legacy/` behind
> `legacy/.gdignore`. Retained as historical reference for `QuickSimEngine`
> depth work; **do not apply it to current code**. See
> `docs/agent-errata/architecture-pivot.md` and `docs/CORE_INVARIANTS.md`.

# Headless Simulation Evaluation Skill

Run headless simulation verification on match kinematics and AI behavior for historical reference.

## When to Use
- When evaluating legacy 22-player match engine simulations for historical kinematics reference.
- When validating headless simulation stability across extended multi-second durations.

## When NOT to Use
- For live career mode fixtures or quick-sim matches (use `CareerManager.simulate_next_fixture()` and `tools/test_quick_sim.py`).
- For standard static syntax verification (use `tools/verify_gate.py --fast`).

## Step-by-Step Workflow

1. **Verify Tooling Prerequisite**:
   ```bash
   set -e
   test -f tools/eval_simulation.py || exit 1
   ```

2. **Execute Headless Evaluation**:
   ```bash
   set -e
   py -3 tools/eval_simulation.py --duration=60 || exit 1
   ```

3. **Validation Check**:
   - Confirm `eval_report.json` is generated and confirms zero NaNs, escapes, and decision stalls before proceeding.

4. **Optional: Match Frame Slice Dump**:
   If visual inspection is needed, generate match slices with:
   ```bash
   set -e
   py -3 tools/dump_match_frames.py --frames=5 || exit 1
   ```

## Assertion Thresholds & Failure Criteria

The simulation harness verifies:
1. **NaN / Inf floats == 0**: All 22 player positions, velocities, and ball coordinates must remain strictly finite.
2. **Boundary Escapes == 0**: No player or ball may drift outside pitch boundaries without triggering out-of-bounds recovery.
3. **AI Decision Cadence Violations == 0**: 15-frame time-slicing must remain strictly periodic: `(player_index + frame_count) % 15 == 0`.
4. **Anchor Variance Integrity**: Dynamic anchor calculations must remain bounded and stable without jitter.

