# ui/ — HUD, Menus, & User Feedback

User interface screens, HUD overlays, and menu systems.

## Architecture Overview

```
MainMenu.tscn (entry point)
  ├─ KickOffMenu (team selection)
  ├─ OptionsMenu (settings)
  └─ Quit
  
PitchScene.tscn (match)
  ├─ HUD (in-match UI)
  │   ├─ ActionText (floating PASS/SHOT labels)
  │   ├─ Nameplate (player info panels)
  │   └─ Minimap (top-down position tracker)
  │
  ├─ PauseMenu (ESC key)
  │   └─ Formation adjustment UI
  │
  ├─ PreGameScreen (pre-match)
  │   ├─ Lineup order editor
  │   └─ Formation preview
  │
  └─ MatchCamera (cinematic + ball-follow modes)
```

## Key Scenes

### MainMenu.tscn

**Responsibilities:**
- Display menu options (Kick Off, Practice, Career, Options, Quit)
- Route to KickOffMenu on selection
- Load game options
- Launch PitchScene with selected parameters

---

### PauseMenu.tscn

**Responsibilities:**
- Display pause overlay
- Allow formation changes mid-match
- Resume, forfeit, or return to main menu

**Signals:**
- Emits `GameEvents.formation_changed(team, name)` on selection change
- Note: This is distinct from `manager_formation_changed` (emitted by ManagerDirector)

---

### PreGameScreen.tscn

**Responsibilities:**
- Show team lineup
- Allow lineup order adjustment via `TeamData.lineup_indices`
- Display formation preview with player anchors
- Set ready-state before match starts

**Current State:**
- Implemented for phase 1 match start
- Lineup order editing ready (reserves system is Phase 1 feature)

---

### HUD.gd (MatchHUD)

**Responsibilities:**
- Render player nameplates (shirt number, stamina, mood indicator)
- Render minimap with team-colored dots
- Display action text (floating PASS/SHOT/LOB SHOT labels)
- Show match clock, score, phase
- Render stamina bar for controlled player

**Subsystems:**

**ActionText.gd**
- Spawns floating labels on ball strikes
- Fades and despawns after delay
- Used for visual feedback on actions

**Nameplate.gd** (per player)
- Shows player shirt number and name
- Stamina indicator (bar or icon)
- Current mood state (SLUMP/NORMAL/STREAK)
- Highlights controlled player

**Minimap.gd**
- Top-down render of pitch with player positions
- Home team = one color; away = another
- GK marked distinctly from outfield
- Ball position indicator
- Updates from MatchWorldModel positions

---

## HUD Rendering Contract

All HUD updates route through signal connections:

**From GameEvents:**
- `player_switched(team, old_index, new_index)` — Update controlled player highlight
- `ball_struck(kicker, impulse_xy, impulse_z)` — Spawn ActionText
- `goal_scored(team, scorer)` — Highlight scorer, update score
- `match_phase_changed(phase)` — Update clock/phase display
- `foul_committed(offender, victim, type)` — Possible card display

**From MatchWorldModel:**
- Polls `player_positions[i]` every frame for minimap
- Polls `ball_node.global_position` and `ball_node.z` for ball render

**DO NOT:**
- Query scene tree for player positions; use MatchWorldModel
- Direct node manipulation; use signals
- Cache player references; query MatchWorldModel every frame

---

## Themes & Styling (Phase 5)

Currently uses Godot default fonts and colors.

**Planned (Phase 5):**
- Custom font stack
- Team-aware color schemes
- Mood-state visual indicators (color/opacity changes)
- Injury/substitution reserve panel
- Match stats panel (end-of-match scoreboard)

---

## Camera Systems (MatchCamera.gd)

Three modes selected by player:

1. **BALL_FOLLOW** — Camera centered on ball; dynamic zoom
2. **DYNAMIC** — Weighted toward ball but includes controlled player
3. **FULL_FIELD** — Shows entire pitch; loses detail

See **entities/ball/README.md** for integration with ball prediction (aim arc visualization).

---

## Notes

- All UI updates are passive (listen to GameEvents; never emit directly)
- Minimap is the primary spatial feedback for off-screen players
- Nameplate stamina is a direct read of `HeavyPlayerController.current_stamina`
- Formation UI is independent of tactical AI (UI shows preview; ManagerDirector applies to brain)
