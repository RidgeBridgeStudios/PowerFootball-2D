# AGENTS.md

Onboarding and architectural reference for Google Antigravity, Gemini models, and non-Claude autonomous agents (DeepSeek, opencode, Copilot). Self-contained mirror of CLAUDE.md and `.claude/rules/` optimized with semantic XML tags for Gemini attention weighting.

<engine_lock>
## 1. Engine Lock

**Godot 4.7-stable · GDScript 2.0 ONLY · Strictly Typed**

### Prohibited / Strictly Forbidden APIs
- NEVER `yield()`                          → use `await`
- NEVER `KinematicBody2D`                  → use `CharacterBody2D`
- NEVER `RigidBody`                        → use `RigidBody2D`
- NEVER `file.open()` or `File.new()`      → use `FileAccess.open()`
- NEVER `dir.open()` or `Directory.new()`  → use `DirAccess.open()`
- NEVER `OS.get_ticks_msec() / 1000`       → use `Time.get_ticks_msec()`
- NEVER `export(...)`                      → use `@export`
- NEVER `onready var`                      → use `@onready var`

### Strict Typing Invariant
Every variable declaration, function parameter, and function return type MUST be explicitly typed.
- CORRECT:   `var velocity: Vector2 = Vector2.ZERO`
- INCORRECT: `var velocity = Vector2.ZERO`
- CORRECT:   `func calculate_steer(target_pos: Vector2, max_speed: float) -> Vector2:`
- INCORRECT: `func calculate_steer(target_pos, max_speed):`
- CORRECT:   `for player: CharacterBody2D in team_players:`
- INCORRECT: `for player in team_players:`
</engine_lock>

<simulation_stack>
## 2. Simulation Stack

Five-layer upward event propagation model. Events bubble upward; each layer feeds the next.

```text
LAYER 5 — NARRATIVE      PressOffice, TouchlineBubble, WorldEvent log
                            ↑ quote generation from layers 3 & 4
LAYER 4 — CLUB WORLD     RelationshipGraph, OffPitchEventEngine, TrainingSystem
                            ↑ trust decay, dressing room events, injuries
LAYER 3 — MATCH SOCIAL   MoodSystem (SLUMP/STREAK), StarMarking, SubReactions
                            ↑ relationship-weighted passing, foul heat
LAYER 2 — MATCH AI       UtilityScorer, FormationAnchors, GK, RoleChaseBudgets
                            ↑ MatchWorldModel spatial cache, 15-frame jitter
LAYER 1 — PHYSICS        Pseudo3DBall, CharacterBody2D, CollisionLayers, SetPieces
```

**Cross-Layer Architectural Invariant:**
Every major feature touches at least two layers. Single-layer systems are ornamental.
</simulation_stack>

<critical_file_contracts>
## 3. Critical File Contracts (Choke Points)

