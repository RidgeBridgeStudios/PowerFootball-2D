---
name: task-intake-routing
description: Classifies task requests, extracts layer-scoped context without token dumping, performs blast radius checks, and prepares approval plans.
---

# Workflow: task-intake-routing

Enforces token-efficient intake, layer context scoping, and pre-edit verification on every task request.

## Execution Steps

1. **Classify & Map Impact Tier:**
   - **Bug / Gameplay:** Layer 1 (Physics), Layer 2 (AI), or Layer 3 (Social). Tier 2 or 3.
   - **Feature:** Single layer or multi-system. Map to Tier 2/3 and `cross-system-feature` skill if multi-layer.
   - **Performance:** Kinematic or spatial hot paths. Map to `perf-benchmark` skill + `docs/MATH_SOLVERS.md`.
   - **Refactor:** AST/typing cleanups. Map to `ast-refactor` skill + `.agents/rules/gdscript-antipatterns.md`.
   - **Data / Career:** Layer 4 (Club World). Map to `tools/verify_db.py`, `tools/validate_schemas.py`, `.agents/rules/career-mode.md`.
   - **UI / Presentation:** Layer 5 (Narrative/UI). Leaf UI is Tier 1 (`ui/README.md`).
   - **Tooling / Docs:** Standalone scripts or markdown rules. Tier 1.

2. **Scoped Context Loading (Zero File Dumps):**
   - *Layer Context:* Run `py -3 tools/layer_context.py [1-5]` instead of dumping full invariant docs.
   - *Roadmap Tasks:* Run `py -3 tools/next_task.py` instead of reading `ROADMAP.md`.
   - *Errata & Rules:* Consult `docs/agent-errata/<topic>.md` or run `py -3 tools/semantic_search.py "<query>"`. Never read full `AGENTS_ERRATA.md`.
   - *Signatures / Methods:* Run `py -3 tools/codebase_slice.py <file> --func <name>` or `--class-header`.

3. **Structural Reconnaissance & Blast Radius (Tier 2/3):**
   - Query Graphify or run dependency blast radius:
     `py -3 tools/dump_dep_graph.py --blast-radius <target_file>`
   - Inspect affected signals in `autoloads/GameEvents.gd` and spatial calls in `autoloads/MatchWorldModel.gd`.

4. **Formulate Short Plan (Approval Gate):**
   - State: (a) Intent & why, (b) Impact Tier (1-3), (c) Files to touch, (d) Invariants to preserve & what NOT to touch, (e) Verification commands.
   - Await user approval before modifying code (Planning Mode).

5. **Execute & Verification Gate:**
   - Fast Gate (post-write / Tier 1-2):
     `py -3 tools/verify_gate.py --fast || python tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast`
   - Full Battery (Tier 3 / pre-turn completion):
     `py -3 tools/verify_gate.py --full || python tools/verify_gate.py --full || py -3 tools/verify_gate.py --full`
