---
name: formation-audit
description: Audits tactical formation spacing, backline depth, and dynamic accordion stretching across match phases when analyzing tactical coordinate anchors.
---

> [!WARNING]
> **SUPERSEDED — pre-pivot real-time match layer.** This skill governed the
> 22-player physics match engine, which is now archived under `legacy/` behind
> `legacy/.gdignore`. Retained as historical reference for `QuickSimEngine`
> depth work; **do not apply it to current code**. See
> `docs/agent-errata/architecture-pivot.md` and `docs/CORE_INVARIANTS.md`.

# Formation & Tactical Spacing Audit Skill

Audit tactical formation anchor coordinates and evaluate dynamic accordion stretching across match phases.

## When to Use
- When inspecting historical formation geometry or tactical line depths in `legacy/`.
- When researching spatial math formulas for future quick-sim depth work.

## When NOT to Use
- For live match simulations (PowerFootball-2D is manager-only; real-time matches are retired).
- For career mode fixtures or UI updates (use `CareerManager.simulate_next_fixture()`).
- For general code verification (use `tools/verify_gate.py --fast`).

## Step-by-Step Workflow

1. **Verify Tooling Prerequisite**:
   ```bash
   set -euo pipefail
   test -f tools/formation_ascii.py || { echo "Error: tools/formation_ascii.py missing"; exit 1; }
   ```

2. **Execute Formation Spacing Audit**:
   Run the terminal ASCII renderer for the desired formation layout (e.g. `4-3-3`, `4-4-2`, or `3-5-2`):
   ```bash
   set -euo pipefail
   # Expected output: ASCII terminal diagram displaying player coordinates across phases
   py -3 tools/formation_ascii.py --formation=4-3-3 --all || exit 1
   ```

3. **Validation Check**:
   - Confirm the ASCII pitch layout renders all 11 player anchors within expected pitch bounds before proceeding.
   - Assert defenders maintain coordinated depth along `defensive_line_x` without inversions.

## Supported Formations

- `4-4-2`: Standard balanced double-pivot formation
- `4-3-3`: High-width wing-forward attacking layout
- `3-5-2`: Wingback-driven central overload formation
- `4-2-3-1`: Double-pivot with advanced attacking midfield trio
- `5-3-2`: Low-block counter-attacking formation with back-5

## Evaluated Spacing Metrics

1. **Backline Depth & Alignment**: Asserts defenders maintain coordinated depth along `defensive_line_x`.
2. **Midfield Compactness**: Asserts midfielders maintain 80-160px vertical and horizontal spacing.
3. **Phase Accordion Stretching**:
   - `IN_POSSESSION`: Forward push (+0.08 normalized pitch units scaled by role sensitivity)
   - `OUT_OF_POSSESSION`: Defensive drop (-0.06 normalized pitch units)
   - `TRANSITION`: Neutral anchor recovery

