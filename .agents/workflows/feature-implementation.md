---
name: feature-implementation
description: Feature request implementation workflow enforcing roadmap alignment, layer context scoping, blast radius analysis, and verification gates.
---

# Workflow: feature-implementation

Adaptive workflow for implementing gameplay, engine, or subsystem features in PowerFootball-2D.

## Execution Protocol

1. **Roadmap & Scope Alignment:**
   - Query roadmap via `py -3 tools/next_task.py` or search with `py -3 tools/semantic_search.py "<feature>"`.
   - Planned: adopt exact wording/scope from `ROADMAP.md`. Unplanned: flag scope boundary and non-goals.

2. **Vision & Invariant Guardrail:**
   - Retrieve layer constraints with `py -3 tools/layer_context.py [1-5]` or `py -3 tools/semantic_search.py "<feature> vision"`.
   - Never dump `POWERFOOTBALL_MASTER_VISION.md`. If request conflicts with invariants or vision, stop and report immediately.

3. **Subsystem Reconnaissance & Blast Radius:**
   - Determine affected layers (1: Physics, 2: AI, 3: Social, 4: Club World, 5: UI).
   - Single-layer: inspect targeted file slices via `py -3 tools/codebase_slice.py <file> --func <name>`.
   - Multi-system (Tier 2/3): run `py -3 tools/dump_dep_graph.py --blast-radius <target>` and query Graphify.

4. **Implementation Plan & Approval Gate:**
   - Multi-subsystem features: adopt `.agents/skills/cross-system-feature/SKILL.md`.
   - Formulate short plan: (a) Intent & non-goals, (b) Affected files, (c) Invariants preserved, (d) Verification commands. Await approval.

5. **Vertical Slice Implementation:**
   - Build minimal observable slice in dependency order: contracts/data -> simulation -> presentation.
   - Enforce invariants: strict typing, zero hot-path allocations (`distance_squared_to`), choke point rules, 6-layer collision matrix.

6. **Conditional Documentation Updates:**
   - Apply AGENTS.md §4: DO NOT touch docs for internal/leaf changes.
   - Public APIs changed: `py -3 tools/dump_api.py` and `py -3 tools/generate_symbols.py`.
   - Dependencies changed: `py -3 tools/dump_dep_graph.py`.
   - Roadmap item completed: mark `[x]` in `ROADMAP.md`.

7. **Verification Gate:**
   - Post-write / Tier 1-2 Fast Gate:
     `py -3 tools/verify_gate.py --fast || python tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast`
   - Pre-turn / Tier 3 Full Battery:
     `py -3 tools/verify_gate.py --full || python tools/verify_gate.py --full || py -3 tools/verify_gate.py --full`
