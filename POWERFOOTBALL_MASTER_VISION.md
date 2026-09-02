# POWERFOOTBALL_MASTER_VISION.md

<!-- Canonical vision, roadmap, system design, and agent protocol for PowerFootball-2D -->
<!-- Read this before any feature work. Synthesizes grand vision, recommended build order, and AI-agent operating guidance. -->
<!-- ENGINE LOCK: Godot 4.7-stable | GDScript 2.0 ONLY | NO DEPRECATED APIS -->
<!-- VERIFICATION: python3 tools/gdcheck.py -->

---

# Part I — The Grand Vision

## The Core Design Philosophy

PowerFootball-2D is **Dwarf Fortress with a football**. The visuals are a viewport into a living social simulation, not the game itself. The game itself is the world underneath.

This project makes the same foundational trade that Dwarf Fortress made. ASCII graphics bought simulation depth: geology, fluid logic, injuries, personalities, social relationships, and emergent history. Here, overhead dots buy football depth: squad chemistry, star psychology, manager-player conflict, off-pitch events, match-to-match memory, and emergent narrative.

The visual reference is old Football Manager 2D match view, but made playable. You are not just watching pieces move. You are intervening inside a story engine. A great moment in this game is not "that passing triangle looked smooth." It is "my striker refused to pass to the right back for half the match because trust broke down three weeks ago in training."

The gameplay priority is slow, weighty, believable football. Heavy movement, turning arcs, friction, pseudo-3D ball travel, and readable overhead play matter more than flashy presentation. The game must feel like football before it tries to look like football.

The long-term ambition is to become one of the deepest football simulations ever made, precisely because it refuses to spend its complexity budget on photorealism. The dots are not placeholder graphics. The dots are the medium through which the simulation becomes legible.

## Design References

| Reference | What to take |
|---|---|
| Early Football Manager 2D match engine | Overhead, readable, systemic match presentation that is playable rather than merely watchable |
| Dwarf Fortress | Multi-layer simulation where low-level events propagate upward into narrative |
| Power Pros / Pro Yakyuu Spirits | Trait icons and hidden modifiers that materially change outcomes, not just labels |
| PS2 FIFA Manager Mode | Off-pitch incidents, player life between matches, and career-mode texture |
| PES Super Cancel | Human agency that can break out of automation and pathfinding lock |

## The North Star

The game is finished when a fully autonomous CPU-vs-CPU match can be watched like a broadcast and generate a story worth retelling, with players behaving as if they remember one another, managers reacting to accumulated context, and the press layer translating all of it into football drama.

---

# Part II — The Simulation Stack

PowerFootball-2D runs on five layers simultaneously. Events propagate upward. The chain itself creates the story.

