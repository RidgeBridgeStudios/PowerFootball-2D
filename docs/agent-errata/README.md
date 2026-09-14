# Agent Errata & Lessons Learned Index

**Navigation Rule for AI Agents:**  
DO NOT load all errata files into context. Identify the simulation layer or system you are modifying, consult this index, and read ONLY the corresponding topic page.

> [!WARNING]
> **Several pages below are historical.** The manager-only pivot retired the real-time match layer; its code now lives under `legacy/`. Pages marked **Historical** record findings about that archived engine — useful as reference when deepening `QuickSimEngine`, but they must **not** be applied to current code. Start with **[architecture-pivot.md](architecture-pivot.md)**.

---

## Topic Reference Pages

| Status | Topic Page | Layer / Subsystem | Key Covered Systems |
|---|---|---|---|
| **Current — read first** | **[architecture-pivot.md](architecture-pivot.md)** | All layers | Manager-only pivot record: what changed and why, `legacy/` archive layout and exclusions, the 3-layer stack, the 9-autoload boot order, and the surviving `GameManager` / `GameEvents` / `MatchStatsTracker` surfaces |
| **Current** | **[data-and-persistence.md](data-and-persistence.md)** | Layer 1 Career World | `CareerManager`, `PlayerData`, player aging decline curve calibration, season fixture calendar spacing rhythm |
| Historical — pre-pivot match layer | **[player-ai.md](player-ai.md)** | Archived Layer 2 Match AI | `PlayerBrain`, decision scoring baselines, loose-ball chase clamp deadlocks, Bresenham passing lane check, Sacchi force gating, defender marking, tackle gating |
| Historical — pre-pivot match layer | **[match-state.md](match-state.md)** | Archived match lifecycle | `GameManager` phase machine, match stage temporal fraction boundaries, possession hold timers, macro urgency saturation, manager risk profile derivation |
| Historical — pre-pivot match layer | **[physics-and-ball.md](physics-and-ball.md)** | Archived Layer 1 Physics | `Pseudo3DBall`, `DribbleState` magnet oscillation & dual-driver possession jitter, `AerialState` bicycle kick gating, `HeavyPlayerController` sprint jostle impulse & fatigue tiers |
| Historical — pre-pivot match layer | **[set-pieces.md](set-pieces.md)** | Archived Layer 1 / 2 | `SetPieceCoordinator`, kickoff low-composure backward pass veto & freeze, corner kick run triggers, throw-in CPU execution stalls, boundary legality rects |
| Historical — mostly pre-pivot | **[scene-and-node-paths.md](scene-and-node-paths.md)** | Cross-Module / Engine | Autoload contracts, `tools/lint_xref.py` enforcement, TackleState `MatchWorldModel` property crash, static cross-referencing latent crashes, non-ASCII identifier parser gotcha (the parser and cross-reference lessons are still current) |
| Historical — pre-pivot match layer | **[telemetry-and-stats.md](telemetry-and-stats.md)** | Archived match observability | `MatchWorldModel.debug_spacing_diagnostics`, crowding metrics, avoiding competing telemetry systems |
| Historical — pre-pivot match layer | **[ui-and-signals.md](ui-and-signals.md)** | Archived match presentation | `ball_struck` signal argument count mismatch, `TouchlineBubble` singleton instance repositioning, HUD substitution banner player lookup |
| Historical archive | **[session-history.md](session-history.md)** | Agent Handoffs | Archived session state logs (Antigravity & Claude) and Manager Career Mode session handoff notes |

---

## Complete Item Migration Manifest

> [!NOTE]
> This manifest is a **historical migration record**. Nearly every entry below concerns the archived real-time match layer (`PlayerBrain`, `MatchWorldModel`, `SetPieceCoordinator`, `HeavyPlayerController`, `Pseudo3DBall`, `HUD`); see the pivoted status column in the table above before following a link.

Every original entry from the former monolithic `AGENTS_ERRATA.md` has been mapped to exactly one topic page:

