# ROADMAP.md

Canonical feature checklist for PowerFootball-2D. Each phase should produce a meaningful, playable improvement before moving to the next. See @./POWERFOOTBALL_MASTER_VISION.md for design rationale, deep systems, and architectural context.

## PHASE 1 — Gameplay Completeness

Core football mechanics that must work before anything else.

- [x] Substitutions + reserves UI
- [x] Yellow/red card implementation
- [x] Offside detection
- [ ] Injury system
- [x] Match stats screen + full-time scoreboard
- [x] End-of-match player ratings
- [x] Goalkeeper dive commitment
- [ ] AerialState / heading resolution
- [x] Penalty shootout flow
- [ ] Through-ball lead targeting
- [x] Phase-dependent dynamic formation anchors (ball-zone + possession phase)

## PHASE 2 — Personality and Traits

Make players feel like individuals with relationships and hidden depth.

- [ ] Player trait bitmask on PlayerData
- [ ] Trait effects wired into existing systems
- [ ] overall_rating and reputation derived fields
- [ ] Star-marking utility scorer
- [x] Relationship trust graph (`RelationshipData`, seeded into TrustSystem at kickoff)
- [x] Trust multiplier on pass utility
- [x] Trust decay/gain events

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
- [ ] Promotion/relegation across multiple divisions (needs a multi-tier league)

## PHASE 5 — Polish

Audio, animation, themes, and final presentation.

- [ ] Audio system
- [ ] Sprite and action animation
- [ ] HUD theme and custom fonts
- [ ] Local 2-player support
- [ ] Real squad JSON database
