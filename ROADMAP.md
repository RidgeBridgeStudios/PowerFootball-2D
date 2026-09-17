# ROADMAP.md

> **Re-based on the manager-only pivot.** This checklist tracks the career / quick-sim football management game.
> The former real-time 22-player match engine was archived under `legacy/` (skipped by `legacy/.gdignore`), so all
> real-time match-engine items are retired there. Match-fidelity work now belongs to `shared/QuickSimEngine.gd`.
> See @./POWERFOOTBALL_MASTER_VISION.md — read its `## Pivot Note` first; it is a historical design record, not current guidance.

Canonical feature checklist for PowerFootball-2D. Each phase should produce a meaningful, playable improvement before moving to the next.

## PHASE 1 — Gameplay Completeness

Core football mechanics that must work before anything else. Under the pivot these are resolved by `QuickSimEngine` or managed in the career UI.

- [x] Squad, lineup and bench management UI (`ui/manager_mode/SquadPanel.gd`, `ui/manager_mode/TacticsPanel.gd`, `shared/TeamManagementData.gd`)
- [x] Yellow/red card implementation (quick-sim discipline events in `shared/QuickSimEngine.gd`, counted in `autoloads/MatchStatsTracker.gd`)
- [x] Offside counting in quick-sim match stats (`shared/QuickSimEngine.gd`; surfaced in `ui/MatchStatsUI.gd`)
- [x] Injury system (career persistence: daily injury rolls in `shared/career/TrainingSchedule.gd`, recovery in `shared/career/PlayerCareerState.gd`)
- [x] Match stats screen + full-time scoreboard (`ui/MatchStatsUI.gd`)
- [x] End-of-match player ratings (`shared/PlayerRatingCalculator.gd`)
- [x] Knockout tie resolution — extra-time / penalty stand-in (`shared/career/CompetitionData.gd::_resolve_tie_winner`)

*Retired with the archive (equivalent fidelity work belongs to `QuickSimEngine`): goalkeeper dive commitment, aerial/heading resolution, through-ball lead targeting, phase-dependent dynamic formation anchors.*

## PHASE 2 — Personality and Traits

Make players feel like individuals with relationships and hidden depth.

- [x] Player trait bitmask on PlayerData (64-bit `@export_flags` on `PlayerData.traits`, 13 blue/red traits)
- [x] Trait effects wired into career systems (11/13 traits wired across `MoraleEngine`, `PlayerDevelopmentEngine`, `TrainingSchedule`, `ScoutingNetwork`, `InboxEngine`, `CareerManager`, `PressOffice`; DeepRunner/WallSplitter were match-AI-only and are retired with `legacy/` — see `docs/SOCIAL_SIMULATION_ARCHITECTURE.md` §1)
- [x] overall_rating and reputation derived fields (`PlayerData.calculate_overall_rating()`; `player_reputation` now drifts from match performance via `MoraleEngine.apply_reputation_drift()`)
- [x] Career relationship graph (`shared/career/RelationshipData.gd`, consumed by `MoraleEngine`, `PlayerCareerState` and `SquadPanel`)
- [x] Manager-trust swings on inbox decisions (`shared/career/InboxEngine.gd` adjusts `PlayerCareerState.manager_trust`)
- [x] Relationship drift across the season (`shared/career/MoraleEngine.gd`)
- [x] Statistical star-marking & tactical shadowing in quick-sim (`shared/QuickSimEngine.gd`, `shared/PlayerData.gd`): Derive Star Tier (`star_score = 0.4 * (overall_rating - 45)/54 + 0.6 * player_reputation`; `World Class >= 0.80`, `Star >= 0.62`, `Regular < 0.62`) per `docs/SOCIAL_SIMULATION_ARCHITECTURE.md` §4.1. In `QuickSimEngine.simulate_match()`, if the opponent features a Star or World Class player, the opposing manager's defensive setup applies statistical star-shadowing: dampens that player's individual goal/assist generation probability (by 30–50%) while proportionally increasing fatigue accumulation on the marker and elevating space/chances for secondary runners. Acceptance: pure static resolution, 0 allocations, verified in `tools/test_quick_sim.py`.
- [x] Ego / catering pass-starvation morale penalty (`autoloads/CareerManager.gd`, `shared/career/MoraleEngine.gd`, `shared/PlayerData.gd`): Post-match hook in `CareerManager._apply_fixture_result()` compares player event share (`touches_player / touches_team` from `MatchStatsTracker` / `QuickSimResult`) against `expected_share = lerp(0.06, 0.14, player_reputation)` per `docs/SOCIAL_SIMULATION_ARCHITECTURE.md` §4.3. If starved, apply asymmetric morale delta `clampf((actual_share - expected_share) * 1.5, -0.08, 0.04)` to `PlayerData.morale`. Acceptance: applied only in career post-match processing; updates `PlayerData.morale`.
- [x] Match micro-events to persistent relationship batching (`autoloads/CareerManager.gd`, `shared/career/RelationshipData.gd`): Batch match event summaries (goals, assists, cards, teammate interactions recorded in `QuickSimResult.player_events`) into persistent `RelationshipData` edges at match end per `docs/SOCIAL_SIMULATION_ARCHITECTURE.md` §2.2. Acceptance: batched at match end, no mid-match signal listeners, no-op when `CareerManager.career == null`.
- [x] Player–manager relationship edge keying (`shared/career/RelationshipData.gd`, `shared/career/PlayerCareerState.gd`, `shared/career/InboxEngine.gd`): Reserve manager relationship key space `MANAGER_RELATIONSHIP_KEY_BASE = 100000` (`100000 + league_team_index`) in `PlayerCareerState.relationships` per `docs/SOCIAL_SIMULATION_ARCHITECTURE.md` §2.3. Tracks manager trust, benching resentment scaled by `(1.0 - loyalty)`, and captain "sounding board" inbox dialogues. Acceptance: reuses `RelationshipData` methods without schema changes.

