# ui/ — HUD, Menus, & User Feedback

User interface screens, HUD overlays, match statistics, and menu systems.

## Architecture Overview

```
MainMenu.tscn (entry point)
  ├─ KickOffMenu (team selection)
  ├─ OptionsMenu (settings)
  └─ Quit
  
PitchScene.tscn (match)
  ├─ HUD (in-match UI)
  │   ├─ ActionText (floating PASS/SHOT/TACKLE labels)
  │   ├─ TouchlineBubble (manager animated quotes)
  │   ├─ Minimap (top-down position radar)
  │   └─ SubstitutionBanner & Referee Banners
  │
  ├─ PauseMenu (ESC / UI pause)
  │   ├─ Tactical formation adjustments
  │   └─ Bench substitution UI (max 3 substitutions)
  │
  ├─ PreGameScreen (pre-match)
  │   ├─ Starting XI & reserve bench lineup editor
  │   ├─ FormationDiagram preview
  │   └─ Team tactics setup
  │
  ├─ MatchStatsUI (full-time screen)
  │   ├─ Final score and team statistics
  │   └─ Per-player 1.0–10.0 performance ratings
  │
  └─ MatchCamera (cinematic + ball-follow modes)
```

## Key Scenes

### MainMenu.tscn

**Responsibilities:**
- Display menu options (Kick Off, Practice, Career, Options, Quit)
- Route to KickOffMenu for 8-team league match setup
- Launch PitchScene with selected parameters via `GameManager` meta

---

### PauseMenu.tscn

**Responsibilities:**
- Display pause overlay
- Allow live formation changes mid-match
- Execute in-match player substitutions (up to 3 per match) via `TeamManagementData`
- Resume, restart match, or return to main menu

**Signals:**
- Emits `GameEvents.substitution_made(team, out_idx, in_idx)`
- Emits `GameEvents.formation_changed(team, name)`

---

### PreGameScreen.tscn

**Responsibilities:**
- Display starting XI and reserve bench
- Allow lineup swapping and bench assignments before kickoff
- Display formation preview with `FormationDiagram.gd`
- Confirm readiness via `GameEvents.pregame_confirmed`

---

### MatchStatsUI.tscn

**Responsibilities:**
- Displayed upon `GameEvents.match_ended` at FULL_TIME
- Shows final score, team possession percentages, total shots, shots on target, passes (completed/attempted), fouls, corners, offsides, and cards
- Displays per-player match performance ratings (1.0–10.0) computed by `PlayerRatingCalculator.gd`
- Provides button to return to Main Menu

---

### HUD.gd (MatchHUD)

**Responsibilities:**
- Render minimap with team-colored dots and ball tracking
- Display floating action text (PASS, SHOT, LOB, TACKLE, SAVE, REBOUND)
- Display match clock, score, current phase banner, and referee event alerts
- Render stamina bar and facing arrow for user-controlled player

---

### TouchlineBubble.gd

**Responsibilities:**
- Spawns animated speech bubbles for manager reactions to key events (goals, missed chances, yellow/red cards, foul disputes).

---

## HUD Rendering Contract

All HUD updates route through signal connections:

**From GameEvents:**
- `player_switched(new_player)` — Update active controlled player highlight
- `ball_struck(player, speed, charge_ratio, is_shot)` — Spawn ActionText
- `goal_scored(team, scorer)` — Highlight scorer, update score
- `match_phase_changed(phase)` — Update clock/phase display
- `yellow_card_shown` / `red_card_shown` — Display card presentation overlays
- `offside_called` — Display offside decision banner
- `substitution_made` — Display player swap overlay

**From MatchWorldModel:**
- Polls `player_positions[i]` every frame for minimap
- Polls `ball_position` and `ball_position_z` for ball radar

**DO NOT:**
- Query scene tree for player positions; use MatchWorldModel
- Direct node manipulation; use signals
- Cache player references; query MatchWorldModel every frame

---

## Themes & Styling (Phase 5)

Currently uses custom Godot theme styling with clean flat arcade visuals.

**Planned (Phase 5):**
- Additional custom font stack
- Extended team-aware stadium cosmetics
- Audio soundscape integration

---

## Camera Systems (MatchCamera.gd)

Three modes selectable by player:
1. **BALL_FOLLOW** — Camera centered on ball with dynamic zoom
2. **DYNAMIC** — Weighted blend between ball and controlled player
3. **FULL_FIELD** — Static view covering entire pitch

---

## Notes

- All UI updates are passive (listen to GameEvents; never mutate physics state directly).
- Minimap is the primary spatial feedback for off-screen players.
- Stamina display reads `HeavyPlayerController.stamina` and `stamina_state_changed` signal.
- Formation UI is independent of tactical AI (UI shows preview; ManagerDirector applies to brains).

