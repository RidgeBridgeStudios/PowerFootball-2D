# SOCIAL_SIMULATION_ARCHITECTURE.md

**Technical & Game Design Specification — Psychological Traits, Social Memory, and Star Gravity**

Companion to [POWERFOOTBALL_MASTER_VISION.md](../POWERFOOTBALL_MASTER_VISION.md) Part V (Deep Systems Design). Where the vision document sketches these systems in a paragraph each, this document is the buildable specification: exact data contracts, exact choke points, exact formulas, and the sequencing that lets Phase 2/3 land without state coupling or hot-path regressions.

Status of this document: **design, not yet implemented**, except where a section is explicitly marked `[EXISTS]`. §§1.2–1.3's Layer 3/4 (club-world) trait levers have since largely shipped — see the §0 table for what is now live; the Layer 2 (match-AI) levers, §2's expanded trust-write events, and §4's star gravity remain unbuilt. Read [CORE_INVARIANTS.md](CORE_INVARIANTS.md) and `.claude/rules/ai-architect.md` before touching any file named here — every new hook below is designed to slot into an existing choke point rather than add a new one.

---

## 0. Ground Truth — What Already Exists vs. What This Document Adds

`ROADMAP.md` Phase 2 now reflects the shipped state of the trait bitmask, `overall_rating`, and `reputation`. The actual state, verified against source on 2026-09-08 and revised after the PES-growth-archetype/trait-wiring merge:

| Component | File | State |
|---|---|---|
| Player trait bitmask (13 flags) | `shared/PlayerData.gd:75-89` | **`[EXISTS]` and partly wired** — 11 of 13 traits now have live Layer 3/4 consumers (`MoraleEngine`, `PlayerDevelopmentEngine`, `TrainingSchedule`, `ScoutingNetwork`, `MatchReferee`, `InboxEngine`, `CareerManager`, `ManagerDirector`, `PressOffice`). `DeepRunner` and `WallSplitter` are still unwritten — both are Layer 2 match-AI levers (§1.2) needing `PlayerBrain` changes. **Every Layer 2 column entry in §1.2 below remains unbuilt.** |
| `player_reputation`, `calculate_overall_rating()`, `calculate_market_value()` | `shared/PlayerData.gd:92,197,259` | **`[EXISTS]`** — derived fields are already computed and already feed transfer value. `player_reputation` now also drifts from match performance via `MoraleEngine.apply_reputation_drift()` rather than sitting at its authored seed. Nothing reads `overall_rating` to gate AI behavior (star-marking) yet. |
| Manager trait bitmask (10 flags) | `shared/ManagerData.gd:112-123` | **`[EXISTS]` and wired** — `ManagerDirector.gd` reads `has_trait()` for pressing escalation (`HotHead`), formation stance rigidity (`Idealist`), and formation weight bias (`Visionary`); `PressOffice` reads it for quote tone. **This is the reference pattern §1.4 replicates for `PlayerData`.** |
| Persistent relationship graph | `shared/career/RelationshipData.gd` | **`[EXISTS]`** — directed edge, `trust` (0-1), `rivalry_score` (0-1), tagged `history`, monthly decay-to-neutral. Held in `PlayerCareerState.relationships: Dictionary` keyed by the other player's `player_key`. |
| Persistent → in-match trust bridge | `entities/player/TrustSystem.gd`, `MoraleEngine.gd:114-119`, `CareerManager.seed_match_trust()` | **`[EXISTS]`** — the two-space conversion (`normalise_trust`/`denormalise_trust`) is load-bearing and already correctly implemented after a prior bug (see `.agents/rules/career-mode.md`, "Trust lives in two spaces"). |
| In-match trust write events | `TrustSystem.resolve_possession_change()` | **`[EXISTS]` but narrow** — only pass-completion and pass-interception write trust. Tackles, benchings, fouls between teammates, and refused passes write nothing. §2.2 closes this gap. |
| `WorldEvent` / `WorldEventLog` | `shared/career/WorldEvent.gd`, `autoloads/WorldEventLog.gd` | **`[EXISTS]`** — append-only log, 11 categories, significance-gated press pickup, `generate_press_reaction()` already routes through `PressOffice`. **No generator exists** — nothing currently calls `WorldEventLog.record()` for a training incident, dressing-room confrontation, or nightlife event. §3.3 specifies the generator. |
| Mood tiers (SLUMP/NORMAL/STREAK) | `entities/player/MoodSystem.gd` | **`[EXISTS]`** — event-driven deltas, passive drift, per-tick multipliers already read by `HeavyPlayerController` and `PlayerBrain`. |
| Star-marking, ego/pass-starvation, reputation-gated AI behavior | — | **Does not exist.** §4 is the full spec. |
| Player-manager relationship | — | **Does not exist.** `RelationshipData` is keyed generically enough to reuse; §2.3 specifies the manager-edge convention. |

