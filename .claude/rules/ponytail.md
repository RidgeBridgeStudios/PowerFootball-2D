## Ponytail Decision Ladder (Reuse & Complexity Gating)

Before writing new code or adding new infrastructure, climb this ladder in order. Stop at the first rung that already solves the problem — do not go further down toward a new abstraction.

This complements the existing `/simplify` and `/code-review` skills (post-hoc cleanup); the ladder is the pre-hoc check that stops the extra code from being written in the first place.

1. **YAGNI Gating** — Reject speculative additions. A feature must trace to an active `[ ]` item in `ROADMAP.md` or an explicit user request. Do not build config, servers, or scaffolding for tools/runtimes not actually present in this repo (verify with `ls`/`find` before assuming a package or binary exists — do not take a prompt's claims about third-party MCP servers on faith).
2. **Codebase Reuse** — Route career state through `autoloads/CareerManager.gd`, match resolution through `shared/QuickSimEngine.gd`, and inter-system events through `autoloads/GameEvents.gd`. Never write a parallel event bus or a second match resolver. For cross-agent shared memory, use the existing `AGENTS_ERRATA.md` structured-YAML mechanism (Section 10 of `AGENTS.md`) instead of standing up a new database.
3. **Engine/Stdlib** — Use GDScript 2.0 built-ins (`distance_squared_to()`, `Vector2`, `Callable.call()`). Never capture `self` inside an anonymous lambda closure — assign it to a local (`var host: Node = self`) or use `Callable.bind()` first.
4. **Native Node Architecture** — Rely on the existing manager-mode scene tree (`ui/manager_mode/ManagerModeRoot.tscn` and its panels) and the live autoloads; do not resurrect a per-frame match scene. The 22-player declarative pitch layout and the collision matrix were archived with the real-time match layer.
5. **Existing Invariant Scripts** — Check `shared/UtilityMath.gd` and `docs/MATH_SOLVERS.md` before deriving a new formula; the closed-form solver you need may already be there.
6. **One-Line Density** — Prefer compact, explicitly-typed assignments over verbose boilerplate once the above rungs are exhausted.
7. **Minimal Viable Diff** — Bound every change to the targeted function via `python3 tools/codebase_slice.py || python tools/codebase_slice.py || py -3 tools/codebase_slice.py`. Full-file rewrites of existing `.gd` files are already blocked by the `PreToolUse` guard in `.agents/hooks.json` — use `Edit`, not `Write`, on existing scripts.

### Real navigation/verification stack — do not reinvent it

This repo already has working, project-local equivalents for the kind of tooling that's easy to imagine needing. Use these instead of adding new servers or packages:

| Need | Real tool already in this repo |
|---|---|
| Symbol-level code retrieval / blast radius | `tools/mcp_server.py` (`get_blast_radius`, `extract_code_slice`, `get_layer_invariants`, `inspect_scene_tree`, `query_spatial_cache`, `run_property_test`), registered as the `powerfootball` MCP server in `.agents/mcp.json` |
| Knowledge graph / architecture queries | The local `graphify` MCP server in `.agents/mcp.json` (backed by `graphify-out/graph.json`) — not the `@graphify/mcp` npm package, which does not exist |
| GDScript LSP diagnostics | `tools/lsp_client.py` (Godot LSP bridge on `127.0.0.1:6005`), falling back to `tools/gdcheck.py` / `tools/lint_xref.py` when the editor daemon isn't running |
| Cross-agent shared memory | `AGENTS_ERRATA.md` (structured YAML, promoted via `tools/sync_rules.py` / `tools/compact_errata.py`) |
| Static + simulation verification | `python3 tools/verify_gate.py --fast` / `--full` (fallback `python` / `py -3`) |

Before adding a new MCP server entry anywhere (`.agents/mcp.json`, `.claude/settings.json`, or a DeepSeek/other-harness config), confirm the underlying package is actually installed or installable — an unverified command in an MCP config just produces a server that fails to launch.
