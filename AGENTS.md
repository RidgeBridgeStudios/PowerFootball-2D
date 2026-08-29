# AGENTS.md — Multi-Agent Repository Guide

**For: DeepSeek, opencode-go, Copilot, and other non-Claude models working on PowerFootball-2D**

This document is a flattened, self-contained mirror of `CLAUDE.md`, `.claude/rules/`, and architectural contracts. An agent that receives only this file needs everything to work safely. No `@./` imports. No auto-loaded rules. Every invariant is inline.

---

## 1. Project Identity

**PowerFootball-2D is Dwarf Fortress with a football.** Simple overhead-dot visuals mask a deep social simulation. The game itself is the world underneath, not the viewport.

This project makes the same foundational trade as Dwarf Fortress: ASCII graphics (here, overhead dots) buy simulation depth—squad chemistry, star psychology, manager-player conflict, off-pitch events, match-to-match memory, and emergent narrative. The result is not just watchable football; it is playable football with hidden complexity.

PowerFootball-2D runs on **five simulation layers** that connect events upward into narrative:

```
LAYER 5 — NARRATIVE          PressOffice, TouchlineBubble, WorldEvent log
                                     ↑ quote generation from layers 3 & 4
LAYER 4 — CLUB WORLD         RelationshipGraph, OffPitchEventEngine, TrainingSystem
                                     ↑ trust decay, dressing room events, injuries
LAYER 3 — MATCH SOCIAL       MoodSystem (SLUMP/STREAK), StarMarking, SubReactions
                                     ↑ relationship-weighted passing, foul heat
LAYER 2 — MATCH AI           UtilityScorer, FormationAnchors, GK, RoleChaseBudgets
                                     ↑ MatchWorldModel spatial cache, 15-frame jitter
LAYER 1 — PHYSICS            Pseudo3DBall, CharacterBody2D, CollisionLayers, SetPieces
```

A typical event chain: bad tackle (physics) → emotional fallout (match-social) → trust drop (club-world) → dressing-room incident (narrative). Every major feature must touch at least two layers to be foundational.

---

## 2. Engine Lock

**Non-negotiable constraints. No exceptions.**

- **Godot 4.7-stable ONLY.** No 4.6, no 4.8. Engine API changes break everything.
- **GDScript 2.0 ONLY.** Strict typing mandatory on every variable, parameter, and return type.
- **await is correct.** `yield()` is Godot 3. PROHIBITED.
- **CharacterBody2D ONLY for players.** `KinematicBody2D` is Godot 3. PROHIBITED.
- **RigidBody2D not used for player movement.** Physics bodies for players: CharacterBody2D only.
- **FileAccess, not file.open().** File I/O must use the Godot 4.7 API.
- **DirAccess, not dir.open().** Directory I/O must use the Godot 4.7 API.
- **@onready and @export everywhere.** Scene references and exports must be declared at the class level.
- **Node.owner must be set before save.** Any node created in GDScript must have `.owner = scene_root` or it silently vanishes on reload.
- **Autoload boot order is law.** Never reorder autoloads in `project.godot` without verifying the entire dependency chain.

**Boot order (non-negotiable):**
```
MatchWorldModel → GameEvents → GameManager → DataLoader → RefereeLoader → ManagerLoader → InputHelper
```

---

## 3. Architectural Laws

These rules are invariant. Every system must obey them.

1. **ALL spatial reads route through MatchWorldModel.**
   - Get player positions: `MatchWorldModel.instance.player_positions[i]`
   - Get ball position: `MatchWorldModel.instance.ball_node`
   - Direct `get_tree().get_nodes_in_group()` for spatial data inside `_process()` or `_physics_process()`: **PROHIBITED.**
   - Exception: `get_nodes_in_group()` for state-machine detection (does the ball exist? is it frozen?) is allowed once per rare event, not every frame.

2. **ALL inter-system events route through GameEvents signal bus.**
   - Direct node references across system boundaries: **PROHIBITED.**
   - All match state, formation changes, fouls, goals, and tactical shifts: emit via `GameEvents`.
   - Signal payloads must be documented (see compounded corrections in Section 9).

3. **NPC utility AI uses 15-frame stagger, never full-frame evaluation.**
   - Each NPC evaluates decisions only when `(player_id + frame_number) % 15 == 0`.
   - `_steer_for_action()` runs every frame; the decision block is gated.
   - This spreads CPU load evenly across the frame budget.

