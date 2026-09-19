# Data, Persistence & Career Calibration Errata

**Simulation Layer:** Layer 1 — Career World (career persistence)  
**Primary Modules:** `autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `shared/PlayerData.gd`, `shared/career/*`

This page documents gotchas in career mode progression curves, player aging decline formulas, season calendar fixture spacing, and the historical morale→mood seeding calibration (that seeding target, `MoodSystem`, is now archived under `legacy/` — see [architecture-pivot.md](architecture-pivot.md)).

---

## Table of Contents
### Career Calibration Findings
- [Calibration is not optional, and the first guess was wrong twice](#calibration-is-not-optional-and-the-first-guess-was-wrong-twice)
- [The season calendar cannot be a fixed weekly rhythm](#the-season-calendar-cannot-be-a-fixed-weekly-rhythm)
- [Promotion/relegation bookkeeping never reaches next season](#promotionrelegation-bookkeeping-never-reaches-next-season)

---

## Calibration is not optional, and the first guess was wrong twice

Two models were plainly wrong on their first numbers and only surfaced by
plotting them:

- **Player decline** multiplied a per-year rate by years-past-peak, compounding
  into an 11% single-season pace loss by 33 and driving every player to the
  `top_speed` floor by 34 — a cliff, not a curve. Reworked to a small base with
  a gentle ramp: ~23% loss across ages 30-38, and traits now spread that from
  156 (fragile, unprofessional) to 197 (IronMan professional) on a 220 base.

- **Morale -> MoodSystem seeding** *(historical: `MoodSystem` is archived under `legacy/`; the surviving career morale model is `shared/career/MoraleEngine.gd`)* used a symmetric slope that dropped a merely
  "Restless" player (morale 0.45) into SLUMP — a heavy penalty tier. Made
  asymmetric (0.56 down / 0.70 up) so SLUMP needs genuine unhappiness. Verified
  anchors: authored default (0.70/6.5) lands exactly on 0.500 NORMAL.

**Rule:** port any new curve to Python and print it across its real input range
before committing it. Both bugs were invisible in code review and obvious in
one table of numbers.

---

## The season calendar cannot be a fixed weekly rhythm

A hard 7-day matchday spacing gave the shipped 8-club league a 14-matchday
season ending in early November. Spacing is now derived from the round count
and the target last-matchday date, so 8 clubs space to 21 days and 20 clubs
compress to 7. The rollover guard was likewise a bare `today.month < 6`, which
fired instantly for a November finish and blocked an April one; it is now an
explicit season-end date.

---

## Promotion/relegation bookkeeping never reaches next season

The shipped `data/world_manifest.json` was 20 top flights, every one
`tier_index: 1` with `promotion_slots: 0`, so `CareerManager._apply_promotion_relegation()`
returned early at its `if tiers.size() >= 2:` guard and **no career could ever be
promoted or relegated** — the `relegation_slots` in the data were decorative. The
only multi-tier coverage was a synthetic 4-team T1/T2/T3 built inside
`tests/run_all.gd`. `tools/generate_phony_db.py` now emits a tier 2 division for
every nation (744 clubs across 40 divisions), which removes that gate.

The deeper trap: the rollover is **bookkeeping only**. `career.tier_indices`,
`tier_1_indices` and `tier_2_indices` have zero live readers — `_build_divisions_competitions()`
re-derives every competition from `DataLoader.divisions` (the static manifest) on each
pre-season. A swap written into `tier_indices` at season end is therefore discarded
before the next fixture list exists. Making promotion real requires the rollover to
persist a division→clubs mapping that `_build_divisions_competitions()` actually consumes.

Two related contracts:

- **`tier_index` is per-nation, not global.** Keying `tier_comps` by `tier` alone merges
  England's tier 2 with Spain's tier 2 into one 40-club "tier". Any pyramid logic must key
  on `(nation, tier_index)`.
- **League indices are packed in manifest order.** `DataLoader._get_division_start_team_index()`
  and the continental seeding loop in `CareerManager._build_competitions()` both walk
  `DataLoader.divisions` accumulating `team_count`. Append new divisions at the END of the
  manifest to keep every issued team index — and every existing save — valid.

The continental seeding loop also read the *first* tier-1 competition it found (always
England's Premier League) and its `career.continental_indices` write was overwritten by the
next pre-season's `_build_competitions()`, so continental entry was static-by-manifest-order
rather than performance-based. A `tier_index != 1` guard now keeps second-division clubs out
of the continental field, verified by `World DB: continental seeding excludes second-division clubs`
in `tests/run_all.gd`.
