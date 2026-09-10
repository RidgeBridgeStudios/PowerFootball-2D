---
name: formation-audit
description: Audits tactical formation spacing, backline depth, and dynamic accordion stretching across match phases.
---

# Formation & Tactical Spacing Audit Skill

Use this workflow to audit tactical formation anchor coordinates and evaluate dynamic accordion stretching across match phases.

## Execution Command

```bash
py -3 tools/formation_ascii.py --formation=4-3-3 --all
```

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