```text
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

A typical propagation chain is straightforward. A bad tackle in physics creates emotional fallout in the match-social layer. That modifies trust in the club-world layer. The fallout becomes a dressing-room or media event. Then the narrative layer turns it into dialogue, press reaction, or a touchline story beat.

Every major feature should touch at least two layers. A system that only exists in one layer is probably ornamental rather than foundational.

---

# Part III — What Is Already Built

The repo already moved from a skeleton to a substantial football simulation foundation across 24 major changes, covering physics, set pieces, AI, manager systems, HUD, menus, and agent scaffolding.

| # | PR / Commit | What was built |
|---|---|---|
| 1 | PR #1 Foundation | `HeavyPlayerController`, pseudo-3D ball, FSMs, `GameEvents`, `GameManager`, HUD, test pitch |
| 2 | PR #2 Set Pieces | Kickoff, goal kick, corner, throw-in, free kick, penalty, `SetPieceCoordinator`, `PitchBoundary` Area2D |
| 3 | PR #3 Data / Roster | `PlayerData`, `TeamData`, `LeagueData`, `DataLoader`, `PlayerFactory`, FC Nordvik, CD Solano |
| 4 | PR #4 Mood | `MoodSystem` with SLUMP / NORMAL / STREAK affecting AI and kick scatter |
| 5 | PR #5 Referee | `RefereeData`, `RefereeLoader`, `MatchReferee`, personality-weighted foul decisions, stat persistence |
| 6 | PR #6 Manager | `ManagerData`, `ManagerLoader`, `FormationLibrary`, `ManagerDirector`, `PressOffice` |
| 7 | Commit #7 Main Menu | `MainMenu.tscn`, Kick Off, Practice, locked career modes, Options, Quit, `KickOffMenu` |
| 8 | PR #8 11v11 | Full 22-player pitch, `PitchMarkings.gd`, goalkeeper AI and goal-line anchor |
| 9 | PR #9 Chase Fix | Role enum and `_should_chase_ball()` gates, `ManagerDirector` tempo fix |
| 10 | PR #10 Touchline | `TouchlineBubble` manager reactions for key match events |
| 11 | PR #11 Off-Ball AI | Role-specific possession-aware targets and auto-switch to nearest teammate |
| 12 | PR #12 Practice | Practice Arena mode with reset, free kick, penalty, and GK freeze toggles |
| 13 | PR #13 Pass + Wall | CPU passing, pursuit steering, GK intercepts, defensive wall, half-time swap |
| 14 | PR #14 Dribble Fix | `TOUCH_SPEED_RATIO` tuning and `FacingArrow.gd` |
| 15 | PR #15 HUD | Nameplate panel and minimap with team-coloured shirt-number dots |
| 16 | PR #16 Utility AI | `UtilityContext` plus Pass / Chase / Space / Dribble / Formation scorers |
| 17 | PR #17 Camera | `MatchCamera.gd` with BALL_FOLLOW, DYNAMIC, and FULL_FIELD modes |
| 18 | PR #18 ActionText | Floating PASS / SHOT / LOB SHOT / THROW labels |
| 19 | PR #19 Facing | `get_facing_dot()` and facing-weighted tackling plus AI penalties |
| 20 | PR #20 PreGame | `PreGameScreen`, `PauseMenu`, lineup order from `TeamData.lineup_indices` |
| 21 | PR #21 Magnetism | Continuous possession magnetism and grace window in `DribbleState` |
| 22 | PR #22 ShotLock | Travel-direction carry target, stronger magnetism, `ShotLockState` |
| 23 | PR #23 ReGrab Fix | `_released` throw-in guard and set-piece foot-sensor protection |
| 24 | PR #24 WorldModel | `MatchWorldModel`, `UtilityMath.gd`, 15-frame AI stagger, Claude agent scaffold |
| 25 | Phase 4 Career | Manager Career mode: `CareerManager` + `WorldEventLog` autoloads, 18 career Resources in `shared/career/`, and the FM-style `ui/manager_mode/` shell (13 sections) |

### Phase 4 — What the career layer added

**Data (`shared/career/`):** `CareerDate` (real calendar arithmetic),
`CareerSaveData`, `CompetitionData` (circle-method scheduler + cup draws),
`FixtureData`, `LeagueTableRow`, `ContractData`, `PlayerCareerState`,
`RelationshipData`, `ClubFinances`, `BoardState`, `TrainingSchedule`,
`ScoutReport`, `TransferOffer`, `InboxItem`, `WorldEvent`,
`ManagerCareerProfile`, `CareerThemePalette`.

**Engines:** `MoraleEngine`, `PlayerDevelopmentEngine`, `TransferMarket`,
`ScoutingNetwork`, `YouthAcademy`, `InboxEngine`, `CareerSerializer`.

**Why it is not a single-layer system.** The career wrapper only earns its place
because it writes back down the stack, and it does so at one choke point:
`PlayerFactory.apply()` calls `CareerManager.apply_career_state_to_player()` for
all 22 players at every match bind.

- **-> Layer 3:** accumulated career morale and form seed `MoodSystem.mood_value`.
  A player left out for months genuinely starts the match in SLUMP; one riding a
  contract renewal starts in STREAK. The slope is asymmetric and calibrated so
  the authored default player still lands exactly on NORMAL.
- **-> Layer 2:** persistent `RelationshipData` trust seeds `TrustSystem`, so
  `PassUtilityScorer`'s trust multiplier opens a match already carrying months of
  dressing-room history instead of a flat neutral slate.
- **-> Layer 5:** `WorldEventLog.generate_press_reaction()` routes club-world
  events back through the existing `PressOffice`, so career narrative speaks in
  the same trait-driven voice as the touchline and post-match lines.

That chain — a training injury or a broken playing-time promise in Layer 4
changing who a player looks for on the pitch in Layer 2 — is the propagation the
vision asks every major feature to produce.

---

# Part IV — What Is Missing

## Immediate Match Completeness

The core football foundation is functional, with out-of-bounds boundary routing, offside detection, goalkeeper dive commitment, substitutions and reserve bench management, referee cards, penalty shootouts, match stats, and dynamic phase-dependent formation anchors operational in Phase 1.

The remaining match-level gameplay features to round out full on-pitch simulation include:
- **Injury system:** Physical knocks, stamina degradation under heavy fatigue, and forced tactical substitutions.
- **AerialState & Heading Resolution:** Complete contest physics and directional header placement from crosses and set pieces.
- **Through-Ball Lead Targeting:** Anticipatory passes into open space ahead of a sprinting teammate's vector.

## Deep Simulation Gaps

The game's long-term identity depends on systems that are still in progress. These include a persistent relationship trust graph, a Power Pro-style player trait system, star-player reputation and treatment, off-pitch life events, a `WorldEvent` log, and a real career-mode calendar with league progression and transfer logic.

The data layer has expanded with `league.json`, `managers.json`, and `referees.json`, validated by `tools/verify_db.py`, with room for deeper relational metadata, biography seeds, and career contracts.

---

# Part V — Deep Systems Design

## Relationship Trust Graph

`PlayerData` should gain a persistent relationship dictionary keyed by player identifier. Each relation stores trust, rivalry, tagged event history, and last meaningful interaction. This turns match behavior into accumulated social memory rather than isolated state.

```gdscript
class_name RelationshipData
extends Resource

