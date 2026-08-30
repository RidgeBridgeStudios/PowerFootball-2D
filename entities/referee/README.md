# entities/referee/ — Match Rules, Officiating Crew & Personality

Referee personality-weighted foul decisions, match rule enforcement, and fully animated on-pitch match officiating crew.

## Architecture Overview

```
RefereeLoader (autoload)
  └─ Loads referee JSON → RefereeData pool
  
MatchReferee (logical match arbiter)
  ├─ Listens to GameEvents.foul_committed
  ├─ Evaluates award based on RefereeData personality & match temperature
  ├─ Routes to SetPieceCoordinator for dead-ball setup
  ├─ Evaluates disciplinary action (yellow / red cards)
  └─ Emits signals to GameEvents bus

OffsideDetector (rule detector)
  ├─ Listens to GameEvents.ball_struck during IN_PLAY
  ├─ Computes 2nd-to-last defender offside line via MatchWorldModel
  └─ Emits GameEvents.offside_called

MatchOfficialCrew (visual officiating crew coordinator)
  ├─ CenterRefereeVisual
  │    ├─ Follows Diagonal System of Control (DSC)
  │    ├─ Avoids player congestion via MatchWorldModel spatial queries
  │    ├─ Rushes to incident / foul spots
  │    └─ Animated card presentation with visual flares (Yellow & Red)
  ├─ AssistantRefereeVisual (x2: AR1 Top, AR2 Bottom)
  │    ├─ Patrols touchlines and mirrors 2nd-to-last defender line
  │    ├─ Flag signals: Offside (vertical flutter), Throw-in (45° angle), Corner, Goal Kick
  │    └─ Inward facing orientation
  ├─ FourthOfficialVisual
  │    ├─ Stationed in technical area near halfway line
  │    └─ Raises dual-LED substitution board (Red Out / Green In) on substitutions
  └─ WhistleSynthesizer
       ├─ Procedural 16-bit PCM AudioStreamWAV dual-tone FM synthesis (zero asset files)
       ├─ Patterns: Short, Hard, Double (Half-Time), Triple (Full-Time), Kickoff
       └─ Animated visual expanding acoustic rings / shockwaves
```

---

## Component Details

### 1. MatchReferee.gd
- **Contract:** Match-time arbiter. Personality-weighted foul decisions.
- **Key Fields:** `strictness`, `consistency`, `composure`, `unprofessionalism`, `incoherence`, `reputation`.
- **Match Temperature:** Rises with goal differentials, match elapsed time, and streak moods, driving threshold drift.

### 2. MatchOfficialCrew.gd
- **Contract:** Manages and coordinates the 4 visual match officials on the pitch.
- Pure visual/kinematic `Node2D` entities: **Zero collision shapes on Layer 2 (PlayerBodies) and Layer 3 (BallPhysicsBody)**.
- Subscribes to `GameEvents` signals to trigger coordinated responses, gestures, flag signaling, and whistle audio cues.

### 3. CenterRefereeVisual.gd
- **Diagonal System of Control (DSC):** Maintains optimal observation angle (~140–240px from the ball) along the diagonal corridor (quadrant II to IV), keeping play between referee and the active assistant referee.
- **Card Presentation:** Sprints to the offending player, draws and raises card high with glowing aura and starburst visual flare for 2.8 seconds.
- **High-Vis Kit:** Neon jersey with black shorts and referee chest badge.

### 4. AssistantRefereeVisual.gd (Linesmen AR1 & AR2)
- **Touchline Patrol:** AR1 covers Top touchline ($x \ge 0$), AR2 covers Bottom touchline ($x \le 0$).
- **Offside Tracking:** Dynamically tracks the 2nd-to-last defender or ball position to stay aligned with the offside line.
- **Flag Signals:** Checkered yellow-and-red flag with animated flutter for offside calls and directional indicators for throw-ins, corner kicks, and goal kicks.

### 5. FourthOfficialVisual.gd
- **Technical Area Station:** Located outside the touchline near the center line.
- **Electronic Sub Board:** Displays red LED number for player exiting and green LED number for player entering upon `GameEvents.substitution_made`.

### 6. WhistleSynthesizer.gd
- **Procedural FM Audio:** Dual-tone frequency synthesis ($f_1 \approx 2850\text{ Hz}$, $f_2 \approx 3200\text{ Hz}$, $f_{\text{trill}} \approx 32\text{ Hz}$) generated in GDScript as uncompressed 16-bit PCM `AudioStreamWAV` buffers.
- **Visual Wave Rings:** Emits expanding acoustic shockwaves at the whistle origin.

---

## Minimap Integration
- **Center Referee:** High-vis yellow dot with black border and "R" marker.
- **Linesmen:** Touchline diamond/square markers along top/bottom boundaries.
- **4th Official:** Neutral marker in technical area.