**Design consequence:** every mechanical lever in this document is specified as an *addition to an existing read site*, not a new subsystem. `PlayerBrain.gd` already computes `eff_aggression` (composure/mood-adjusted) at three call sites (lines 732, 1262, 2565) and folds `mood_risk_aversion` into `effective_pressure` at line 1475, and already applies `TrustSystem.trust_multiplier()` inside `_score_pass()` at line 1545. Traits multiply onto these same floats. No new decision loop, no new per-frame allocation, no new choke point.

---

## 1. The Psychological Trait & Archetype Matrix

### 1.1 Existing Bitmask (unchanged)

```gdscript
# shared/PlayerData.gd:75-89 — already shipped, do not renumber the bits.
@export_flags(
    "DeepRunner:1", "WallSplitter:2", "PressureImmune:4", "HotHeadedTackler:8",
    "Talisman:16", "LockerRoomCancer:32", "CaptainMaterial:64", "StreetBaller:128",
    "PrideGlory:256", "VeteranLeader:512", "DeadBallSpecialist:1024",
    "NightOwl:2048", "IronMan:4096"
) var traits: int = 0
```

### 1.2 Mechanical Lever Table

Every trait pulls at least two levers across two different layers, per the cross-layer invariant in `CORE_INVARIANTS.md` §2. "Choke point" is the exact existing read site the lever attaches to — no new signal, no new autoload.

