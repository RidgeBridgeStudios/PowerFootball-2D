---
name: bug-investigation
description: Systematic bug investigation workflow isolating root causes, enforcing layer invariants, checking blast radius, and running verification gates.
---

# Workflow: bug-investigation

Systematic triage and resolution protocol for defects across the 5-layer simulation stack.

## Execution Protocol

1. **Symptom Triage & Invariant Classification:**
   - Map symptom to simulation layer (1: Physics, 2: AI, 3: Social, 4: Club World, 5: UI).
   - Check layer rules via `py -3 tools/layer_context.py [1-5]` or `py -3 tools/semantic_search.py "<symptom>"`.
   - Distinguish defects from pending roadmap items via `py -3 tools/next_task.py`.
   - If no invariant covers the symptom, flag as a documentation/specification gap.

2. **Targeted Errata Reconnaissance (Zero Full Dumps):**
   - Query topic-scoped errata in `docs/agent-errata/<topic>.md` (e.g. `player-ai.md`, `physics-and-ball.md`).
   - Search historical failure modes with `py -3 tools/semantic_search.py "<subsystem> <symptom>"`.
   - Never dump full `AGENTS_ERRATA.md` or `docs/CORE_INVARIANTS.md`.

3. **Structural Root-Cause Tracing:**
   - Query Graphify (`query_graph` or `graphify query/path`) for topological dependency flow.
   - Trace callers and blast radius: `py -3 tools/dump_dep_graph.py --blast-radius <target>`.
   - Rank candidate causes by causal likelihood across the 5 simulation layers.

4. **Targeted Code Inspection:**
   - Never read whole files. Extract specific functions, enums, or headers via:
     `py -3 tools/codebase_slice.py <file> --func <name>` (or `--class-header`, `--signals`).
   - For focused line ranges, inspect targeted line slices only.

5. **Diagnosis & Minimal Fix Plan (Approval Gate):**
   - Present diagnosis: offending file, function, exact causal chain, and violated invariant.
   - Formulate minimal surgical fix and evaluate blast radius (what the fix could break).
   - Await user approval before modifying code (Planning Mode).

6. **Execution & Regression Verification:**
   - Apply minimal fix adhering to strict typing, zero hot-path allocations, and choke points.
   - Run relevant domain check (`eval-sim`, `fuzz_solvers.py`, `fuzz_formations.py`, `replay_test.py`).
   - If non-obvious lesson learned, record structured errata in `AGENTS_ERRATA.md` and run `py -3 tools/sync_rules.py`.

7. **Verification Gate:**
   - Post-write / Fast Gate (10 static linters):
     `py -3 tools/verify_gate.py --fast || python tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast`
   - Pre-turn / Full Battery (linters + fuzzers + simulation):
     `py -3 tools/verify_gate.py --full || python tools/verify_gate.py --full || py -3 tools/verify_gate.py --full`