4. **Zero heap allocations in `_physics_process()` and `_process()`.**
   - `Vector2()`, `Array()`, `Dictionary()`, `RandomNumberGenerator.new()` inside physics/process loops: **PROHIBITED.**
   - Pre-allocate class-level buffers and reuse them.
   - Goal: zero garbage-collection stalls.

5. **Strict typing on every var, param, and return.**
   - `var x = something` without a type: **PROHIBITED.**
   - `func y(z)` without param types: **PROHIBITED.**
   - `func w()` without return type annotation: **PROHIBITED.**
   - CORRECT: `var velocity: Vector2 = Vector2.ZERO`
   - CORRECT: `func apply_force(force: Vector2) -> void:`

6. **Collision layers are immutable constants from `shared/CollisionLayers.gd`.**
   - Magic integers in physics code: **PROHIBITED.**
   - Always reference `CollisionLayers.LAYER_PLAYER`, `CollisionLayers.LAYER_BALL`, etc.

7. **CharacterBody2D players MUST NOT mask Layer 3 (Ball).**
   - Layer 3 is ball-exclusive. Masking it in a player controller causes the physics solver to zero all player velocity.
   - Collision: CharacterBody2D masks Layer 1 (players) + Layer 2 (terrain) ONLY.
   - Ball interaction: Area2D on Layer 4 sensing Layer 3.

8. **PlayerBrain writes ONLY to `player.movement_intent`.**
   - The brain computes tactical decisions. `HeavyPlayerController` consumes those decisions and moves the player.
   - Cross-contamination (brain directly tweaking position or velocity): **PROHIBITED.**

9. **Formation anchors are written per-brain, not emitted as positions.**
   - `ManagerDirector._apply_formation()` writes anchor positions directly to each `PlayerBrain`.
   - Listeners asking "where should player i go?" read `player_brain.formation_anchor`, not a signal payload.
   - Signal `GameEvents.formation_anchors_changed(team, anchors_dict)` exists for systems that need the full picture.

10. **"Deprecated export ≠ unused export" — grep before deleting.**
    - An `@export` may be superseded for *scheduling* but still written by other systems.
    - Example: `PlayerBrain.decision_interval` is superseded by the 15-frame stagger, but `ManagerDirector` still writes it.
    - Always verify no other code path writes the export before removing it.

11. **Static counters for declarative player spawn must be reset on roster teardown.**
    - All 22 players are declarative children of `$Players` in `pitch/PitchScene.tscn`, not spawned in a loop.
    - Each player's `HeavyPlayerController._ready()` uses a static counter to self-assign its index.
    - When the roster tears down (`MatchWorldModel.unregister_all()`), the counter MUST reset, or the next match claims invalid slots.

12. **Child `_ready()` runs BEFORE parent `_ready()`.**
    - `PlayerBrain` is a child of `HeavyPlayerController`.
    - `PlayerBrain._ready()` cannot read anything the parent assigns in its `_ready()` — those values are still zero.
    - Connect signals in the child's `_ready()`; read parent-assigned state later (in a callback or decision tick).
    - `await` cannot paper over this.

13. **Practice Arena frees 20 of 22 players — all node reads must be guarded.**
    - `PitchScene._setup_practice_arena()` calls `queue_free()` on all players except one human and one keeper.
    - Any cached node array holds freed references. `EVERY` read of `player_nodes[i]` must call `is_instance_valid()`.
    - A null check alone does NOT catch a freed node.

14. **Shared scratch buffers must have exactly one live call site.**
    - `PlayerBrain._find_nearby_opponents()` refills a member `Array[Node2D]` to avoid allocation.
    - This is only safe because one call site exists.
    - Before adding a second call site, verify no caller is still iterating the buffer when the other refills it.
    - `_find_best_pass_target()` and `_find_channel_run_target()` were deliberately rewritten onto `MatchWorldModel.nearest_opponent_dist_to()` instead of given a second call to it.

15. **Group scans that must NOT route through MatchWorldModel:**
    - `ShotLockState`, `ThrowInState`, `ChargeKickState`: `get_nodes_in_group(&"ball")` to search for ANY ball and filter by state.
    - `TackleState._find_nearby_opponent()`: `get_nodes_in_group(&"players")` — fires once per mistimed challenge, not per frame.
    - These are not on the hot path and were deliberately left as scene-tree lookups.