## PHASE 3 — Club World

Bridge between match events and player life between matches.

- [x] WorldEvent struct and WorldEventLog autoload
- [x] Substitution reaction events
- [x] Training incidents and dressing-room confrontations
- [x] Street football / nightlife / media events
- [x] PressOffice consumption of WorldEvent log (`WorldEventLog.generate_press_reaction()`)
- [x] Manager response system
- [x] Dressing room mutiny & crisis escalation system (`shared/career/WorldEventGenerator.gd`, `shared/career/BoardState.gd`, `shared/career/InboxEngine.gd`): Implement `check_mutiny_threshold(team: TeamData, career: CareerSaveData) -> bool` per `docs/Social Dynamics Simulation Engine Implementation.md`. Evaluates dual conditions: mean squad morale < 0.35 AND mean manager trust among squad leaders (`CaptainMaterial`, `VeteranLeader`, or `player_reputation >= 0.70`) < 0.30. Emits `WorldEvent` with tag `&"mutiny_warning"` or `&"dressing_room_mutiny"`, generating high-priority `InboxItem` requiring manager response or triggering board intervention in `BoardState.gd`. Acceptance: dual-threshold condition strictly enforced; emits `WorldEvent` (significance >= 0.8) without serializing closures.
- [ ] Squad clique & faction dynamics (`shared/career/MoraleEngine.gd`, `shared/career/RelationshipData.gd`, `shared/NationDatabase.gd`): Identify social sub-graphs in `PlayerCareerState.relationships` based on mutual trust >= 0.70, shared nationality/language (`NationDatabase`), and shared manager resentment. Faction leader morale swings propagate to clique members via peer diffusion with numerical damping. Acceptance: bounded within `[0.0, 1.0]`; prevents runaway feedback loops.
- [ ] PressOffice between-match incident narrative pipeline (`entities/manager/PressOffice.gd`, `autoloads/WorldEventLog.gd`, `shared/career/InboxEngine.gd`): Connect `WorldEventLog` unhandled incidents (training clashes, nightlife breaches, mutiny warnings) directly into pre/post-match press conference questionnaires in `PressOffice.gd`. Acceptance: questions cite player names, incident tags, and sentiment; responses affect board confidence and player trust.

## PHASE 4 — Career Mode

Multi-match progression with persistence, transfers, and season structure.

