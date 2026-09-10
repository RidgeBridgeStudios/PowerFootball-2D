# AGENTS_ERRATA.md — Migration Index & Errata Hub

> [!NOTE]
> **Errata Modularization Notice:**
> The errata catalog has been modularized into topic-specific reference pages under `docs/agent-errata/`.
> Agents should **NOT** load this file in full or search across all errata. Instead, consult the topic page for the specific simulation layer or subsystem you are editing.
> See **[docs/agent-errata/README.md](docs/agent-errata/README.md)** for the complete reading guide and search protocols.

---

## Topic Reference Pages

| Subsystem / Layer | Reference Page | Key Content |
|---|---|---|
| **Layer 2 Match AI** | **[docs/agent-errata/player-ai.md](docs/agent-errata/player-ai.md)** | `PlayerBrain` decision scoring baselines, loose-ball chase clamp deadlocks, Bresenham passing lane check, Sacchi force gating, defender marking, CPU tackle gating |
| **Layer 2 / Layer 5 Match Lifecycle** | **[docs/agent-errata/match-state.md](docs/agent-errata/match-state.md)** | `GameManager` match stage temporal fraction boundaries, possession hold timers, macro urgency saturation, manager risk profile derivation |
| **Layer 1 Physics & Kinematics** | **[docs/agent-errata/physics-and-ball.md](docs/agent-errata/physics-and-ball.md)** | `Pseudo3DBall`, `DribbleState` magnet oscillation & dual-driver possession jitter, `AerialState` bicycle kick gating, `HeavyPlayerController` sprint jostle impulse & fatigue tiers |
| **Layer 1 / Layer 2 Set Pieces** | **[docs/agent-errata/set-pieces.md](docs/agent-errata/set-pieces.md)** | `SetPieceCoordinator`, kickoff low-composure backward pass veto & freeze, corner kick run triggers, throw-in CPU execution stalls, boundary legality rects |
| **Cross-Module & Engine Architecture** | **[docs/agent-errata/scene-and-node-paths.md](docs/agent-errata/scene-and-node-paths.md)** | Autoload contracts, `tools/lint_xref.py` enforcement, TackleState MatchWorldModel property crash, static cross-referencing latent crashes, non-ASCII identifier parser gotcha |
| **Layer 4 Club World & Persistence** | **[docs/agent-errata/data-and-persistence.md](docs/agent-errata/data-and-persistence.md)** | `CareerManager`, `PlayerData`, player aging decline curve calibration, morale-to-mood seeding slopes, season fixture calendar spacing rhythm |
| **Layer 2 / Layer 3 Observability** | **[docs/agent-errata/telemetry-and-stats.md](docs/agent-errata/telemetry-and-stats.md)** | `MatchWorldModel.debug_spacing_diagnostics`, crowding metrics, avoiding competing telemetry systems |
| **Layer 5 Presentation & UI** | **[docs/agent-errata/ui-and-signals.md](docs/agent-errata/ui-and-signals.md)** | `ball_struck` signal argument count mismatch, `TouchlineBubble` singleton instance repositioning, HUD substitution banner player lookup |
| **Session Handoffs & History** | **[docs/agent-errata/session-history.md](docs/agent-errata/session-history.md)** | Archived session state logs (Antigravity & Claude) and Manager Career Mode session handoff notes |

---

## Migration Manifest & Stable Redirects

All entries originally housed in this file have been migrated to their canonical topic pages:

