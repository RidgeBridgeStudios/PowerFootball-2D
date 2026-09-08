# Data, Persistence & Career Calibration Errata

**Simulation Layer:** Layer 4 — Club World & Career Persistence  
**Primary Modules:** `autoloads/CareerManager.gd`, `autoloads/DataLoader.gd`, `shared/PlayerData.gd`, `shared/career/*`

This page documents gotchas in career mode progression curves, player aging decline formulas, morale-to-mood seeding slopes, and season calendar fixture spacing.

---

## Table of Contents
### Career Calibration Findings
- [Calibration is not optional, and the first guess was wrong twice](#calibration-is-not-optional-and-the-first-guess-was-wrong-twice)
- [The season calendar cannot be a fixed weekly rhythm](#the-season-calendar-cannot-be-a-fixed-weekly-rhythm)

---

## Calibration is not optional, and the first guess was wrong twice

Two models were plainly wrong on their first numbers and only surfaced by
plotting them:

- **Player decline** multiplied a per-year rate by years-past-peak, compounding
  into an 11% single-season pace loss by 33 and driving every player to the
  `top_speed` floor by 34 — a cliff, not a curve. Reworked to a small base with
  a gentle ramp: ~23% loss across ages 30-38, and traits now spread that from
  156 (fragile, unprofessional) to 197 (IronMan professional) on a 220 base.

- **Morale -> MoodSystem seeding** used a symmetric slope that dropped a merely
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