- [x] Career calendar and scheduling (`CareerDate`, `CareerManager.advance_day()`, adaptive matchday spacing)
- [x] League table persistence (`CompetitionData`, `LeagueTableRow`, saved per slot)
- [x] Transfer window system (`TransferMarket`, `TransferOffer`, summer/winter locks)
- [x] Season progression and contracts (`ContractData`, ageing, rollover, youth intake)
- [x] Staff system (staff-driven coaching, physio, scouting quality)
- [x] Manager Career mode unlock (`ui/manager_mode/`, reachable from the main menu)
- [x] Save/load with slots and versioned migration (`CareerSerializer`, 3 slots)
- [x] Board expectations, confidence, requests and sacking (`BoardState`)
- [x] Inbox, press conferences and player interactions (`InboxEngine`)
- [x] Scouting network with uncertainty-based reports (`ScoutingNetwork`, `ScoutReport`)
- [x] Finances: budgets, ledger, amortisation, gate receipts (`ClubFinances`)
- [x] Training schedules, individual focus, injuries (`TrainingSchedule`)
- [ ] Continental competition multi-stage tournament structure (`shared/career/CompetitionData.gd`, `autoloads/CareerManager.gd`, `ui/manager_mode/FixturesPanel.gd`): Expand knockout placeholder into complete multi-stage tournament (group stage with 4-team round-robin home/away, two-legged knockout rounds with aggregate scoring and extra-time/penalties via `QuickSimEngine`, neutral single-match final). Acceptance: group tables sorted by points, goal difference, goals scored; calendar fixtures integrate without congestion crashes in `CareerManager.advance_day()`.
- [ ] Stadium expansion & infrastructure investment system (`shared/career/ClubFinances.gd`, `shared/career/BoardState.gd`, `ui/manager_mode/FinancesPanel.gd`, `ui/manager_mode/BoardPanel.gd`): In `ClubFinances.gd`, track `stadium_expansion_capacity`, `expansion_completion_date`, and `expansion_cost`. Manager requests capacity expansion or facility upgrades via `BoardState.file_request()`. Board evaluates balance and club stature. Capital expense is booked (lump sum or instalments), construction progresses on daily tick, and upon completion increases `stadium_capacity` (raising matchday gate receipts in `book_matchday()`) or facility tier (boosting `YouthAcademy` intake quality and `TrainingSchedule` injury recovery). Acceptance: serialized in `CareerSaveData`; board confidence reacts to financial health; matchday receipts scale accurately.
- [ ] Regional scouting network & Bayesian attribute weighting (`shared/career/ScoutingNetwork.gd`, `shared/career/ScoutReport.gd`, `ui/manager_mode/ScoutingPanel.gd`): Implement position-specific attribute weighting matrix (36-to-13 aggregation for GK, CB, FB, DM, CM, AM, W, ST per `docs/Bayesian Scouting & Attribute Weighting Implementation Plan.md`). Replace linear knowledge bar with precision-space conjugate Gaussian Bayesian updating (prior variance $\sigma_0^2$, scout observation noise based on `judging_ability`, posterior mean and credible intervals). Track regional familiarity accumulation for assigned scouts. Acceptance: scout reports show narrowing attribute range bands as observations accumulate; regional familiarity persists per scout in `CareerSaveData`.
- [ ] Loan market system & contract purchase option clauses (`shared/career/TransferMarket.gd`, `shared/career/TransferOffer.gd`, `shared/career/ContractData.gd`, `ui/manager_mode/TransfersPanel.gd`): Enhance transfer market with loan listings, configurable wage contribution splits (`ContractData.loan_wage_subsidy`), loan durations (half/full season), parent-club recall clauses, and optional/mandatory purchase fee options. Acceptance: loan transactions update squad rosters while preserving parent club ownership; loan wage bill properly reflects subsidies in `ClubFinances.weekly_wage_bill()`.
- [x] Promotion/relegation across multiple divisions (multi-tier support via `tier_indices` in `CareerSaveData` and `CareerManager._apply_promotion_relegation()`; see `docs/PHASE_0_FIXES.md`)

## PHASE 5 — Polish

Audio, theming, and final presentation for the manager experience.

- [ ] UI virtualization & high-performance component controls (`ui/manager_mode/LazyListBox.gd`, `ui/manager_mode/VirtualTable.gd`, `ui/manager_mode/UIPanelStack.gd`, `ui/manager_mode/SquadPanel.gd`, `ui/manager_mode/TransfersPanel.gd`): Implement `LazyListBox.gd` (visible-row pool recycling) and `VirtualTable.gd` (custom CanvasItem draw-based table with sortable column headers) per `docs/PowerFootball-2D UI Architecture Plan.md`. Integrate `UIPanelStack.gd` for LIFO panel navigation with deferred redraw on activation. Acceptance: zero heap allocations during scrolling across 1000+ player records; steady 60 FPS in Godot 4.7.
- [ ] Manager UI theme, typography & responsive club palettes (`ui/manager_mode/CareerTheme.gd`, `shared/career/CareerThemePalette.gd`, `ui/manager_mode/ManagerModeRoot.gd`): Implement unified Godot `Theme` resource integrating header/body typography hierarchies, high-contrast dark palette, dynamic primary/secondary accent coloring sampled from `TeamData.primary_color`/`secondary_color`, and responsive layout scaling. Acceptance: all 13 manager mode panels inherit unified styling without inline overrides; reactive to window resize.
- [ ] Comprehensive real squad JSON database & schema validation (`data/league.json`, `data/players.json`, `data/teams.json`, `data/managers.json`, `data/referees.json`, `data/staff.json`): Expand JSON datasets to populate multi-tier authentic club rosters, complete attribute sets [0.0, 1.0], calibrated trait bitmasks, staff rosters, and referee profiles compliant with `docs/json-schema.md`. Acceptance: passes `tools/verify_db.py` and strict schema validation with 0 errors or warnings; all entity IDs maintain referential integrity.
- [ ] Interactive matchday broadcast & Moneyball analytical dashboard (`ui/MatchStatsUI.gd`, `ui/QuickSimModal.gd`, `shared/QuickSimEngine.gd`): Enhance quick-sim matchday presentation with chronological text commentary ticker, dynamic momentum flow charts (rolling xG / field tilt), and team comparison radar visualizations based on `QuickSimResult.advanced_stats`. Acceptance: commentary playback streams from pre-computed match events with adjustable playback speed and instant-skip; zero allocations during playback loop.
- [ ] Manager audio ambience & UI sound design (`autoloads/AudioManager.gd`, `default_bus_layout.tres`, `ui/manager_mode/*`, `ui/OptionsMenu.gd`): Implement sound design for managerial actions: UI button clicks/tabs, paper/folder rustling, calendar tick, matchday referee whistle, crowd goal alerts, and urgent inbox notification chimes. Acceptance: audio events trigger via `GameEvents` signals without blocking simulation ticks; clean volume sliders in `ui/OptionsMenu.gd`.