### Discovered Rules
- `press-trigger-needs-time-backstop` → [docs/agent-errata/player-ai.md#press-trigger-needs-time-backstop](docs/agent-errata/player-ai.md#press-trigger-needs-time-backstop)
- `kickoff-backward-pass-veto-starves-taker` → [docs/agent-errata/set-pieces.md#kickoff-backward-pass-veto-starves-taker](docs/agent-errata/set-pieces.md#kickoff-backward-pass-veto-starves-taker)
- `loose-ball-anchor-clamp-deadlock` → [docs/agent-errata/player-ai.md#loose-ball-anchor-clamp-deadlock](docs/agent-errata/player-ai.md#loose-ball-anchor-clamp-deadlock)
- `ball-struck-signal-arg-count-mismatch` → [docs/agent-errata/ui-and-signals.md#ball-struck-signal-arg-count-mismatch](docs/agent-errata/ui-and-signals.md#ball-struck-signal-arg-count-mismatch)
- `maintain-formation-floor-freezes-ball-carrier` → [docs/agent-errata/player-ai.md#maintain-formation-floor-freezes-ball-carrier](docs/agent-errata/player-ai.md#maintain-formation-floor-freezes-ball-carrier)
- `bresenham-threat-shadowed-real-lane-check-match-wide` → [docs/agent-errata/player-ai.md#bresenham-threat-shadowed-real-lane-check-match-wide](docs/agent-errata/player-ai.md#bresenham-threat-shadowed-real-lane-check-match-wide)
- `loose-ball-max-dist-cap-also-needed-a-bypass` → [docs/agent-errata/player-ai.md#loose-ball-max-dist-cap-also-needed-a-bypass](docs/agent-errata/player-ai.md#loose-ball-max-dist-cap-also-needed-a-bypass)
- `chase-radius-crushes-legal-loose-ball-chase-score` → [docs/agent-errata/player-ai.md#chase-radius-crushes-legal-loose-ball-chase-score](docs/agent-errata/player-ai.md#chase-radius-crushes-legal-loose-ball-chase-score)
- `arrive-radius-strands-correct-chase-decision` → [docs/agent-errata/player-ai.md#arrive-radius-strands-correct-chase-decision](docs/agent-errata/player-ai.md#arrive-radius-strands-correct-chase-decision)
- `find-space-outscores-chase-on-loose-ball` → [docs/agent-errata/player-ai.md#find-space-outscores-chase-on-loose-ball](docs/agent-errata/player-ai.md#find-space-outscores-chase-on-loose-ball)
- `dribble-magnet-forward-overshoot-oscillation` → [docs/agent-errata/physics-and-ball.md#dribble-magnet-forward-overshoot-oscillation](docs/agent-errata/physics-and-ball.md#dribble-magnet-forward-overshoot-oscillation)
- `sacchi-force-cancels-urgent-ball-actions` → [docs/agent-errata/player-ai.md#sacchi-force-cancels-urgent-ball-actions](docs/agent-errata/player-ai.md#sacchi-force-cancels-urgent-ball-actions)
- `possessor-can-chase-own-ball` → [docs/agent-errata/player-ai.md#possessor-can-chase-own-ball](docs/agent-errata/player-ai.md#possessor-can-chase-own-ball)
- `bicycle-kick-dominates-ambiguous-facing` → [docs/agent-errata/physics-and-ball.md#bicycle-kick-dominates-ambiguous-facing](docs/agent-errata/physics-and-ball.md#bicycle-kick-dominates-ambiguous-facing)
- `manager-risk-profile-is-derived-not-authored` → [docs/agent-errata/match-state.md#manager-risk-profile-is-derived-not-authored](docs/agent-errata/match-state.md#manager-risk-profile-is-derived-not-authored)
- `match-stage-boundaries-are-fractions-not-literal-seconds` → [docs/agent-errata/match-state.md#match-stage-boundaries-are-fractions-not-literal-seconds](docs/agent-errata/match-state.md#match-stage-boundaries-are-fractions-not-literal-seconds)
- `touchline-bubble-is-one-shared-instance-home-perspective-only` → [docs/agent-errata/ui-and-signals.md#touchline-bubble-is-one-shared-instance-home-perspective-only](docs/agent-errata/ui-and-signals.md#touchline-bubble-is-one-shared-instance-home-perspective-only)
- `crowding-space-creation-diagnostics` → [docs/agent-errata/telemetry-and-stats.md#crowding-space-creation-diagnostics](docs/agent-errata/telemetry-and-stats.md#crowding-space-creation-diagnostics)
- `verify-external-agent-prompts-against-source-before-executing` → [docs/agent-errata/physics-and-ball.md#verify-external-agent-prompts-against-source-before-executing](docs/agent-errata/physics-and-ball.md#verify-external-agent-prompts-against-source-before-executing)
- `possession-hold-timer-has-two-non-interchangeable-variants` → [docs/agent-errata/match-state.md#possession-hold-timer-has-two-non-interchangeable-variants](docs/agent-errata/match-state.md#possession-hold-timer-has-two-non-interchangeable-variants)
- `defender-marking-was-uncoordinated-and-boundary-clamp-already-existed` → [docs/agent-errata/player-ai.md#defender-marking-was-uncoordinated-and-boundary-clamp-already-existed](docs/agent-errata/player-ai.md#defender-marking-was-uncoordinated-and-boundary-clamp-already-existed)
- `stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate` → [docs/agent-errata/match-state.md#stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate](docs/agent-errata/match-state.md#stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate)
- `dribble-claim-ignores-existing-possessor-dual-driver-jitter` → [docs/agent-errata/physics-and-ball.md#dribble-claim-ignores-existing-possessor-dual-driver-jitter](docs/agent-errata/physics-and-ball.md#dribble-claim-ignores-existing-possessor-dual-driver-jitter)
- `cpu-players-never-gated-into-tackle-state` → [docs/agent-errata/player-ai.md#cpu-players-never-gated-into-tackle-state](docs/agent-errata/player-ai.md#cpu-players-never-gated-into-tackle-state)
- `eval-simulation-harness-was-decoupled-from-gdscript-tuning` → [docs/agent-errata/physics-and-ball.md#eval-simulation-harness-was-decoupled-from-gdscript-tuning](docs/agent-errata/physics-and-ball.md#eval-simulation-harness-was-decoupled-from-gdscript-tuning)
- `pass-strike-speed-was-flat-while-pass-selection-was-distance-scored` → [docs/agent-errata/player-ai.md#pass-strike-speed-was-flat-while-pass-selection-was-distance-scored](docs/agent-errata/player-ai.md#pass-strike-speed-was-flat-while-pass-selection-was-distance-scored)
- `role-config-is-null-in-live-matches-so-role-space-alpha-is-what-runs` → [docs/agent-errata/player-ai.md#role-config-is-null-in-live-matches-so-role-space-alpha-is-what-runs](docs/agent-errata/player-ai.md#role-config-is-null-in-live-matches-so-role-space-alpha-is-what-runs)
- `eval-harness-index-phase-and-claim-gate-were-structural-artifacts` → [docs/agent-errata/physics-and-ball.md#eval-harness-index-phase-and-claim-gate-were-structural-artifacts](docs/agent-errata/physics-and-ball.md#eval-harness-index-phase-and-claim-gate-were-structural-artifacts)

### Error Logs
- `ERR-20260830-01` → [docs/agent-errata/player-ai.md#err-20260830-01](docs/agent-errata/player-ai.md#err-20260830-01)
- `ERR-20260830-02` → [docs/agent-errata/ui-and-signals.md#err-20260830-02](docs/agent-errata/ui-and-signals.md#err-20260830-02)
- `ERR-20260831-01` → [docs/agent-errata/set-pieces.md#err-20260831-01](docs/agent-errata/set-pieces.md#err-20260831-01)
- `ERR-20260831-02` → [docs/agent-errata/set-pieces.md#err-20260831-02](docs/agent-errata/set-pieces.md#err-20260831-02)
- `ERR-20260831-03` → [docs/agent-errata/set-pieces.md#err-20260831-03](docs/agent-errata/set-pieces.md#err-20260831-03)
- `ERR-20260901-01` → [docs/agent-errata/scene-and-node-paths.md#err-20260901-01](docs/agent-errata/scene-and-node-paths.md#err-20260901-01)
- `throw-in-ball-outside-chase-legality-rect` → [docs/agent-errata/set-pieces.md#throw-in-ball-outside-chase-legality-rect](docs/agent-errata/set-pieces.md#throw-in-ball-outside-chase-legality-rect)

### Narrative Subsections
- `Three latent runtime crashes found by static cross-referencing` → [docs/agent-errata/scene-and-node-paths.md#three-latent-runtime-crashes-found-by-static-cross-referencing](docs/agent-errata/scene-and-node-paths.md#three-latent-runtime-crashes-found-by-static-cross-referencing)
- `Non-ASCII identifiers parse here but not in Godot` → [docs/agent-errata/scene-and-node-paths.md#non-ascii-identifiers-parse-here-but-not-in-godot](docs/agent-errata/scene-and-node-paths.md#non-ascii-identifiers-parse-here-but-not-in-godot)
- `Calibration is not optional, and the first guess was wrong twice` → [docs/agent-errata/data-and-persistence.md#calibration-is-not-optional-and-the-first-guess-was-wrong-twice](docs/agent-errata/data-and-persistence.md#calibration-is-not-optional-and-the-first-guess-was-wrong-twice)
- `The season calendar cannot be a fixed weekly rhythm` → [docs/agent-errata/data-and-persistence.md#the-season-calendar-cannot-be-a-fixed-weekly-rhythm](docs/agent-errata/data-and-persistence.md#the-season-calendar-cannot-be-a-fixed-weekly-rhythm)

### Session State
- `## Session State` → [docs/agent-errata/session-history.md#recent-session-state-archive](docs/agent-errata/session-history.md#recent-session-state-archive)
- `## Session State: 2026-09-02 (Manager Career Mode, Phase 4)` → [docs/agent-errata/session-history.md#session-state-2026-09-02-manager-career-mode-phase-4](docs/agent-errata/session-history.md#session-state-2026-09-02-manager-career-mode-phase-4)

---

## Discovered Rules

```yaml
# Schema:
# discovered_rules:
#   - id: string (kebab-case identifier)
#     discovered_date: YYYY-MM-DD
#     discovered_by: string (model/agent identifier)
#     category: engine | physics | ai | social | data | architecture
#     target_files:
#       - string (file path)
#     invariant: string (the rule or negative constraint)
#     rationale: string (why the rule exists)
#     promotion_target: string (path to rulebook destination)
#     status: pending | promoted

discovered_rules: []
```

---

## Session State

```yaml
# Schema for recording session handoff state:
# session_state:
#   date: YYYY-MM-DD
#   agent: string
#   task: string
#   files_modified:
#     - string
#   gdcheck_status: pass | fail (error count)
#   invariants_consulted:
#     - string
#   next_steps: string
#   new_rules_discovered: []

session_state: []
```