@export var trust: float = 0.0
@export var rivalry_score: float = 0.0
@export var history: Array[String] = []
@export var last_interaction_match: int = 0

# On PlayerData:
var relationships: Dictionary = {}
```

This plugs directly into the existing utility pass scorer. A player with low trust in a teammate should score that pass target lower, while a bonded pair should find one another more often. That is one of the clearest ways to make the social simulation visible on the pitch.

```gdscript
var rel: RelationshipData = carrier.player_data.relationships.get(candidate.player_id)
var trust_weight: float = lerp(0.6, 1.2, rel.trust if rel else 0.5)
score *= trust_weight
```

## Trait Bitmask

The repo already has a useful pattern in manager traits. `PlayerData` should gain the same kind of bitmask-driven architecture so traits remain cheap to store, cheap to test, and easy to wire into existing systems.

```gdscript
@export_flags(
    "DeepRunner:1",
    "WallSplitter:2",
    "PressureImmune:4",
    "HotHeadedTackler:8",
    "Talisman:16",
    "LockerRoomCancer:32",
    "CaptainMaterial:64",
    "StreetBaller:128",
    "PrideGlory:256",
    "VeteranLeader:512",
    "DeadBallSpecialist:1024",
    "NightOwl:2048",
    "IronMan:4096"
) var traits: int = 0
```

Each trait should modify a system that already exists instead of creating a parallel architecture. `DeepRunner` alters off-ball channel weighting, `PressureImmune` resists SLUMP logic, `HotHeadedTackler` increases foul probability, `StreetBaller` influences off-pitch injury events, and `PrideGlory` affects substitution reaction outcomes.

## Aerial Contact Personality Weighting (Future Refinement)

`AerialState._attempt_contact()` currently picks header / volley / bicycle kick from a pure geometry read — ball height and `facing_goal_dot` only (see `AGENTS_ERRATA.md`'s `bicycle-kick-dominates-ambiguous-facing` for the header-default fix already applied there). It has no access to attributes, traits, or match context, so every eligible player attempts a bicycle kick with the same willingness in the 89th minute of a scoreless draw as in the 3rd minute of a friendly.

Once heading-relevant attributes/traits exist, `_attempt_contact()`'s branch should weight *willingness* to attempt the flashier, higher-risk strikes (volley, and especially bicycle kick) rather than deciding on geometry alone:

- **Heading skill/preference** — a low heading attribute (or a trait leaning away from aerial ability) should bias toward the safe, reliable header even when the geometry would otherwise permit a volley/bicycle attempt; a confident/skilled header of the ball should commit to headers more often too, not just default into them by elimination.
- **Match desperation** — losing (or drawing when a win is needed) in the closing minutes should raise willingness to gamble on a bicycle kick, mirroring how `MoodSystem`/composure already bias other risk-taking (see `PassUtilityScorer.PRESSURE_SAFETY_SHIFT` for the existing pattern of a match-state signal reshaping a weighted choice).
- **Proximity to goal** — a bicycle kick struck from distance is mostly cosmetic risk with no reward; the willingness weighting should scale up sharply only inside real shooting range, not uniformly across the pitch.
- **Personality trait** — `StreetBaller` (already listed above, currently only wired to off-pitch injury events) is the natural existing hook for "attempts flashy strikes more readily" rather than inventing a new bitmask flag.

This is deliberately a *willingness* weighting layered on top of the existing geometry gate, not a replacement for it — the height/facing conditions still decide what's physically possible; attributes/traits/match-state should decide what a given player *chooses* to attempt among the options geometry allows.

## Star System

`PlayerData` should gain derived `overall_rating` and `reputation` fields. `overall_rating` is calculated from weighted football attributes rather than authored by hand, while `reputation` accumulates over career events and decays slowly over time. This distinction allows some players to be efficient but not famous, and others to be famous enough to distort tactical behavior.

When a player's reputation crosses a threshold, the opposing AI should be able to enter a star-marking utility mode. That means at least one defender gives up ideal formation anchoring to prioritize shadowing the star. This creates the football sensation that elite players are treated differently by the match itself.

## Off-Pitch World Events

Career mode should run a `WorldEvent` layer between matches. This is the bridge between simulation depth and narrative output, and it is the cleanest way to integrate training incidents, dressing-room tension, injuries from bad choices, media noise, and contract drama.

```gdscript
class_name WorldEvent
extends Resource

