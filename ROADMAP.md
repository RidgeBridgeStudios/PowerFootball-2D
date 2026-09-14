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

## PHASE 3 — Club World

Bridge between match events and player life between matches.

- [x] WorldEvent struct and WorldEventLog autoload
- [ ] Substitution reaction events
- [ ] Training incidents and dressing-room confrontations
- [ ] Street football / nightlife / media events
- [x] PressOffice consumption of WorldEvent log (`WorldEventLog.generate_press_reaction()`)
- [ ] Manager response system

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
- [ ] Continental competition beyond the simplified knockout placeholder
- [x] Promotion/relegation across multiple divisions (multi-tier support via `tier_indices` in `CareerSaveData` and `CareerManager._apply_promotion_relegation()`; see `docs/PHASE_0_FIXES.md`)

## PHASE 5 — Polish

Audio, theming, and final presentation for the manager experience.

- [ ] Audio system
- [ ] Manager UI theme and custom fonts
- [ ] Real squad JSON database