16. **Ball ownership has TWO properties with different meanings.**
    - `possessor: Node2D` — who is actively carrying the ball right now. Null while loose or in flight. Set by `set_possessor()` from DribbleState/TackleState; cleared by `release_possession()`.
    - `last_touched_by: HeavyPlayerController` — who struck it last. Survives the ball going loose. Used by `PitchBoundary` to distinguish goal kick from corner.
    - "Who has the ball" resolves `possessor` first; only falls back to `last_touched_by` if null.

17. **Ball friction is a PRODUCT, not a coefficient.**
    - `Pseudo3DBall.pitch_friction` (default 0.45) is a coefficient, NOT px/s².
    - Every use multiplies it by `const FRICTION_SCALE: float = 200.0`.
    - Intercept predictor must pass the product: `pitch_friction * Pseudo3DBall.FRICTION_SCALE` (default 90.0 px/s²).
    - Passing `pitch_friction` alone under-decelerates the ball by 200x, and every intercept lands far beyond where the ball stops.

18. **Pseudo3DBall.predict_trajectory() returns render points, not ground points.**
    - Each point is `sim_pos_xy + Vector2(0.0, -sim_pos_z)` — height is baked into Y for drawing.
    - This is correct for aim arcs; wrong for ground intercepts on airborne balls.
    - Use `UtilityMath.calculate_intercept_point()` for true ground positions on airborne targets.

19. **Formation names are STRINGS, not anchor structures.**
    - `ManagerDirector._shift_to()` emits `GameEvents.manager_formation_changed.emit(_team, formation_name)`.
    - Payload is `(team: int, new_formation: String)` — a NAME, no position data.
    - Anchors are written straight onto each brain by `_apply_formation()`.

20. **Three signals exist with "formation" in the name — check the emitter.**
    - `GameEvents.formation_changed(team, name)` — emitted by `PauseMenu` and `PreGameScreen` (UI).
    - `GameEvents.manager_formation_changed(team, name)` — emitted by `ManagerDirector` (match-time).
    - `GameEvents.formation_anchors_changed(team, anchors_dict)` — emitted by `ManagerDirector` (full anchor data).
    - Before connecting, verify you have the right signal for your use case.

21. **ManagerLoader is a database, not a runtime actor.**
    - `autoloads/ManagerLoader.gd` parses JSON and saves managers. It has NO match-time signals.
    - Match-time formation logic lives in `entities/manager/ManagerDirector.gd`.
    - Do not go looking for formation change signals in ManagerLoader.

22. **TOTAL_PLAYERS is 22, always.**
    - 10 outfield + 1 goalkeeper per team = 11 per team × 2 teams = 22 total.
    - Any other value is a bug.

---

## 4. Key File Map

Each entry: **path → contract**

### Autoloads (Boot Order Critical)

- **autoloads/MatchWorldModel.gd** — Spatial position cache. All NPC position reads route here. Maintains `player_positions[i]`, `ball_node`, and stagger jitter.
- **autoloads/GameEvents.gd** — Signal bus. All inter-system events emit here. No direct node references across systems.
- **autoloads/GameManager.gd** — Match phase, score, clock, set-piece flow control.
- **autoloads/DataLoader.gd** — JSON parsing and instantiation of players, teams, managers.
- **autoloads/RefereeLoader.gd** — Referee personality data and foul-decision logic.
- **autoloads/ManagerLoader.gd** — Manager data loading (database only; no match-time behavior).
- **autoloads/InputHelper.gd** — Player input handling; touch/keyboard mapping.

### Player & Brain

- **entities/player/HeavyPlayerController.gd** — Kinematic weight model, stamina, velocity clamping, input consumption. Executes the decision from `PlayerBrain.movement_intent`. Process priority: 100 (runs last).
- **entities/player/PlayerBrain.gd** — Utility-scored AI decision engine. Evaluates Pass/Chase/Space/Dribble/Formation every 15 frames via stagger. Writes ONLY to `movement_intent`. Process priority: 0 (default).

### Ball Physics

- **entities/ball/Pseudo3DBall.gd** — Pseudo-3D physics: z-axis trajectory, shadow rendering, friction model. Critical formulas: `z(t+Δt) = z(t) + vz(t)*Δt - 0.5*g*(Δt)²`. Shadow scale: `clamp(1.0 - z/300.0, 0.35, 1.0)`.

### Manager & Tactics

