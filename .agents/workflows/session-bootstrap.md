---
name: session-bootstrap
description: Lightweight session initialization workflow that establishes task-adaptive routing, enforces token-hygiene invariants, and asserts repository readiness.
---

# Workflow: session-bootstrap

Initializes agent context at session start. Resolves policy precedence, sets up semantic routing, and validates repo health without token dumping.

## Execution Protocol

1. **Verify Baseline Readiness:**
   Assert repository health with zero diagnostics before taking action:
   `python3 tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast`

2. **Policy Precedence Resolution:**
   Resolve any rule conflict in strict descending order:
   `docs/CORE_INVARIANTS.md` & `AGENTS.md` > `.agents/rules/*.md` > `docs/agent-errata/*.md` > `llms.txt` / Module `README.md` > Defaults.

3. **Context Hygiene & File-Read Restrictions:**
   - **Forbidden full reads:** `AGENTS_ERRATA.md`, `docs/SYMBOLS.json`, `docs/API_SURFACE.md`, `docs/DEPENDENCY_GRAPH.json`, `data/*.json`, `docs/research/*`.
   - **Targeted Tool Replacements:**
     - Query symbol signatures: `python3 tools/codebase_slice.py --symbol <name>`
     - Compute blast radius DAG: `python3 tools/dump_dep_graph.py --blast-radius <target>`
     - Search rules & docstrings: `python3 tools/semantic_search.py "<query>"`
     - Fetch layer architecture: `python3 tools/layer_context.py [1-5]`
     - Fetch next roadmap task: `python3 tools/next_task.py`

4. **Task-Adaptive Semantic Routing:**
   Map the assigned task to minimal context, skill, and verification tier:
   - **Layer 1 (Physics/Kinematics):** `tools/layer_context.py 1` -> `perf-benchmark` -> Fast Gate + `fuzz_solvers.py`
   - **Layer 2 (Match AI/Formations):** `tools/layer_context.py 2` -> `formation-fuzzer` / `formation-audit` -> Fast Gate + `fuzz_formations.py`
   - **Layer 3 (Social/Trust/Ratings):** `tools/layer_context.py 3` -> `eval-sim` -> Fast Gate + `eval_simulation.py`
   - **Layer 4 (Club World/Database):** `tools/layer_context.py 4` -> `verify-db` -> Fast Gate + `verify_db.py`
   - **Layer 5 (Narrative/Presentation):** `tools/layer_context.py 5` -> UI inspect -> Fast Gate (`verify_gate.py --fast`)
   - **Cross-Layer / Multi-System:** Blast radius check -> `cross-system-feature` -> Full Gate (`verify_gate.py --full`)
   - **AST & Typing Refactoring:** `tools/codebase_slice.py` -> `ast-refactor` -> Fast Gate (`verify_gate.py --fast`)

5. **Startup Report & Standby:**
   Report the active routing table in <= 15 lines. Do not read source files or apply edits until the user provides or confirms the specific task.

6. **Post-Task Verification Gate:**
   - Local leaf edits (Tier 1/2): `python3 tools/verify_gate.py --fast || py -3 tools/verify_gate.py --fast`
   - Core / Cross-module edits (Tier 3): `python3 tools/verify_gate.py --full || py -3 tools/verify_gate.py --full`
