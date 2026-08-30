# AGENTS.md

Onboarding and agent protocol for Google Antigravity, Gemini models, and autonomous agents (DeepSeek, opencode, Copilot).

<core_invariants>
## 1. Core Architecture & Invariants

All engine constraints, simulation layers, and critical file contracts are canonically defined in:
👉 **[docs/CORE_INVARIANTS.md](docs/CORE_INVARIANTS.md)**
👉 **[docs/API_SURFACE.md](docs/API_SURFACE.md)**

Key Highlights:
- **Engine Lock:** Godot 4.7-stable · GDScript 2.0 ONLY · Strict Typing on every variable, parameter, and return type.
- **Simulation Stack:** 5-layer upward event propagation model (Physics → AI → Social → Club World → Narrative). Every major feature touches at least two layers.
- **Choke Points:** All spatial reads via `MatchWorldModel.gd`; all inter-system events via `GameEvents.gd`; `PlayerBrain` writes ONLY `movement_intent` and `wants_sprint`.
- **Reference Spec:** Consult `docs/course_implementation_specification.md` (READ-ONLY) before implementing course-related systems.
</core_invariants>

<verification>
## 2. Verification & Static Analysis

After every `.gd` file write, execute static analysis immediately:
```bash
python3 tools/gdcheck.py || python tools/gdcheck.py || py -3 tools/gdcheck.py
```
**Strict Requirement:** Do not proceed or conclude turns until the checker output shows `0 errors`.

### Database Integrity Verification
```bash
python3 tools/verify_db.py || python tools/verify_db.py || py -3 tools/verify_db.py
```

### Autoload Handling Contract
`gdcheck.py` reads `[autoload]` from `project.godot` and treats every autoload name as a known type. Never add `class_name` to an autoload script.

### Headless Engine Testing (when Godot 4.7 binary is available)
```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
```
</verification>

<tooling>
## 3. Developer Tooling & Slash Commands

| Command | Action | Description |
|---|---|---|
| `/verify-all` | `tools/gdcheck.py && tools/verify_db.py` | Complete GDScript & database verification |
| `/sync-rules` | `tools/sync_rules.py` | Promote discovered rules to `.claude/rules/` & `docs/CORE_INVARIANTS.md` |
| `/compact-errata` | `tools/compact_errata.py` | Promote rules and compact session state history to `docs/archive/` |
| `/rebuild-api` | `tools/dump_api.py` | Regenerate `docs/API_SURFACE.md` public API surface map |
| `/next-task` | `tools/next_task.py` | Query `ROADMAP.md` for next Phase 1 gameplay completeness item |
| `/layer-ctx` | `tools/layer_context.py [1-5]` | Extract targeted context for simulation layers 1–5 |
</tooling>

<gemini_context_protocol>
## 4. Gemini Context Protocol & Antigravity Autonomy

### Large Context Window & Context Caching
- **Cached Architecture Prefix:** `POWERFOOTBALL_MASTER_VISION.md`, `docs/CORE_INVARIANTS.md`, `docs/API_SURFACE.md`, `AGENTS.md`, and `llms.txt` reside in the context prefix.
- **Holistic Cross-Layer Awareness:** Gemini's 1M+ token context window enables reasoning across multiple simulation layers simultaneously without lossy compaction.
- **Self-Healing Iteration:** When `.antigravity/hooks.json` intercepts a verification failure, review the `gdcheck.py` error diagnostic, locate the file and line number, and resolve type/syntax/contract errors immediately.

### Atomic Feature Discipline
- **One Feature = One File Set + One Verification Pass:** Execute changes in modular, cohesive units.
- **Strict Verification Gate:** Always verify with `tools/gdcheck.py` prior to completing any turn.
- **Errata Synchronization:** Record novel failure modes, API misconceptions, and runtime discoveries into `AGENTS_ERRATA.md` using the structured machine-readable format. Promote to `.claude/rules/` and `docs/CORE_INVARIANTS.md` via `/sync-rules` or `/compact-errata`.
</gemini_context_protocol>