- **entities/manager/ManagerDirector.gd** — Match-time formation shifting, formation anchor application, tactical AI. Emits `manager_formation_changed` and `formation_anchors_changed`.
- **entities/manager/FormationLibrary.gd** — Stores formation templates keyed by name. Returns anchor positions.

### Referee & Rules

- **entities/referee/MatchReferee.gd** — Match rules enforcement, personality-weighted foul decisions, card tracking, stat persistence.

### Data Models

- **shared/PlayerData.gd** — Player attributes, movement speed, decision weights. Planned: trait bitmask, relationships.
- **shared/ManagerData.gd** — Manager personality traits (bitmask), preferred formations, press aggression.
- **shared/TeamData.gd** — Team roster, lineup order, league affiliation.
- **shared/LeagueData.gd** — League metadata (name, teams, season).

### Utilities

- **shared/UtilityMath.gd** — Intercept solver, lane occlusion tests, sigmoid, lerp helpers. Critical for prediction and chase targeting.
- **shared/CollisionLayers.gd** — Layer constants. Read before any physics work. Never use magic integers.

### Pitch & Field

- **pitch/PitchScene.tscn** — Main field scene. Contains `$Players` (22 declarative player children), `$Ball`, boundaries, markings.
- **pitch/PitchBoundary.gd** — Handles ball out-of-bounds: throw-ins, goal kicks, corners, goals.
- **pitch/PitchMarkings.gd** — Visual field markings and anchor display for debugging.

### UI & HUD

- **ui/HUD.gd** — Real-time match HUD: nameplates, minimap, action text, possession indicator.
- **ui/MainMenu.tscn** — Main menu: Kick Off, Practice, locked career modes, Options.
- **ui/PreGameScreen.tscn** — Team selection and lineup order before match start.
- **ui/PauseMenu.tscn** — In-match pause menu.
- **ui/TouchlineBubble.gd** — Manager reaction dialogue (tactical decisions, goals, fouls).

### Static Checker

- **tools/gdcheck.py** — Static GDScript linter. Catches undeclared members, unknown types, unbalanced brackets, Godot 3 APIs, bad autoloads. **Run after every file write.**

### Documentation & Schema

- **docs/json-schema.md** — Complete schema for player, manager, team, league JSON import.
- **POWERFOOTBALL_MASTER_VISION.md** — Canonical vision, five-layer stack, recommended build order, agent protocol.
- **ROADMAP.md** — Feature checklist with `[ ]`/`[x]` state for five build phases.

---

## 5. Current Build State

### IMPLEMENTED (24 Major Changes)

| # | What Was Built | Status |
|---|---|---|
| 1 | HeavyPlayerController, pseudo-3D ball, FSMs, GameEvents, GameManager, HUD, test pitch | ✓ |
| 2 | Kickoff, goal kick, corner, throw-in, free kick, penalty, SetPieceCoordinator, PitchBoundary | ✓ |
| 3 | PlayerData, TeamData, LeagueData, DataLoader, PlayerFactory, FC Nordvik, CD Solano | ✓ |
| 4 | MoodSystem (SLUMP/NORMAL/STREAK) affecting AI and kick scatter | ✓ |
| 5 | RefereeData, RefereeLoader, MatchReferee, personality-weighted foul decisions | ✓ |
| 6 | ManagerData, ManagerLoader, FormationLibrary, ManagerDirector, PressOffice | ✓ |
| 7 | MainMenu.tscn with Kick Off, Practice, locked career modes, Options, Quit | ✓ |
| 8 | Full 22-player pitch, PitchMarkings, goalkeeper AI, goal-line anchoring | ✓ |
| 9 | Role enum, _should_chase_ball() gates, ManagerDirector tempo fix | ✓ |
| 10 | TouchlineBubble manager reactions for key match events | ✓ |
| 11 | Role-specific possession-aware targets, auto-switch to nearest teammate | ✓ |
| 12 | Practice Arena mode with reset, free kick, penalty, GK freeze toggles | ✓ |
| 13 | CPU passing, pursuit steering, GK intercepts, defensive wall, half-time swap | ✓ |
| 14 | TOUCH_SPEED_RATIO tuning, FacingArrow.gd | ✓ |
| 15 | Nameplate panel, minimap with team-coloured shirt-number dots | ✓ |
| 16 | UtilityContext, Pass/Chase/Space/Dribble/Formation scorers | ✓ |
| 17 | MatchCamera.gd (BALL_FOLLOW, DYNAMIC, FULL_FIELD modes) | ✓ |
| 18 | Floating PASS/SHOT/LOB SHOT/THROW action labels | ✓ |
| 19 | get_facing_dot() and facing-weighted tackling plus AI penalties | ✓ |
| 20 | PreGameScreen, PauseMenu, lineup order from TeamData.lineup_indices | ✓ |
| 21 | Continuous possession magnetism, grace window in DribbleState | ✓ |
| 22 | Travel-direction carry target, stronger magnetism, ShotLockState | ✓ |
| 23 | _released throw-in guard, set-piece foot-sensor protection | ✓ |
| 24 | MatchWorldModel, UtilityMath.gd, 15-frame AI stagger, Claude agent scaffold | ✓ |