| Trait (bit) | Layer 2 — Match AI Utility | Layer 3 — Emotional Volatility | Layer 4 — Club World Friction |
|---|---|---|---|
| **DeepRunner** (1) | +0.15 weight on `_find_channel_run_target()`'s off-ball scoring for runs beyond the defensive line. Choke: `PlayerBrain` channel-run candidate score, additive before the existing distance/lane terms. | — | — |
| **WallSplitter** (2) | +0.12 to `_score_pass()` for any candidate pass classified as a through-ball (receiver ahead of the last defender). Choke: `_score_pass(ctx)` return, multiplicative `* 1.12`. | — | — |
| **PressureImmune** (4) | Composure floor: `eff_aggression`/`eff_composure` reads clamp their mood contribution to 55% of normal magnitude. Choke: the three `eff_aggression` sites already blend `mood_node.get_aggression_delta()` — wrap that delta in `lerpf(0.0, delta, 0.55)` when the bit is set. | Blunts SLUMP entry: `MoodSystem._set_mood()`'s tier comparison effectively needs a lower `mood_value` to cross `SLUMP_THRESHOLD` for this player (**`[EXISTS]` partially** — currently only applied once, at match-start mood seeding in `MoraleEngine.gd:110`; §1.3 extends it live). | Resists morale free-fall from benching/bad press in `MoraleEngine`. |
| **HotHeadedTackler** (8) | Raises tackle-commit probability: multiply `eff_aggression` feeding tackle-decision logic by `1.15` (mirrors `ManagerDirector`'s own `HotHead` pattern, one layer down the stack). | Composure recovers 20% slower after a card/foul event (`MoodSystem._on_foul_committed` delta ×1.2 when self-fouling). | Elevated `foul_committed` frequency raises `WorldEventLog` disciplinary-incident odds (§3.3). |
| **Talisman** (16) | `_score_pass()` receives +0.10 when the passer is under `effective_pressure > 0.5` (teammates specifically look for the talisman when the picture is scrambled). | Goal/assist events give this player 1.5× the normal `MoodSystem.apply_delta()` magnitude — their form swings the group's. | Their own `MoodSystem` tier feeds a small ambient nudge to every teammate's `MOMENTUM_COMPOSURE_OWN_SCALE` input (opt-in extension of the existing momentum-drift channel; see §1.5 for the guard against snowballing). |
| **LockerRoomCancer** (32) | — | Baseline `mood_value` seed (`MoraleEngine.seed_mood_value`) capped 0.10 below neutral even at high morale/form — this player runs a permanent slight handicap. | Each week idle in the squad without match minutes generates a `WorldEvent.Category.DRESSING_ROOM` incident at 2× the normal base rate (§3.3), and rivalry accrues toward teammates at `MONTHLY_DECAY`-scaled rate even without a triggering micro-event. |
| **CaptainMaterial** (64) | If assigned captain (`PlayerData.is_captain`), teammates' `PressureImmune`-style composure floor (55%) is extended to them too, scaled by `RelationshipData.trust` toward the captain — a captained team panics less as a group. Choke: a small read in the same `eff_aggression`/composure blend, gated behind `GameManager` exposing which squad_index is captain. | — | Directly eligible for the manager-relationship "sounding board" inbox category (§2.3) — the only trait that unlocks that InboxEngine branch. |
| **StreetBaller** (128) | Raises willingness (not eligibility — geometry still gates) to attempt volley/bicycle in `AerialState._attempt_contact()`, per the willingness model already speced in `POWERFOOTBALL_MASTER_VISION.md` Part V "Aerial Contact Personality Weighting". This is the trait that section names explicitly. | — | Off-pitch/nightlife `WorldEvent` generation (§3.3) draws this player at elevated weight. |
| **PrideGlory** (256) | — | Substitution-reaction composure hit is doubled when subbed off before the 60th minute while the scoreline is close (extends `SubReactions`, Layer 3). | Losing a genuine local/national rivalry fixture logs a higher-`significance` `WorldEvent` for this player specifically (feeds §4's reputation-adjacent narrative, not reputation itself). |
| **VeteranLeader** (512) | Extends a damped version of `Talisman`'s ambient composure nudge to nearby low-`experience`/young teammates only (age-gated, not team-wide — the differentiator from `Talisman`). | Their own mood drift rate (`DRIFT_RATE_SLUMP`/`DRIFT_RATE_STREAK`) is 25% slower — veterans ride out bad patches. | `MoraleEngine` weighs their `RelationshipData` toward younger squad members more heavily when computing dressing-room cohesion (§3.2). |
| **DeadBallSpecialist** (1024) | Free kick / corner / penalty taker selection in `SetPieceCoordinator` prefers this player outright (existing selection logic gets a hard preference bit, not a soft utility nudge — dead-ball taker choice is discrete, not scored). | — | — |
| **NightOwl** (2048) | Small permanent `stamina_recover` penalty applied at `PlayerFactory.apply()` bind time (mirrors how career fatigue already modifies bound stats) — this is the trait's only in-match footprint, and it is indirect. | — | Primary driver of `PERSONAL_LIFE` category `WorldEvent`s (§3.3), at a rate further scaled up after a loss or a benching (compounding misbehavior, not random noise). |
| **IronMan** (4096) | `stamina_drain` at bind time scaled down ~12%; injury-system exertion-gate thresholds (Phase 1's injury system, already shipped) relaxed slightly for this player. | — | Career injury frequency (existing recovery-persistence system) draws this player at reduced weight. |

### 1.3 `PressureImmune` — Closing the Live-Match Gap

Currently `PressureImmune` only blunts the mood **seed** at kickoff (`MoraleEngine.gd:110`). To make it a real in-match trait rather than a one-time bias, `MoodSystem.apply_delta()` needs the same damping the seed already gets:

```gdscript
# entities/player/MoodSystem.gd — apply_delta(), extended
func apply_delta(delta: float) -> void:
    if _player != null and _player.player_data != null and _player.player_data.has_trait(4):
        delta *= PRESSURE_IMMUNE_DAMPING   # new const, 0.55 — matches MoraleEngine's seed damping
    _set_mood(mood_value + delta)
```

This requires `MoodSystem` to hold a reference to `PlayerData` (it currently only holds `HeavyPlayerController`). `HeavyPlayerController.player_data` already exists (`PlayerFactory.apply()` sets it) — this is a read, not a new dependency, and costs one branch on an already-called function. Zero hot-path allocation, satisfies `.claude/rules/gdscript-antipatterns.md` §3.

### 1.4 The `TraitEffectResolver` Pattern

`ManagerData`'s traits are read ad hoc, inline, at each of `ManagerDirector`'s several call sites (`has_trait(1)`, `has_trait(8)`, ...). That has worked at 10 traits and low call-site count. At 13 player traits read from *inside PlayerBrain's per-decision-tick hot path* (`_score_pass`, `eff_aggression` — all three read sites, tackle logic), inlining every `has_trait()` call risks scattering bit literals across a dozen functions with no single place to retune a trait's magnitude.

**Specification:** introduce a small static-only helper, not a Node, not a per-frame allocation:

```gdscript
## shared/PlayerTraitEffects.gd — pure static math, no state, no allocation.
## Single place every trait's NUMERIC magnitude lives, so retuning one trait
## never means grepping five files. Callers still do their own has_trait()
## bit test — this only centralizes the "how much," not the "whether."
class_name PlayerTraitEffects
extends RefCounted

const WALL_SPLITTER_PASS_BONUS: float = 0.12
const TALISMAN_PRESSURE_PASS_BONUS: float = 0.10
const HOTHEAD_TACKLE_AGGRESSION_MULT: float = 1.15
const PRESSURE_IMMUNE_DAMPING: float = 0.55
# ... one const per numeric lever in the table above, grouped by trait.
```

Call sites stay exactly where they are today (`_score_pass`, the `eff_aggression` blends) — they gain one `if data.has_trait(BIT): score *= PlayerTraitEffects.CONST` line each, reading the constant instead of a magic number. This is the minimum structural change that keeps every tuning value in one file without adding a class hierarchy PowerFootball-2D's other systems don't use (`MoodSystem`/`TrustSystem` are both plain tuned consts on the Node itself — this preserves that convention rather than introducing a strategy-pattern trait system the rest of the codebase doesn't have).

### 1.5 Trait Interaction & Anti-Snowball Guard

- **Conflicting bits are legal, not mutually exclusive** (`@export_flags` never enforces exclusivity) — a player can be both `LockerRoomCancer` and `Talisman`. Resolve by additive stacking on the underlying float, then a single final `clampf` at the existing multiplier boundaries (`TrustSystem.TRUST_MULT_MIN/MAX`, `MoodSystem`'s `[0,1]` mood range) — never let a trait combination escape the bounds the rest of the system already assumes.
- **`Talisman`'s ambient teammate nudge is capped identically to `MoodSystem`'s existing momentum drift** (`MOMENTUM_COMPOSURE_OWN_SCALE = 0.10`) — reuse that same scale constant rather than inventing a second one, and it must never stack additively with momentum drift into an unbounded loop (a good Talisman on a winning team already gets a momentum boost; the ambient nudge should be the *smaller* of the two effects, not additive on top).

---

## 2. The Social Memory & Relationship Graph

### 2.1 Existing Schema (unchanged)

`RelationshipData` (`shared/career/RelationshipData.gd`) is already the complete directed-edge structure: `trust: float[0,1]`, `rivalry_score: float[0,1]`, `history: Array[String]` (capped 12), `last_interaction_ordinal: int`, monthly decay-to-neutral, and `to_match_multiplier()` which already folds rivalry against trust:

$$\text{effective} = \text{clamp}(trust - rivalry \times 0.5,\ 0,\ 1)$$
$$\text{multiplier} = \text{lerp}(0.85,\ 1.15,\ \text{effective})$$

Held per-player in `PlayerCareerState.relationships: Dictionary`, keyed by the other party's `player_key` (`team_index * 1000 + squad_index`, the same synthesized identity `TrustSystem` and `MatchStatsTracker` already use — see `.claude/rules/ai-architect.md`, "PlayerData has no stable identity").

### 2.2 New Micro-Event → Memory Token Table

The gap identified in §0: `TrustSystem` only ever writes on pass completion/interception. The persistent graph (`RelationshipData`) should accumulate from more of the match than the in-match `TrustSystem` currently tracks, because the persistent graph is what carries story forward — a feud that never gets written down cannot be remembered.

| Match Micro-Event | Existing Signal | New Write (post-match, batched — not live) | Magnitude |
|---|---|---|---|
| Pass completed to teammate | `TrustSystem.resolve_possession_change()` `[EXISTS, in-match only]` | `RelationshipData.adjust_trust(+delta, "", ordinal)` at match end, summed over the match's completions for that pair | `+0.01` per completion, capped `+0.05`/match/pair |
| Pass intercepted (receiver was the intended target) | Same, `[EXISTS, in-match only]` | `adjust_trust(-delta, "misplaced pass under pressure", ordinal)` | `-0.02`, capped `-0.08`/match/pair |
| Foul committed by a teammate against this player (own-team foul, e.g. reckless tackle in training-adjacent friendly minutes — rare but must not silently no-op) | `GameEvents.foul_committed` `[EXISTS]` | `adjust_rivalry(+delta, "training-ground clash", ordinal)` | `+0.10`, single event |
| **Refused an open, high-utility pass** — the highest-signal event for the "star sulks" story beat. Requires a NEW check: `PlayerBrain._score_pass()` already computes every candidate's score; if the actually-chosen target scored meaningfully below the best-available candidate AND that candidate had `RelationshipData.rivalry_score >= 0.4` toward the passer, log it. | **New** — a post-hoc comparison inside the existing scoring loop, not a new evaluation pass. | `adjust_rivalry(+0.03, "ignored on an open look", ordinal)` on BOTH directions of the edge (the passer resents being seen as unreliable too) | Rate-limited to once per pair per match — this is a narrative flag, not a live counter. |
| Player benched despite fit/available, `squad_status` in {"Star Player","Important"} | New — `CareerManager` already knows the lineup selection outcome. | `RelationshipData` edge toward the **manager** (§2.3), `adjust_trust(-0.06, "left out of the squad", ordinal)` | Scaled by `1.0 - loyalty` (low-loyalty players resent benching far more; `PlayerData.loyalty` already exists). |
| Late goal conceded/scored | `GameEvents.goal_scored`, minute available from `GameManager` | Whole-squad `RelationshipData` cohesion nudge is deliberately **not** modeled per-pair (would be O(n²) writes per goal) — instead a single scalar `PlayerCareerState.team_cohesion_delta` accumulator, consumed once post-match by `MoraleEngine`. | — |

All new writes are **batched at match end**, read from the already-existing `MatchStatsTracker`/`PlayerRatingCalculator` per-player event summaries rather than adding new signal listeners mid-match. This is a deliberate constraint: `RelationshipData` is career-space and `CareerManager.career` is `null` outside a career (Kick Off, Practice Arena) exactly like `TrustSystem`/`MoodSystem` must degrade to no-ops there — batching at the existing "match finished, now log career state" step means this new logic lives in exactly one place (`CareerManager`'s post-match hook) instead of needing a null-guard scattered through match-time signal handlers.

### 2.3 Player–Manager Relationship Edge

`RelationshipData` has no concept of "the other party is a manager, not a player" — it is keyed purely by an opaque int. Two options: reuse `PlayerCareerState.relationships` with a manager sentinel key, or a parallel dictionary. **Specification: reuse the same dictionary with a reserved key range.**

```gdscript
## Manager relationship keys live OUTSIDE the 0-21999 player_key space
## (team*1000+squad_index maxes at team=1 -> 1999, but squads can exceed 22 in
## the wider league, so reserve a clearly out-of-band band instead of assuming
## a ceiling). Manager key = 100000 + league_team_index.
const MANAGER_RELATIONSHIP_KEY_BASE: int = 100000

static func manager_relationship_key(league_team_index: int) -> int:
    return MANAGER_RELATIONSHIP_KEY_BASE + league_team_index
```

This lets every existing `RelationshipData` method (`adjust_trust`, `adjust_rivalry`, `decay_toward_neutral`, `relation_label()`) work unmodified for player↔manager edges — no new class, no schema fork. `CaptainMaterial`'s "sounding board" inbox unlock (§1.2) and the benching-resentment write above (§2.2) both target this key range.

---

## 3. The Five-Layer Event Propagation Pipeline

### 3.1 Worked Cascade (traced against real call sites)

The vision document's abstract "Physics Collision → Social Friction → Club World Incident → Narrative" chain, made concrete end-to-end:

```
LAYER 1  HeavyPlayerController / TackleState
         A mistimed tackle: GameEvents.tackle_won.emit(winner, loser)
                                    │
LAYER 3  MoodSystem._on_tackle_won()          [EXISTS]
         loser.apply_delta(-0.05)  →  possible SLUMP tier flip
         + NEW: if the tackle was reckless (foul_committed same frame),
           RelationshipData rivalry write queued for §2.2's post-match batch
                                    │
LAYER 4  CareerManager post-match hook (NEW, §2.2)
         RelationshipData.adjust_rivalry(+0.10, "training-ground clash", ordinal)
         WorldEventLog.record(&"dressing_room_friction",
             WorldEvent.Category.DRESSING_ROOM, narrative, sentiment=-0.3,
             significance=0.4)                          [record() EXISTS]
                                    │
LAYER 5  WorldEventLog.generate_press_reaction(event, manager)  [EXISTS]
         routes through PressOffice.generate_quote() — same trait-driven
         voice the touchline already uses (ManagerData.has_trait() read
         inside PressOffice, unchanged)
```

Every node in that chain except the two `NEW` boxes already exists and already fires today. The design contribution is exactly two things: (1) tag a subset of `foul_committed` events as rivalry-worthy at the moment they happen (Layer 1→3, cheap, already-emitted signal), and (2) a single post-match batching step that turns queued in-match social friction into `RelationshipData` writes and a `WorldEvent` (Layer 3→4→5). No new autoload, no new signal bus, no new choke point — this is additive to `CareerManager`'s existing "match finished" handling and `MoodSystem`'s existing signal handlers.

### 3.2 `WorldEvent` Schema Extension

Categories `[EXISTS]` (`shared/career/WorldEvent.gd:23-35`): `MATCH, TRAINING, DRESSING_ROOM, INJURY, TRANSFER, CONTRACT, MEDIA, BOARD, YOUTH, PERSONAL_LIFE, STAFF`. All 11 are sufficient for every trait-driven and relationship-driven event in §1-2 — **no new category is needed**, only new `tag: StringName` values within `DRESSING_ROOM`, `PERSONAL_LIFE`, and `TRAINING` for the generator in §3.3 to use (tags are free-form `StringName`, not an enum, per `WorldEvent.make()`'s signature — confirm against the source before assuming otherwise).

### 3.3 The Between-Match World Event Generator

`WorldEventLog` today is purely reactive — an append/query API with zero autonomous generation. Every trait table entry in §1.2 that references "generates a WorldEvent at elevated weight" requires a generator, which does not exist. Specification:

```gdscript
## shared/career/WorldEventGenerator.gd — NEW. Pure function of career state,
## called once per CareerManager.advance_day() tick (the existing daily
## cadence — see career-mode.md's "season calendar is derived" note; this
## rides the same tick, it does not add a new timer).
##
## Deliberately NOT a Node/autoload: stateless roll-the-dice logic over
## CareerSaveData, matching CareerSerializer's and TransferMarket's existing
## "plain class over the save data" convention rather than MoraleEngine's
## Node-adjacent pattern (MoraleEngine takes live match nodes; this never
## touches one).
class_name WorldEventGenerator
extends RefCounted

## Per-player, per-day base probability of ANY off-pitch event firing.
## Deliberately tiny — this is a rare-event generator, not a soap opera.
const BASE_DAILY_EVENT_CHANCE: float = 0.015

static func roll_for_day(career: CareerSaveData, rng: RandomNumberGenerator) -> void:
    for team: TeamData in DataLoader.get_all_teams():
        if team.team_name != career.user_club_name:
            continue   # only the user's club generates story beats — opponents
                       # are not simulated at this granularity, matching how
                       # QuickSimEngine already treats off-screen clubs abstractly
        for squad_index: int in range(team.squad.size()):
            var data: PlayerData = team.squad[squad_index]
            var chance: float = BASE_DAILY_EVENT_CHANCE * _trait_weight(data)
            if rng.randf() < chance:
                _fire_event(career, team, squad_index, data, rng)
```

`_trait_weight()` is the single place §1.2's "elevated weight" language becomes a number — `StreetBaller`/`NightOwl` multiply `PERSONAL_LIFE` odds (~2.5×), `LockerRoomCancer` multiplies `DRESSING_ROOM` odds when `squad_status` shows reduced minutes, `DeadBallSpecialist`/`VeteranLeader` are dampeners (professionals generate fewer incidents). This keeps the RNG surface tiny and auditable rather than a sprawling event-table JSON — consistent with how `TransferMarket`/`ScoutingNetwork` already keep their randomness in code, not data files, per the existing `docs/json-schema.md` split between authored and derived fields.

**Constraint carried over from `career-mode.md`:** any event this generator creates that requires a player DECISION (accept/reject a resolution, matching `InboxItem.Option`'s existing pattern) must NOT serialize the option deltas — only the resolved text and outcome persist, exactly like the existing inbox rule. A new `DRESSING_ROOM` decision category needs a matching branch in `CareerManager._rehydrate_inbox()`, the same requirement any new decision-bearing category already carries.

---

## 4. Star Gravity & Tactical Asymmetry

### 4.1 Star Tier — Built On, Not Replacing, Existing Fields

`PlayerData.calculate_overall_rating()` (1-99) and `player_reputation` (0-1) both **already exist and are already computed** (§0). Star gravity is a derived read of these two existing fields, not a new attribute:

$$\text{star\_score} = 0.4 \times \frac{\text{overall\_rating} - 45}{54} + 0.6 \times \text{player\_reputation}$$

$$\text{Star Tier} = \begin{cases} \text{World Class} & \text{star\_score} \geq 0.80 \\ \text{Star} & 0.62 \leq \text{star\_score} < 0.80 \\ \text{Regular} & \text{star\_score} < 0.62 \end{cases}$$

The 0.4/0.6 weighting deliberately favors reputation over raw rating — a well-rated but anonymous squad player (high `overall_rating`, low `player_reputation`) should not trigger star-marking; a famous, ageing, declining player (moderate `overall_rating`, high `player_reputation`) should. This mirrors the vision document's own framing: "efficient but not famous" vs. "famous enough to distort tactical behavior."

### 4.2 Star-Marking Utility Scorer — Full Specification

**Trigger condition:** at formation-bind time (`ManagerDirector._apply_formation()`, already the place formation anchors are written — no new bind hook), scan the opposing team's squad for any player at `Star Tier >= Star`. If one exists, the highest-tier opposing player becomes the `marked_target`.

**Mechanism — reuses the existing defensive anchor blend, does not add a new AI mode:**

`PlayerBrain`'s `OUTFIELD_DEFENDER` branch already blends between a dynamic anchor and `MatchWorldModel.defensive_line_x` (per `ai-architect.md`, "Defensive line depth is computed ONCE"). Star-marking adds a THIRD blend term, active only for the one defender assigned to shadow:

$$\vec{p}_{\text{anchor}} = (1 - \omega_{\text{mark}}) \cdot \vec{p}_{\text{formation}} + \omega_{\text{mark}} \cdot \vec{p}_{\text{marked\_target}}$$

Where $\omega_{\text{mark}}$ scales with star tier (`0.55` for Star, `0.75` for World Class) and decays toward `0.0` as distance from the marked player's own defensive third increases (a marker does not follow a World Class winger into their own box — the existing formation anchor should reassert near the marker's own goal). This is a straight three-term lerp inserted at the exact point `defensive_line_x` is already blended in, not a new steering force category — it costs one extra `Vector2` lerp per marking defender per decision tick (already gated behind the existing 15-frame stagger).

**Marker selection:** the nearest available center-back or the nearest same-role defender to the star's average position over the last N decision ticks (not their instantaneous position — a star drifting wide should pull a marker, but noise in a single tick should not cause anchor thrashing). Reuses `MatchWorldModel.player_positions` reads already in place; adds one rolling-average scratch float pair per defender, matching the zero-allocation discipline `PlayerBrain` already follows for its other cached scratch buffers (`_find_nearby_opponents()`'s pattern, per `ai-architect.md`).

**Giving up shape:** exactly one defender (never two — double-teaming a star is a distinct, larger tactical change out of scope here) sacrifices formation rigidity. This is the "at least one defender gives up ideal formation anchoring" requirement from the vision document, made literal: `PlayerRoleConfig.anchor_weight` for that one player is read as if it were lower than authored, scaled by `(1 - \omega_{\text{mark}})`, for the duration of the marking assignment only — the `.tres` resource itself is never mutated.

### 4.3 Ego / Catering — Pass-Starvation Morale Penalty

A star who touches the ball meaningfully below their `player_reputation`-implied expectation should sour. Computed post-match from data `MatchStatsTracker` already accumulates (touches, passes received):

$$\text{expected\_share} = \text{lerp}(0.06,\ 0.14,\ \text{player\_reputation})$$
$$\text{actual\_share} = \frac{\text{touches}_{\text{player}}}{\text{touches}_{\text{team}}}$$
$$\Delta\text{morale} = \text{clamp}\left((\text{actual\_share} - \text{expected\_share}) \times 1.5,\ -0.08,\ +0.04\right)$$

Applied to `PlayerData.morale` at the same post-match step §2.2's batched relationship writes happen in — one more write in an already-existing hook, not a new one. The asymmetric clamp (larger downside than upside) matches the vision document's framing that failing to feed a superstar is punished harder than successfully doing so is rewarded — stars expect service; they do not throw parties for receiving exactly what was expected.

### 4.4 Aerial Willingness — Cross-Reference

`POWERFOOTBALL_MASTER_VISION.md` Part V, "Aerial Contact Personality Weighting," already specifies this fully (heading skill, match desperation, proximity-to-goal, and `StreetBaller` as the willingness trait). This document does not duplicate it — implement it as specified there, using `PlayerTraitEffects` (§1.4) as the constant-holding location for its willingness weights rather than inlining magic numbers in `AerialState._attempt_contact()`.

---

## 5. Master Implementation Blueprint

Sequenced to avoid the exact failure mode the vision document's own Part VIII warns about — compounding speculative changes on shared state. Each step is independently shippable and independently verifiable via `tools/verify_gate.py`.

```
STEP 1 — PlayerTraitEffects.gd (new file, pure consts)               [Tier 1]
  No behavior change yet. Just the constant table from §1.4.

STEP 2 — Wire the 3 lowest-risk traits into PlayerBrain               [Tier 3]
  WallSplitter (_score_pass), HotHeadedTackler (eff_aggression),
  PressureImmune-live (MoodSystem.apply_delta, §1.3).
  Blast radius: PlayerBrain.gd, MoodSystem.gd — mandatory
  `dump_dep_graph.py --blast-radius` per CORE_INVARIANTS Tier 3 gate.
  Verify: fuzz_solvers.py (no NaN/inf from new multiplier paths),
  eval_simulation.py --duration=10 (no crash, no invariant violation).

STEP 3 — Remaining 10 traits, same pattern, one PR-sized batch each   [Tier 2/3]
  Talisman and VeteranLeader (ambient composure) are the highest-risk
  pair — verify against §1.5's anti-snowball guard explicitly.

STEP 4 — §2.2 micro-event → RelationshipData batching                [Tier 2]
  Lives entirely inside CareerManager's existing post-match hook.
  Must remain a no-op when CareerManager.career == null (Kick Off,
  Practice Arena) — same guard TrustSystem/MoodSystem already carry.

STEP 5 — §2.3 manager relationship key range                         [Tier 2]
  Additive to RelationshipData's existing consumers — verify no
  existing code assumes player_key < 100000 as an invariant
  (grep every `relationships.get(` / `relationships[` call site first).

STEP 6 — WorldEventGenerator.gd (§3.3)                                [Tier 2]
  Rides CareerManager.advance_day()'s existing daily tick.
  New InboxEngine branch for any decision-bearing DRESSING_ROOM event,
  per career-mode.md's serialization constraint.

STEP 7 — Star tier derivation + star-marking anchor blend (§4.1-4.2)  [Tier 3]
  Touches ManagerDirector._apply_formation() and PlayerBrain's
  OUTFIELD_DEFENDER anchor blend — both are named Tier 3 choke points
  in AGENTS.md's table. Full blast-radius + Graphify neighbor trace
  mandatory before this step, not optional.
  Verify: fuzz_formations.py (marking assignment must not produce
  formation anchors outside pitch bounds), replay_test.py (determinism
  preserved — marker selection RNG, if any, must be seeded).

STEP 8 — Ego/catering morale penalty (§4.3)                          [Tier 2]
  Same post-match hook as Step 4 — bundle into the same PR if the
  batching infrastructure from Step 4 already exists.

STEP 9 — Aerial willingness weighting                                 [Tier 3]
  Already fully specified in POWERFOOTBALL_MASTER_VISION.md Part V;
  implement against AerialState._attempt_contact(), reading constants
  from PlayerTraitEffects (Step 1).

STEP 10 — Documentation & ROADMAP correction
  Flip ROADMAP.md Phase 2 items 12-15 as each step ships. Separately,
  file a correction: items "Player trait bitmask on PlayerData" and
  "overall_rating and reputation derived fields" should be marked
  [x] with a note that only the CONSUMERS were missing, per §0 — the
  data layer shipped earlier than the roadmap reflects.
```

### 5.1 Choke Points Touched, Summarized

| File | New Reads | New Writes | Tier |
|---|---|---|---|
| `shared/PlayerTraitEffects.gd` | — | new file | 1 |
| `entities/player/PlayerBrain.gd` | `PlayerData.traits`, `PlayerTraitEffects.*` | none (reads only) | 3 |
| `entities/player/MoodSystem.gd` | `HeavyPlayerController.player_data` | none | 2 |
| `autoloads/CareerManager.gd` | `MatchStatsTracker` per-player summaries | `RelationshipData` (player-player, player-manager), `PlayerData.morale` | 2 |
| `shared/career/WorldEventGenerator.gd` | `CareerSaveData`, `DataLoader` | `WorldEventLog.record()` (existing API) | 2 |
| `entities/manager/ManagerDirector.gd` | `PlayerData.calculate_overall_rating()`, `player_reputation` | formation anchor override (existing write path) | 3 |
| `autoloads/CareerManager.gd` (InboxEngine branch) | `WorldEvent` category/tag | `InboxItem` | 2 |

No file in this table is touched that is not already named as a Tier 2/3 choke point in `AGENTS.md`'s change-impact table — this blueprint introduces zero new choke points to the architecture.

---

## 6. Open Design Questions (deliberately deferred, not resolved here)

- **Opponent-club world events:** §3.3 only generates events for the user's own club, matching `QuickSimEngine`'s existing off-screen abstraction. A future pass could extend generation to rival clubs specifically to feed transfer-market rumor generation (`WorldEvent.Category.TRANSFER`) about players the user might scout — deliberately out of scope here since it requires deciding how deep off-screen club simulation should go, which is a `QuickSimEngine` design question, not a social-simulation one.
- **Double-marking / zonal star-suppression** as a distinct tactical mode from single-marker shadowing (§4.2 explicitly limits to one defender) is a plausible Phase 3+ extension once single-marking is verified stable in `eval_simulation.py` over many simulated matches.
- **Trait rarity/authoring tooling** — nothing here specifies how traits get assigned to authored players (`squads.json`-equivalent `.tres` authoring). That is a `docs/json-schema.md` concern, not an architecture concern, and should be resolved there when Phase 2 traits actually ship.
