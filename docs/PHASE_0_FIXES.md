# Phase 0 Architectural Fixes (P1–P4)

This document records the design rationale, contract modifications, and verification evidence for the Phase 0 architectural fixes implemented in PowerFootball-2D to unblock the world-wide synthetic database generator (`tools/generate_phony_db.py`).

---

## 1. P1: Tier-Aware Competition Construction & Multi-Tier League Systems

### Problem
Previously, `autoloads/CareerManager.gd` built competitions assuming a single flat 8-team or 16-team league division, hardcoding two tiers (`tier_1_indices` and `tier_2_indices`). Grouped divisions (e.g. regional leagues with multiple parallel groups at tier 3) were unsupported, cup knockout generation required power-of-two team counts, fixture generation could exceed calendar constraints on large leagues without capping, and promotion/relegation was hardcoded to swap between exactly two tiers.

### Solutions
1. **Tier-Aware & Grouped Competitions:**
   - Updated `shared/career/CompetitionData.gd` to store `group_index: int = -1`, `promotion_slots: int = 0`, `relegation_slots: int = 0`, `single_round_robin: bool = false`, and `max_rounds_cap: int = -1`.
   - Updated `autoloads/CareerManager.gd`:
     - `_build_competitions()` checks `DataLoader.manifest_mode` and `DataLoader.divisions`. If divisions exist, it dispatches to `_build_divisions_competitions()`; otherwise, it falls back to `_build_flat_competitions()`.
     - `_build_divisions_competitions()` builds a separate `CompetitionData` for each division/group, populating promotion/relegation metadata and assigning tier/group labels.
2. **Cup Knockout Bye Seeding:**
   - In `CompetitionData.gd::draw_cup_round()`, non-power-of-two team counts (e.g. 3, 5, 6, 7, 10, 15, 20, 60) are handled by computing the largest power of two less than the team count $P = 2^{\lfloor \log_2 N \rfloor}$.
   - Number of preliminary matches is $M = N - P$, and number of byes is $B = N - 2M = 2P - N$. The top $B$ seeded teams receive automatic byes to Round 2, while the remaining $2M$ teams play preliminary knockout matches.
3. **Adaptive Matchday Spacing & Fixture Capping:**
   - In `autoloads/CareerManager.gd::_matchday_spacing()`, spacing adapts smoothly: $\le 10$ teams = 7 days; $11\text{--}16$ teams = 4 days; $> 16$ teams = 3 days.
   - In `CompetitionData.gd::generate_league_fixtures()`, the 5th parameter `max_rounds_cap: int = -1` allows capping total rounds generated so massive divisions (e.g. 190 teams) do not flood memory or calendar buffers ($> 500$ fixtures).
4. **Data-Driven Multi-Tier Promotion/Relegation:**
   - `autoloads/CareerManager.gd::_apply_promotion_relegation()` dynamically traverses `save.tier_indices` (an array of arrays of team indices for tiers $0, 1, \dots, T-1$).
   - For each tier boundary $t \to t+1$, relegated teams from tier $t$ (bottom $N$ slots) swap with promoted teams from tier $t+1$ (top $N$ slots), dynamically adjusting to arbitrary pyramid depths.

---

## 2. P2: Sharded League Data Architecture & On-Demand Loading

### Problem
A worldwide football pyramid with hundreds of divisions and thousands of clubs cannot reside comfortably in a single massive JSON file without causing severe memory bloat and long boot times.

### Solutions
1. **Manifest Mode & Division Metadata:**
   - `autoloads/DataLoader.gd` inspects the root JSON structure. If `"divisions"` is present, it operates in `manifest_mode = true`.
   - Division definitions include `tier_index`, `group_index`, `team_count`, `promotion_slots`, `relegation_slots`, `shard` relative path, and stub team metadata (`team_name`, `reputation`).
   - Generates indexed placeholder teams in `league.teams` so all global indices remain contiguous and stable.
2. **Lazy Shard Caching & Dirty Tracking:**
   - Added `load_division_shard(division_index: int) -> bool` to dynamically load and cache full squad rosters and details when required by the simulation or UI.
   - Added `loaded_shards: Dictionary` and `dirty_shards: Dictionary` to track modifications.
   - `save_league()` writes dirty shards back to disk or saves flat files when running in legacy flat mode.
3. **Arbitrary Tier Hierarchy Serialization:**
   - Extended `shared/career/CareerSaveData.gd` with `tier_indices: Array = []` (array of integer arrays). Backward compatibility is maintained with existing `tier_1_indices` and `tier_2_indices`.
   - Updated `shared/career/CareerSerializer.gd` to serialize and deserialize `tier_indices`.

---

## 3. P3: Decoupling the Retired Real-Time Match Engine

### Problem
The real-time 22-player match engine was archived in `legacy/` behind `legacy/.gdignore`, but residual entry points (`play_next_fixture`, `record_user_match_result`) remained in `autoloads/CareerManager.gd`, inviting architectural drift and confusion. Furthermore, `legacy/` was tracked in git, complicating clean builds.

### Solutions
1. **Removed Dead Entrypoints:**
   - Completely deleted `play_next_fixture()`, `record_user_match_result()`, and `_find_pending_fixture()` from `autoloads/CareerManager.gd`.
   - Match simulation now exclusively flows through `CareerManager.simulate_next_fixture()` $\to$ `QuickSimEngine.simulate_match()` $\to$ `CareerManager._apply_fixture_result()`.
2. **Repository & Git Hygiene:**
   - Added `legacy/` and `data/generated/` to `.gitignore`.
   - Untracked `legacy/` from git index (`git rm --cached -r legacy`) while preserving all 88 physical files and `legacy/.gdignore` on disk for historical reference.

---

## 4. P4: Quick Match Exhibition Mode & Custom League Ingestion

### Problem
Users had no way to play a standalone exhibition quick match or load external league configurations without modifying the default package files or contaminating a career save slot.

### Solutions
1. **Quick Match Exhibition Mode:**
   - Added `QuickMatchButton` to `ui/MainMenu.tscn`.
   - Added programmatic exhibition modal in `ui/MainMenu.gd` that resolves a fixture using `QuickSimEngine.simulate_match()` with real team, manager, and referee selections from `DataLoader`.
   - Runs in complete isolation: never instantiates or mutates `CareerManager.career` or writes to `user://career/`.
2. **Custom League Loader:**
   - Added "Load Custom League" button and `FileDialog` in `ui/OptionsMenu.tscn` and `ui/OptionsMenu.gd`.
   - Ingests user JSON manifests or flat league files via `DataLoader.load_league_from()`, copying to `user://custom_league.json` for persistence.

---

## 5. Verification Suite

All modifications are validated by:
1. Fast gate static linters: `python3 tools/verify_gate.py --fast` (10/10 linters pass with 0 errors).
2. Headless regression runner: `godot --headless tests/TestRunner.tscn` (16/16 tests pass).
3. Schema & database validation: `python3 tools/verify_db.py`, `python3 tools/validate_schemas.py`.