@export var timestamp_match: int = 0
@export var event_tag: String = ""
@export var primary_player_id: String = ""
@export var secondary_player_id: String = ""
@export var narrative_context: String = ""
@export var resolved: bool = false
@export var resolution_choice: int = -1
```

## JSON Schema Direction

The repo should define a complete schema for player and manager JSON authoring. That schema needs to cover football attributes, personality traits, relationships, style preferences, biography, contract data, and manager philosophy so future imports of real teams are predictable and AI-agent-friendly.

---

# Part VI — Recommended Build Order

The strongest roadmap is to move in phases where each phase produces a meaningful, playable improvement instead of chasing the full grand vision at once.

```text
PHASE 1 — Gameplay completeness
  [x] 1. Substitutions + reserves UI
  [x] 2. Yellow/red card implementation
  [x] 3. Offside detection
  [ ] 4. Injury system
  [x] 5. Match stats screen + full-time scoreboard
  [x] 6. End-of-match player ratings
  [x] 7. Goalkeeper dive commitment
  [ ] 8. AerialState / heading resolution
  [x] 9. Penalty shootout flow
  [ ] 10. Through-ball lead targeting
  [x] 11. Phase-dependent dynamic formation anchors

PHASE 2 — Personality and traits
  [ ] 12. Player trait bitmask on PlayerData
  [ ] 13. Trait effects wired into existing systems
  [ ] 14. overall_rating and reputation derived fields
  [ ] 15. Star-marking utility scorer
  [ ] 16. Relationship trust graph
  [x] 17. Trust multiplier on pass utility
  [x] 18. Trust decay/gain events

PHASE 3 — Club world
  [ ] 19. WorldEvent struct and WorldEventLog autoload
  [ ] 20. Substitution reaction events
  [ ] 21. Training incidents and dressing-room confrontations
  [ ] 22. Street football / nightlife / media events
  [ ] 23. PressOffice consumption of WorldEvent log
  [ ] 24. Manager response system

PHASE 4 — Career mode
  [x] 25. Career calendar and scheduling
  [x] 26. League table persistence
  [x] 27. Transfer window system
  [x] 28. Season progression and contracts
  [x] 29. Staff system
  [x] 30. Manager Career mode unlock

PHASE 5 — Polish
  [ ] 31. Audio system
  [ ] 32. Sprite and action animation
  [ ] 33. HUD theme and custom fonts
  [ ] 34. Local 2-player support
  [ ] 35. Real squad JSON database
```

This order is better than jumping directly to career mode because it preserves the core rule that the match itself must already feel valid before the world around it becomes complex. The soul of the project depends on both, but the match foundation comes first.

---

# Part VII — Repository Structural Improvements

The repo already has unusually strong AI scaffolding, including `CLAUDE.md`, `.claude/rules`, stop-hook verification, and a clear architecture direction. The next improvements should focus on faster orientation and lower context waste for coding agents.

## llms.txt

A root `llms.txt` should act as a universal static map for non-Claude agents, including Cursor, Copilot, and other repo-aware tools. It should point directly at the architectural choke points.

```text
# PowerFootball-2D — Godot 4.7 top-down football simulation. GDScript 2.0 only.
# "Dwarf Fortress with a football." Simple visuals; deep social simulation.