### ABSENT / STUB (Priority Order)

| Phase | Item | Status |
|---|---|---|
| 1 | Substitutions + reserves UI | ☐ |
| 1 | Yellow/red card implementation | ☐ |
| 1 | Offside detection | ☐ |
| 1 | Injury system | ☐ |
| 1 | Match stats screen + full-time scoreboard | ☐ |
| 1 | End-of-match player ratings | ☐ |
| 1 | Goalkeeper dive commitment | ☐ |
| 1 | AerialState / heading resolution | ☐ |
| 1 | Penalty shootout flow | ☐ |
| 1 | Through-ball lead targeting | ☐ |
| 2 | Player trait bitmask on PlayerData | ☐ |
| 2 | Trait effects wired into existing systems | ☐ |
| 2 | overall_rating and reputation derived fields | ☐ |
| 2 | Star-marking utility scorer | ☐ |
| 2 | Relationship trust graph | ☐ |
| 2 | Trust multiplier on pass utility | ☐ |
| 2 | Trust decay/gain events | ☐ |
| 3 | WorldEvent struct and WorldEventLog autoload | ☐ |
| 3 | Substitution reaction events | ☐ |
| 3 | Training incidents and dressing-room confrontations | ☐ |
| 3 | Street football / nightlife / media events | ☐ |
| 3 | PressOffice consumption of WorldEvent log | ☐ |
| 3 | Manager response system | ☐ |
| 4 | Career calendar and scheduling | ☐ |
| 4 | League table persistence | ☐ |
| 4 | Transfer window system | ☐ |
| 4 | Season progression and contracts | ☐ |
| 4 | Staff system | ☐ |
| 4 | Manager Career mode unlock | ☐ |
| 5 | Audio system | ☐ |
| 5 | Sprite and action animation | ☐ |
| 5 | HUD theme and custom fonts | ☐ |
| 5 | Local 2-player support | ☐ |
| 5 | Real squad JSON database | ☐ |

---

## 6. Agent Reading Order

**MANDATORY.** Do not begin implementation until you have completed this sequence.

1. **Read this file (AGENTS.md) in full.** All 11 sections. No shortcuts.
2. **Read POWERFOOTBALL_MASTER_VISION.md.** Vision, five-layer stack, build order, and this session's AI protocol.
3. **Read ROADMAP.md.** Identify which Phase 1 items are unchecked. Know the current priority.
4. **Run the verifier.** `python3 tools/gdcheck.py` — confirm zero errors.
5. **Identify your target system** (e.g., player controller, AI utility scoring, manager tactics, ball physics).
6. **Read the target file and its neighbors.** Understand the existing architecture and call chain.
7. **Skim llms.txt.** Understand the directory structure and which files are choke points.
8. **Read shared/CollisionLayers.gd if touching physics.** Never use magic integers.
9. **Read shared/UtilityMath.gd if touching prediction or interception.** Understand the math contracts.
10. **Check for README.md in the target directory.** If it exists, read it for per-directory contracts.
11. **Start implementation.** You are now permitted to write code.

---

## 7. Pre-Flight Checklist

Before submitting a large prompt or beginning work, confirm:

- [ ] **Autonomy is explicit.** Your task grant includes "FULL AUTONOMY" or equivalent language.
- [ ] **Engine is locked to Godot 4.7, GDScript 2.0.** Prompt names the versions.
- [ ] **yield / KinematicBody2D / RigidBody explicitly forbidden.** Prompt states deprecated APIs are prohibited.
- [ ] **Spatial rules are named.** "All position reads → MatchWorldModel."
- [ ] **Allocation constraints are clear.** "Zero heap allocations in _physics_process()."
- [ ] **Scene-tree polling is banned.** "get_nodes_in_group() for spatial data: PROHIBITED."
- [ ] **Stagger logic is explicit.** "NPC evaluation every 15 frames via (player_id + frame_number) % 15."
- [ ] **Bot count is named.** "TOTAL_PLAYERS = 22."
- [ ] **Verification ends with gdcheck.** Prompt says: "python3 tools/gdcheck.py after every file write. Do not stop until gdcheck reports zero errors."
- [ ] **Fan-out is capped.** Prompt does not spawn more than 3 concurrent subagents.
- [ ] **Context window strategy is stated.** Prompt explains when to /compact, /clear, or restart.

---

## 8. Verification Command

**After every file write, run:**

```bash
python3 tools/gdcheck.py
```

**Do NOT stop until gdcheck reports zero errors.**

This is non-negotiable. The static checker catches:
- Undeclared members and methods
- Type errors and unknown types
- Unbalanced brackets and syntax errors
- Godot 3 deprecated APIs
- Bad autoload entries in project.godot

A session that skips verification is a session that ships broken code.

---

## 9. Error Compounding Protocol

Every novel failure mode discovered during a session must be recorded before the session ends. This is how the repo compounds agent intelligence over time.

### For Claude Code Sessions

If you discover a new architectural mistake or constraint violation:

1. **Categorize it:**
   - Engine syntax, deprecated API, or scene-init contract → `.claude/rules/godot-47-core.md`
   - Physics formula, collision, or kinematic rule → `.claude/rules/soccer-physics.md`
   - AI scheduling, spatial caching, or allocation constraint → `.claude/rules/ai-architect.md`
   - Novel domain (career mode, relationship graph, off-pitch events) → create a new scoped rule file

2. **Add the rule to the appropriate file** before the session ends.
3. **Update the corresponding section of this document (AGENTS.md)** so non-Claude agents get the same knowledge.

### For Non-Claude Sessions (DeepSeek, opencode-go, etc.)

If you discover a new architectural mistake or constraint violation:

1. **You cannot write to .claude/rules/ directly.** That directory is Claude Code specific.
2. **Create or append to `AGENTS_ERRATA.md`** at the repo root instead. Use this format:

```markdown
## Session: [Your Model / Tool] — [Date]

### New Finding: [Constraint Name]
**Category:** (godot-47-core | soccer-physics | ai-architect | [domain])
**Description:** [What went wrong and why]
**Proposed Rule:** [Exact text to add to the rule file]
**Verified Against:** [Files or tests that confirm this]
```

3. **At the start of the next Claude Code session,** a human agent will reconcile `AGENTS_ERRATA.md` into the three `.claude/rules/` files and this document.

---

## 10. Context Hygiene

Large sessions decay when context saturates. CPU and memory constraints apply here as they do in real systems.

### Context Fill Thresholds

```
0%  ───────────── 50%   OPTIMAL
     Good reasoning, low noise. Architecture and math work belong here.

50% ───────────── 70%   MONITOR
     Acceptable. Watch for deprecated API risk and stale assumptions.

70% ───────────── 85%   DANGER
     Compaction or clear is mandatory. Major subsystem changes risk errors.

85% ──────────── 100%   CRITICAL
     Session is truncating writes. Restart immediately.
```

### Suggested Actions

- **At 50–70%:** Spot-check recent outputs; re-read invariant files if drifting.
- **At 70–85%:** Run `/compact` (Claude Code) to compress prior context.
- **At 85%+:** Run `/clear` (Claude Code) to reset conversation; re-read AGENTS.md and target file from disk.

### Context Survival

AGENTS.md and any inline-pasted rule content survive both `/compact` and `/clear` because they are re-read from disk, not stored in conversation history.

### For Non-Claude Sessions (No /compact or /clear)

- When context exceeds 60% (rough estimate), start a fresh session.
- Re-read AGENTS.md and your target file from scratch.
- Preserve any uncommitted work by committing it first.

---

## 11. Sync Protocol (READ EVERY SESSION)

**This section defines how AGENTS.md and CLAUDE.md stay coherent. Non-Claude agents must follow it.**

### The Covenant