| File | Contract | Must Never Do |
|------|----------|---------------|
| `autoloads/MatchWorldModel.gd` | ALL spatial position reads go here. Global cache of 22 players + ball. Owns `defensive_line_x` — shared per-team defensive-line depth (world X), recomputed every physics frame from ball position + carrier pressure. Defenders blend toward this instead of each computing an independent line. | Call `get_tree().get_nodes_in_group()` inside `_process`/`_physics_process`; compute a per-player defensive line independently instead of reading `defensive_line_x`. |
| `autoloads/GameEvents.gd` | ALL inter-system events propagate via signals on this bus. Single event hub for physics, AI, match events, and social systems. | Emit cross-system signals from individual components directly; bypass GameEvents. |
| `autoloads/GameManager.gd` | Match phase, score, clock, set pieces. Single source of truth for match lifecycle. | Query multiple disparate files for match state; maintain duplicate score or clock state. |
| `entities/player/HeavyPlayerController.gd` | Physics execution body for CharacterBody2D. Owns `velocity`, acceleration curves, top speed clamping, collision resolution, and the resolved `is_sprinting` state. Reads `movement_intent` and `wants_sprint` from `PlayerBrain`. | Contain tactical decision-making or utility scoring logic; mask Layer 3 (Ball collision layer). |
| `entities/player/PlayerBrain.gd` | Utility-scored AI decision engine. Runs on 15-frame jitter per `player_index`. Writes ONLY `player.movement_intent` (Vector2 direction) and `player.wants_sprint` (bool/desired speed scale) — never `velocity`, `acceleration`, or `is_sprinting`. | Allocate or scan scene trees inside `_physics_process`; write to `velocity`, `acceleration`, or `is_sprinting` directly. |
| `shared/PlayerData.gd` | Player attributes, traits, relationships. Persists across matches. | Mutate attributes directly from outside call sites; use class methods only. |
| `shared/PlayerRoleConfig.gd` | Data-driven role tuning resource (`.tres` presets in `shared/roles/`). `anchor_weight` (0–1): 1.0 = hold formation anchor rigidly, 0.0 = roam freely — the INVERSE of PlayerBrain's internal roam alpha (`ROLE_SPACE_ALPHA` convention), so consumers must convert via `1.0 - anchor_weight` when blending toward open space. `role_config` is null on all entities until a `.tres` is assigned — always guard reads with `if player.role_config != null`. Separate from `DEFENSIVE_LINE_DEPTH_WEIGHT` (X-axis line-depth blend). | Feed `anchor_weight` straight into a roam-weighted alpha (conventions are inverted); treat `ROLE_SPACE_ALPHA` as a float — it is a Dictionary const in `PlayerBrain.gd`; confuse `anchor_weight` with `DEFENSIVE_LINE_DEPTH_WEIGHT`. |
| `shared/CollisionLayers.gd` | Layer bitmask constants. Layer 1 = World/Pitch bounds, Layer 2 = Players, Layer 3 = Ball. CharacterBody2D masks Layer 1+2 ONLY. | Mask Layer 3 in CharacterBody2D (ball manages its own pseudo-3D height and collision). |
| `docs/course_implementation_specification.md` | READ-ONLY reference specification. Course-derived build phases 1–10, FSM patterns, physics formulas, data models, known gotchas, and agent protocol. Consult before starting any new phase or implementing any system described in Sections 7–13. | Modify this file. It is a reference artifact only. |
</critical_file_contracts>

<verification>
## 4. Verification & Static Analysis

After every `.gd` file write, execute static analysis immediately:
```bash
python3 tools/gdcheck.py || python tools/gdcheck.py || py -3 tools/gdcheck.py
```
**Strict Requirement:** Do not proceed or conclude turns until the checker output shows `0 errors`.

### Autoload Handling Contract
`gdcheck.py` reads `[autoload]` from `project.godot` and treats every autoload name (e.g. `MatchWorldModel`) as a known type even when its script has no `class_name` — that's deliberate, since Godot 4.7+ rejects a `class_name` that collides with an autoload's injected global name. If `gdcheck.py` ever reports `unknown type` for an autoload, fix `gdcheck.py`'s autoload parsing — never "fix" it by adding `class_name` to the autoload script itself.

### Headless Engine Testing (when Godot 4.7 binary is available)
```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
```
</verification>

<gemini_context_protocol>
## 5. Gemini Context Protocol & Antigravity Autonomy

### Large Context Window & Context Caching
- **Cached Architecture Prefix:** `POWERFOOTBALL_MASTER_VISION.md`, `AGENTS.md`, and core schemas reside in the pinned/cached context prefix.
- **Holistic Cross-Layer Awareness:** Gemini's 1M+ token context window enables reading and reasoning across multiple simulation layers (Physics + Match AI + Social + Club World) simultaneously without lossy compaction.
- **Self-Healing Iteration:** When `.antigravity/hooks.json` intercepts a verification failure, review the full `gdcheck.py` error diagnostic, locate the file and line number, and resolve type/syntax/contract errors immediately.

### Atomic Feature Discipline
- **One Feature = One File Set + One Verification Pass:** Despite large context capacity, execute changes in modular, cohesive units.
- **Strict Verification Gate:** Always verify with `tools/gdcheck.py` prior to completing any turn.
- **Errata Synchronization:** Record novel failure modes, API misconceptions, and runtime discoveries into `AGENTS_ERRATA.md` using the structured machine-readable format.
</gemini_context_protocol>