- POWERFOOTBALL_MASTER_VISION.md              # Canonical vision, roadmap, systems design
- CLAUDE.md                                    # Invariants, contracts, autoload order
- ROADMAP.md                                   # Canonical [ ]/[x] feature checklist
- autoloads/MatchWorldModel.gd                 # Spatial cache — ALL position reads go here
- autoloads/GameEvents.gd                      # Signal bus — ALL inter-system events
- autoloads/GameManager.gd                     # Match phase, score, clock, set pieces
- entities/player/PlayerBrain.gd               # Utility-scored AI decision model
- entities/player/HeavyPlayerController.gd     # Kinematic weight, stamina, input
- entities/ball/Pseudo3DBall.gd                # Ball physics, z-axis, shadow
- shared/PlayerData.gd                         # Player attributes, traits, relationships
- shared/ManagerData.gd                        # Manager personality, tactics, traits
- shared/UtilityMath.gd                        # Intercept solver, lane occlusion, sigmoid
- shared/CollisionLayers.gd                    # Layer constants — read before any physics
- .claude/rules/ai-architect.md                # AI/spatial decision invariants
- .claude/rules/godot-47-core.md               # Engine-specific syntax rules
- .claude/rules/soccer-physics.md              # Physics contracts
- docs/json-schema.md                          # Full schema for squad/manager JSON import
- tools/gdcheck.py                             # Static GDScript checker
```

## ROADMAP and Directory Readmes

A dedicated `ROADMAP.md` should mirror Part VI with explicit `[ ]` and `[x]` state, while per-directory `README.md` files should explain the contract of each key file in `autoloads/`, `entities/`, and `shared/`. This lowers orientation cost and reduces the odds that an agent re-implements something already present or violates a contract it never discovered.

---

# Part VIII — AI Coding Agent Protocol

This section synthesizes the operational guidance with the repo-specific architectural needs of PowerFootball-2D.

## Session Initialization

Claude Code sessions should start in maximum-autonomy mode with the strongest reasoning setting available, then verify model, effort, and dynamic workflow state before feature work begins.

```bash
claude --dangerously-skip-permissions --effort ultracode --model claude-opus-5
```

Inside the session, verify:

```text
/model claude-opus-5
/effort ultracode
/config
```

## Context Hygiene

The protocol stresses that long sessions decay in quality when context is allowed to saturate. Architecture and math work are best done in the low-to-mid context range. Around 70 percent context usage, compaction becomes mandatory, and subsystem changes should trigger `/clear` so stale assumptions do not bleed between physics, UI, and career logic.

```text
0%  ─────────────── 50%   OPTIMAL
50% ─────────────── 70%   MONITOR
70% ─────────────── 85%   DANGER
85% ────────────── 100%   CRITICAL
```

## Feature Development Loop

The strongest working loop is: lock the vision, generate the workflow, isolate implementation, verify after every write, then merge and record the new rule if a novel failure mode appeared. This is how the repo compounds agent intelligence over time rather than repeating old mistakes.

```text
1. VISION LOCK
2. WORKFLOW GENERATION
3. WORKTREE EXECUTION
4. VERIFICATION
5. MERGE + RULE UPDATE
```

## Prompt Template

A good repo-specific prompt gives full authority, references the invariant files explicitly, defines the target system, specifies mathematical or mechanical constraints, and ends with a hard verification requirement.

```text
[EXECUTION MODE: FULL AUTONOMY]
You have ownership of [TARGET SYSTEM] in PowerFootball-2D.
You are authorized to overwrite, refactor, or delete any file that violates architecture specs.

INVARIANTS:
- @.claude/rules/godot-47-core.md
- @.claude/rules/soccer-physics.md
- @.claude/rules/ai-architect.md
- All spatial reads -> MatchWorldModel
- All inter-system events -> GameEvents
- Zero untyped variants

TASK: [precise feature request]
MATHEMATICAL SPEC: [explicit formulas, thresholds, budgets]
VERIFY: Run python3 tools/gdcheck.py after every file write.
Do not stop until gdcheck reports zero errors.
```

## Pre-Flight Checklist

Before submitting a large prompt, confirm that autonomy is explicit, the engine lock is present, deprecated APIs are forbidden, spatial rules are named, allocation constraints are clear, scene-tree polling is banned, and verification ends in `gdcheck.py`. This is the difference between a productive agent session and an expensive cleanup session.

## Error Compounding

Every newly discovered failure mode should be written back into the relevant rule file before the session ends. Engine mistakes belong in `godot-47-core.md`, physics mistakes belong in `soccer-physics.md`, and AI architecture mistakes belong in `ai-architect.md`. If career mode and social simulation become large enough, they deserve new dedicated rule files of their own.

---

# Part IX — Maintenance Rule

This document should evolve with the codebase. When a feature is implemented, update Part III and the roadmap phase state together. When a new deep system is designed, add it to Part V and Part VI before implementation begins. When an agent discovers a new way to fail, Part VIII and the relevant `.claude/rules/` file should be updated the same day.

The project reaches its goal when a simulated match can generate a credible football story without needing photorealism to sell it. At that point, the dots will have proven they were enough all along.