1. **AGENTS.md is the flattened mirror of CLAUDE.md + all three `.claude/rules/` files.**
   - Every architectural law in CLAUDE.md appears inline in AGENTS.md Section 3.
   - Every prohibition in `.claude/rules/` appears inline in AGENTS.md Section 3 or Section 9.
   - AGENTS.md contains zero `@./` imports or references to files the reader must fetch.

2. **CLAUDE.md is authoritative. AGENTS.md is derived.**
   - When they conflict, CLAUDE.md wins.
   - Non-Claude agents use AGENTS.md because they cannot auto-load `.claude/rules/`.
   - Claude Code agents should prefer CLAUDE.md and the individual rule files for latest truth.

3. **Any agent (Claude or non-Claude) that adds a new architectural law to CLAUDE.md MUST update AGENTS.md Section 3 in the same session.**
   - Do not leave the sync broken for the next agent.
   - If you discover a new rule, add it to CLAUDE.md, then add it to AGENTS.md Section 3.

4. **Any agent that creates a new `.claude/rules/*.md` file MUST update AGENTS.md Sections 3 and 9.**
   - Add the key prohibitions to Section 3 (Architectural Laws).
   - Reference the new rule file in Section 9 (Error Compounding Protocol).

5. **Any agent that checks off a ROADMAP.md item MUST update AGENTS.md Section 5 tables.**
   - Change `☐` to `✓` in the ABSENT table OR move the item to the IMPLEMENTED table.
   - Keep the numbering and phase labels consistent with ROADMAP.md.

6. **Non-Claude agents that cannot write to `.claude/rules/` MUST write to AGENTS_ERRATA.md.**
   - At the start of the next Claude Code session, a human agent reconciles AGENTS_ERRATA.md into `.claude/rules/` and updates AGENTS.md.
   - This is the bridge for knowledge from non-Claude sessions.

7. **The sync is healthy when:**
   - ✓ Every law in CLAUDE.md Section 3 appears in AGENTS.md Section 3.
   - ✓ Every prohibition in `.claude/rules/godot-47-core.md` appears in AGENTS.md Section 3 or Section 9.
   - ✓ Every prohibition in `.claude/rules/soccer-physics.md` appears in AGENTS.md Section 3 or Section 9.
   - ✓ Every prohibition in `.claude/rules/ai-architect.md` appears in AGENTS.md Section 3 or Section 9.
   - ✓ ROADMAP.md checkbox state matches AGENTS.md Section 5 tables.
   - ✓ AGENTS_ERRATA.md (if it exists) has a note in this document referencing it.

### What Stays in Sync

| Source | Destination | Update Rule |
|---|---|---|
| CLAUDE.md § 3 | AGENTS.md § 3 | Every session |
| .claude/rules/godot-47-core.md | AGENTS.md § 3 & 9 | Every session |
| .claude/rules/soccer-physics.md | AGENTS.md § 3 & 9 | Every session |
| .claude/rules/ai-architect.md | AGENTS.md § 3 & 9 | Every session |
| ROADMAP.md checkboxes | AGENTS.md § 5 tables | Every session |
| AGENTS_ERRATA.md (non-Claude) | .claude/rules/ (Claude) | Next Claude session |

### Maintenance

This file (AGENTS.md) should be treated as a living document. It is the synchronization hub for multi-agent work. When the codebase evolves, the sync evolves with it.

**Update AGENTS.md immediately when:**
- A new architectural law is discovered and added to CLAUDE.md.
- A new `.claude/rules/` file is created.
- A ROADMAP.md item is checked off.
- A novel failure mode is discovered and recorded in AGENTS_ERRATA.md.

Do not let the sync drift. The health of the repository depends on it.

---

## Quick Reference: Where to Make Changes

| Goal | File to Edit |
|---|---|
| Add an architectural law | CLAUDE.md Section 3 + AGENTS.md Section 3 |
| Document an engine mistake | .claude/rules/godot-47-core.md + AGENTS.md Sections 3 & 9 |
| Document a physics mistake | .claude/rules/soccer-physics.md + AGENTS.md Sections 3 & 9 |
| Document an AI mistake | .claude/rules/ai-architect.md + AGENTS.md Sections 3 & 9 |
| Check off a ROADMAP item | ROADMAP.md + AGENTS.md Section 5 |
| Add a new system domain | Create .claude/rules/[domain].md + update AGENTS.md Sections 3, 9, and this table |
| Non-Claude error discovery | AGENTS_ERRATA.md |

---

End of AGENTS.md. Session complete when all 11 sections are in place and the sync protocol is understood.