### Discovered Rules (24 Items)
| Original ID | Topic Page | Anchor Link |
|---|---|---|
| `press-trigger-needs-time-backstop` | `player-ai.md` | [Link](player-ai.md#press-trigger-needs-time-backstop) |
| `kickoff-backward-pass-veto-starves-taker` | `set-pieces.md` | [Link](set-pieces.md#kickoff-backward-pass-veto-starves-taker) |
| `loose-ball-anchor-clamp-deadlock` | `player-ai.md` | [Link](player-ai.md#loose-ball-anchor-clamp-deadlock) |
| `ball-struck-signal-arg-count-mismatch` | `ui-and-signals.md` | [Link](ui-and-signals.md#ball-struck-signal-arg-count-mismatch) |
| `maintain-formation-floor-freezes-ball-carrier` | `player-ai.md` | [Link](player-ai.md#maintain-formation-floor-freezes-ball-carrier) |
| `bresenham-threat-shadowed-real-lane-check-match-wide` | `player-ai.md` | [Link](player-ai.md#bresenham-threat-shadowed-real-lane-check-match-wide) |
| `loose-ball-max-dist-cap-also-needed-a-bypass` | `player-ai.md` | [Link](player-ai.md#loose-ball-max-dist-cap-also-needed-a-bypass) |
| `chase-radius-crushes-legal-loose-ball-chase-score` | `player-ai.md` | [Link](player-ai.md#chase-radius-crushes-legal-loose-ball-chase-score) |
| `arrive-radius-strands-correct-chase-decision` | `player-ai.md` | [Link](player-ai.md#arrive-radius-strands-correct-chase-decision) |
| `find-space-outscores-chase-on-loose-ball` | `player-ai.md` | [Link](player-ai.md#find-space-outscores-chase-on-loose-ball) |
| `dribble-magnet-forward-overshoot-oscillation` | `physics-and-ball.md` | [Link](physics-and-ball.md#dribble-magnet-forward-overshoot-oscillation) |
| `sacchi-force-cancels-urgent-ball-actions` | `player-ai.md` | [Link](player-ai.md#sacchi-force-cancels-urgent-ball-actions) |
| `possessor-can-chase-own-ball` | `player-ai.md` | [Link](player-ai.md#possessor-can-chase-own-ball) |
| `bicycle-kick-dominates-ambiguous-facing` | `physics-and-ball.md` | [Link](physics-and-ball.md#bicycle-kick-dominates-ambiguous-facing) |
| `manager-risk-profile-is-derived-not-authored` | `match-state.md` | [Link](match-state.md#manager-risk-profile-is-derived-not-authored) |
| `match-stage-boundaries-are-fractions-not-literal-seconds` | `match-state.md` | [Link](match-state.md#match-stage-boundaries-are-fractions-not-literal-seconds) |
| `touchline-bubble-is-one-shared-instance-home-perspective-only` | `ui-and-signals.md` | [Link](ui-and-signals.md#touchline-bubble-is-one-shared-instance-home-perspective-only) |
| `crowding-space-creation-diagnostics` | `telemetry-and-stats.md` | [Link](telemetry-and-stats.md#crowding-space-creation-diagnostics) |
| `verify-external-agent-prompts-against-source-before-executing` | `physics-and-ball.md` | [Link](physics-and-ball.md#verify-external-agent-prompts-against-source-before-executing) |
| `possession-hold-timer-has-two-non-interchangeable-variants` | `match-state.md` | [Link](match-state.md#possession-hold-timer-has-two-non-interchangeable-variants) |
| `defender-marking-was-uncoordinated-and-boundary-clamp-already-existed` | `player-ai.md` | [Link](player-ai.md#defender-marking-was-uncoordinated-and-boundary-clamp-already-existed) |
| `stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate` | `match-state.md` | [Link](match-state.md#stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate) |
| `dribble-claim-ignores-existing-possessor-dual-driver-jitter` | `physics-and-ball.md` | [Link](physics-and-ball.md#dribble-claim-ignores-existing-possessor-dual-driver-jitter) |
| `cpu-players-never-gated-into-tackle-state` | `player-ai.md` | [Link](player-ai.md#cpu-players-never-gated-into-tackle-state) |

### Error Logs (7 Items)
| Original ID | Topic Page | Anchor Link |
|---|---|---|
| `ERR-20260830-01` | `player-ai.md` | [Link](player-ai.md#err-20260830-01) |
| `ERR-20260830-02` | `ui-and-signals.md` | [Link](ui-and-signals.md#err-20260830-02) |
| `ERR-20260831-01` | `set-pieces.md` | [Link](set-pieces.md#err-20260831-01) |
| `ERR-20260831-02` | `set-pieces.md` | [Link](set-pieces.md#err-20260831-02) |
| `ERR-20260831-03` | `set-pieces.md` | [Link](set-pieces.md#err-20260831-03) |
| `ERR-20260901-01` | `scene-and-node-paths.md` | [Link](scene-and-node-paths.md#err-20260901-01) |
| `throw-in-ball-outside-chase-legality-rect` | `set-pieces.md` | [Link](set-pieces.md#throw-in-ball-outside-chase-legality-rect) |

### Narrative Subsections (4 Items)
| Original Section Heading | Topic Page | Anchor Link |
|---|---|---|
| `Three latent runtime crashes found by static cross-referencing` | `scene-and-node-paths.md` | [Link](scene-and-node-paths.md#three-latent-runtime-crashes-found-by-static-cross-referencing) |
| `Non-ASCII identifiers parse here but not in Godot` | `scene-and-node-paths.md` | [Link](scene-and-node-paths.md#non-ascii-identifiers-parse-here-but-not-in-godot) |
| `Calibration is not optional, and the first guess was wrong twice` | `data-and-persistence.md` | [Link](data-and-persistence.md#calibration-is-not-optional-and-the-first-guess-was-wrong-twice) |
| `The season calendar cannot be a fixed weekly rhythm` | `data-and-persistence.md` | [Link](data-and-persistence.md#the-season-calendar-cannot-be-a-fixed-weekly-rhythm) |

### Session Handoff States
| Original Section Heading | Topic Page | Anchor Link |
|---|---|---|
| `## Session State` (YAML blocks) | `session-history.md` | [Link](session-history.md#recent-session-state-archive) |
| `## Session State: 2026-09-02 (Manager Career Mode, Phase 4)` | `session-history.md` | [Link](session-history.md#session-state-2026-09-02-manager-career-mode-phase-4) |

---

## Ambiguous Entries Report
The following entries bridge multiple architectural domains:
1. **`verify-external-agent-prompts-against-source-before-executing`**:
   - *Scope:* Development / prompt verification process vs. `HeavyPlayerController` fatigue tiers (`FatigueTier`) and kinematic sprint jostle impulse (`_resolve_sprint_jostle`).
   - *Assigned To:* `physics-and-ball.md` because its concrete code contract governs Layer 1 player kinematics and collision resolution.
2. **`kickoff-backward-pass-veto-starves-taker`**:
   - *Scope:* Player AI passing veto (`PlayerBrain`) vs. Kickoff set-piece restart mechanics (`SetPieceCoordinator`).
   - *Assigned To:* `set-pieces.md` because it resolves the match-freezing dead-ball kickoff failure mode.
3. **`crowding-space-creation-diagnostics`**:
   - *Scope:* Spatial navigation metrics vs. Telemetry and diagnostic logging instrumentation.
   - *Assigned To:* `telemetry-and-stats.md` to establish the architectural boundary against duplicate diagnostic logging systems.
4. **`manager-risk-profile-is-derived-not-authored`**:
   - *Scope:* Layer 4 `ManagerData` JSON schema vs. Layer 2 in-match macro urgency calculations.
   - *Assigned To:* `match-state.md` because its mathematical formula dictates dynamic match urgency scaling.
5. **`possession-hold-timer-has-two-non-interchangeable-variants`**:
   - *Scope:* Match-wide possession tracking in `MatchWorldModel` vs. individual carrier pressing triggers in `PlayerBrain`.
   - *Assigned To:* `match-state.md` because it defines the dual possession timer invariants.
6. **`cpu-players-never-gated-into-tackle-state`**:
   - *Scope:* AI decision engine wanting tackles vs. `HeavyPlayerController` intent inputs and `PlayerState` transitions.
   - *Assigned To:* `player-ai.md` because it establishes the tactical AI intent wiring (`wants_tackle`) into the decision loop.
