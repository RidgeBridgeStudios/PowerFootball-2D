# autoloads/ — Singletons & Global Services

Autoloads are the backbone of PowerFootball-2D's layered architecture. They initialize in order (see CLAUDE.md) and must never reference each other directly in `_ready()`.

## Boot Order (project.godot)

1. **MatchWorldModel** — Spatial cache for all players and ball
2. **GameEvents** — Signal bus for inter-system events
3. **GameManager** — Match phase, score, clock, set piece coordination
4. **MatchStatsTracker** — Per-match team stats and per-player ratings event accumulator
5. **DataLoader** — JSON parsing; player/manager/team instantiation
6. **RefereeLoader** — Referee database
7. **ManagerLoader** — Manager database and formation library
8. **InputHelper** — Player input mapping

Do not change this order without updating CLAUDE.md and all dependent systems.

## Key Responsibilities

### MatchWorldModel.gd

**Contract:** Single source of truth for player and ball positions in 3D space.

**Exports:**
- `player_positions: Dictionary[int, Vector2]` — Spatial cache keyed by world_index
- `player_nodes: Array[Node2D]` — Direct references
- `ball_node: Node2D` — Ball reference (set by PitchScene)
- `instance: MatchWorldModel` — Singleton getter

**Must Read From:**
- `player_index = world_index` assignment per player in `_ready()`
- `register_player(index, node, team)` for roster initialization
- `nearest_opponent_dist_to(from_index, exclude_team)` for spatial queries

**DO NOT:**
- Call `get_tree().get_nodes_in_group()` inside AI loops
- Cache player positions; query the model every frame
- Use stale `player_nodes` references in Practice Arena (many freed mid-match)

---

### GameEvents.gd

**Contract:** Central signal bus. No other system references each other directly; all communication routes here.

**Critical Signals:**
- `ball_struck(kicker, speed, charge_ratio, is_shot)` — Any kick action
- `goal_scored(team, scorer)` — Ball in goal (scorer is last_touched_by; scorer.team != team is an own goal)
- `foul_committed(offender, victim, foul_type)` — Player rule violation
- `match_phase_changed(new_phase)` — Phase transitions
- `substitution_made(team, player_out_idx, player_in_idx)` — Reserve entry
- `manager_formation_changed(team, formation_name)` — Tactical shift (emitted by ManagerDirector, not ManagerLoader)
- `formation_anchors_changed(team, new_anchors)` — World-space anchor updates for AI steering

**DO NOT:**
- Reference other autoloads or scene nodes directly from GameEvents
- Emit signals outside of their intended origin file
- Use signals for cheap state queries; that is what MatchWorldModel and data structures are for

---

### GameManager.gd

**Contract:** Owns match phase, score, clock, and set piece initiation.

**Exports:**
- `match_clock: float` — Seconds elapsed (for UI and match flow)
- `score: Array[int]` — Current score `[home, away]`
- `current_phase: GameManager.MatchPhase` — Enum (PREGAME, KICKOFF, IN_PLAY, HALF_TIME, FULL_TIME, etc.)
- `match_duration: float` — Full-time duration (default 300.0s)

**Responsibilities:**
- Drive `GameEvents.match_phase_changed` on phase transitions
- Update clock and emit score changes
- Coordinate set pieces and penalties via `SetPieceCoordinator`
- Call `_end_match()` when time expires

**DO NOT:**
- Make gameplay decisions (fouls, offsides, possession). That is ref/AI territory.
- Directly modify player state
- Emit or consume non-match-phase signals

---

### MatchStatsTracker.gd

**Contract:** Per-match team aggregate stats and per-player event tracker for full-time ratings.

**Responsibilities:**
- Samples possession every 30 physics ticks (`POSSESSION_SAMPLE_INTERVAL = 30`) via `MatchWorldModel.possessor_index`
- Accumulates team stats: shots (total/on target), passes (attempted/completed), fouls, cards, corners, offsides
- Tracks per-player events keyed by `team * 1000 + squad_index`
- Computes end-of-match player ratings (1.0–10.0) via `PlayerRatingCalculator.gd`
- Provides match summary statistics to `MatchStatsUI.gd`

**DO NOT:**
- Query scene tree during possession sampling
- Mutate PlayerData directly; provide rating calculations via `compute_all_ratings()`

---

### DataLoader.gd

**Contract:** Parses JSON; instantiates PlayerData, ManagerData, TeamData; populates singletons.

**Exports:**
- `players: Dictionary[String, PlayerData]` — Keyed by player_id
- `managers: Dictionary[String, ManagerData]` — Keyed by manager_id
- `teams: Dictionary[String, TeamData]` — Keyed by team_id

**Responsibilities:**
- Load `res://data/*.json` at boot
- Instantiate data classes from JSON
- Validate references (team IDs exist, etc.)

**DO NOT:**
- Modify data at runtime (data is loaded once; use WorldEvent log for career changes)
- Emit GameEvents (that is GameManager's role)
- Reference scene nodes

---

### RefereeLoader.gd & ManagerLoader.gd

Similar to DataLoader; pure database loaders.

**RefereeLoader:**
- `referees: Dictionary[String, RefereeData]`
- Used by `MatchReferee` to instantiate personality-weighted foul decisions

**ManagerLoader:**
- `managers: Dictionary[String, ManagerData]`
- Formation library accessed by `ManagerDirector`
- Note: Formation signal is emitted by ManagerDirector, not ManagerLoader

---

### InputHelper.gd

**Contract:** Maps player input to standardized action signals.

**Responsibilities:**
- Detect gamepad and keyboard input
- Emit action events (move, pass, tackle, sprint, etc.)
- Handle input blocking during pause/cutscenes

**DO NOT:**
- Make gameplay decisions based on input (that is PlayerBrain)
- Cache player references; query MatchWorldModel

---

## Adding a New Autoload

1. Create the file in `autoloads/`
2. Register in `project.godot` (Scene → Autoload)
3. Update boot order in CLAUDE.md if it has dependencies on other autoloads
4. Emit all events through GameEvents; receive through signal connections in `_ready()`
5. Export a singleton getter if other scenes need to access it
6. Run `py -3 tools/gdcheck.py` to verify no undeclared members

---

## Notes

- Autoloads persist across scene changes; clear state in `_ready()` if re-entering a match
- Avoid circular references by never calling another autoload in `_ready()`; use signal connections instead
- Use `@export` only for things that are authored in the inspector (rare in autoloads)
