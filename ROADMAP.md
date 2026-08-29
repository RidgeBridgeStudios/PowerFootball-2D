# ROADMAP.md

Canonical feature checklist for PowerFootball-2D. Each phase should produce a meaningful, playable improvement before moving to the next. See @./POWERFOOTBALL_MASTER_VISION.md for design rationale, deep systems, and architectural context.

## PHASE 1 — Gameplay Completeness

Core football mechanics that must work before anything else.

- [ ] Substitutions + reserves UI
- [ ] Yellow/red card implementation
- [ ] Offside detection
- [ ] Injury system
- [ ] Match stats screen + full-time scoreboard
- [ ] End-of-match player ratings
- [ ] Goalkeeper dive commitment
- [ ] AerialState / heading resolution
- [ ] Penalty shootout flow
- [ ] Through-ball lead targeting

## PHASE 2 — Personality and Traits

Make players feel like individuals with relationships and hidden depth.

- [ ] Player trait bitmask on PlayerData
- [ ] Trait effects wired into existing systems
- [ ] overall_rating and reputation derived fields
- [ ] Star-marking utility scorer
- [ ] Relationship trust graph
- [ ] Trust multiplier on pass utility
- [ ] Trust decay/gain events

## PHASE 3 — Club World

Bridge between match events and player life between matches.

- [ ] WorldEvent struct and WorldEventLog autoload
- [ ] Substitution reaction events
- [ ] Training incidents and dressing-room confrontations
- [ ] Street football / nightlife / media events
- [ ] PressOffice consumption of WorldEvent log
- [ ] Manager response system

## PHASE 4 — Career Mode

Multi-match progression with persistence, transfers, and season structure.

- [ ] Career calendar and scheduling
- [ ] League table persistence
- [ ] Transfer window system
- [ ] Season progression and contracts
- [ ] Staff system
- [ ] Manager Career mode unlock

## PHASE 5 — Polish

Audio, animation, themes, and final presentation.

- [ ] Audio system
- [ ] Sprite and action animation
- [ ] HUD theme and custom fonts
- [ ] Local 2-player support
- [ ] Real squad JSON database
