# Phase 0 Architectural Fixes (P1–P4) — Final Report

## 1. What shipped

- **P1 — Tier-Aware Competition Construction & Multi-Tier League Systems (`673483f`):** Modified `shared/career/CompetitionData.gd` and `autoloads/CareerManager.gd`. Replaced hardcoded two-tier logic with arbitrary tier depth support (`tier_indices`), grouped division building, tournament cup preliminary bye seeding for non-power-of-two team counts, adaptive calendar matchday spacing, fixture round capping (`max_rounds_cap`), and data-driven multi-tier promotion/relegation.
- **P2 — Sharded League Data Architecture & On-Demand Loading (`5be4884`):** Modified `autoloads/DataLoader.gd`, `shared/career/CareerSaveData.gd`, and `shared/career/CareerSerializer.gd`. Introduced manifest mode parsing with division and stub team structures, on-demand shard loading (`load_division_shard`), loaded and dirty shard tracking dictionaries, and serialization/deserialization of arbitrary tier hierarchies in career saves.
- **P3 — Decouple the Retired Real-Time Match Engine (`07fbe0e`):** Modified `autoloads/CareerManager.gd` and `.gitignore`; untracked `legacy/` from git index. Deleted dead match-entry methods (`play_next_fixture`, `record_user_match_result`, `_find_pending_fixture`), added `legacy/` and `data/generated/` to `.gitignore`, and removed all 88 legacy match-engine files from git tracking while leaving the physical files and `legacy/.gdignore` intact on disk.
- **P4 — Quick Match Exhibition Mode & Custom League Ingestion (`7c80bd9`):** Modified `ui/MainMenu.gd`, `ui/MainMenu.tscn`, `ui/OptionsMenu.gd`, and `ui/OptionsMenu.tscn`. Added a standalone Quick Match exhibition modal in the main menu that resolves matches through `QuickSimEngine` with zero career state mutation, and added a custom league file dialog importer in the options menu targeting `user://custom_league.json`.

Reference: see `git log --oneline -n 6`.

---

## 2. Verification status

| Invariant / Requirement | Status | Notes |
|---|---|---|
| Validators pass against current `data/` | **verified** | `verify_db.py` (16 teams, 288 players, 18 managers, 8 refs, 84 staff) and `validate_schemas.py` pass with 0 errors. |
| Regression suite passes headless | **verified** | `godot --headless tests/TestRunner.tscn` passes 16/16 tests across P1–P4. |
| `play_next_fixture` / `record_user_match_result` / `_find_pending_fixture` have zero live callers | **verified** | Zero call sites outside `legacy/`; confirmed via ripgrep (see Appendix). |
| Live tree has zero references to `res://pitch/` or `res://entities/` | **verified** | Zero references in live `.gd` and `.tscn` code (only `entities/manager/PressOffice.gd` exists as a live class). |
| RAM/boot measurement for flat vs sharded at scale | **partial** | Only 16-team flat (~152.8 MB) vs 4-team synthetic manifest (~151.0 MB) was measured; the ~200-team comparison P2 was meant to justify was not built. |
| Quick Match flow end-to-end through UI | **partial** | `QuickSimEngine.simulate_match()` isolation from career state is verified; the MainMenu → modal → simulate → return path was not driven headlessly. |
| Serializer round-trip preserves manifest and writes dirty shards only | **not verified** | Dirty shard writing logic exists in `DataLoader.save_league()`, but round-trip preservation and dirty-only writes are unverified by tests. |

---

## 3. Known limitations carried into Phase 1

1. **Fixture cap produces truncated league tables for oversized divisions:**
   - *Limitation:* When `max_rounds_cap` limits total rounds on divisions with large team counts (e.g. 190 teams capped to 5 rounds = 475 fixtures), teams only play a small subset of opponents, resulting in unbalanced/truncated tables.
   - *Why unresolved:* Resolving degenerate seasons requires structural scheduling rules (e.g. conference splits or sub-group pools), which were out of scope for Phase 0.
   - *Future fix:* Automatically partition oversized divisions into regional or numbered sub-groups prior to fixture generation.
2. **Quick Match UI flow is not covered by an automated test:**
   - *Limitation:* UI button clicks, modal transitions, and team dropdown interactions in `MainMenu.gd` are not automated in `tests/run_all.gd`.
   - *Why unresolved:* Headless GUI integration harness was not in scope; only the underlying simulation isolation contract was verified.
   - *Future fix:* Add a headless GUI integration test or GUT harness to dispatch button events and assert modal presentation.
3. **Serializer dirty-shard-only saving is claimed but not proven:**
   - *Limitation:* `DataLoader.save_league()` contains dirty shard detection, but no automated test verifies that saving writes only dirty shard files while leaving pristine shards untouched.
   - *Why unresolved:* Test coverage focused on manifest parsing, team indexing, and load paths.
   - *Future fix:* Write an integration test that mutates one team in shard A, calls `save_league()`, and verifies filesystem timestamps and file writes across all shards.
4. **No manifest-scale (200+ team) RAM/boot measurement exists:**
   - *Limitation:* Memory and boot times were measured only for the default 16-team flat database and a 4-team synthetic manifest.
   - *Why unresolved:* The full-scale worldwide database generator (`tools/generate_phony_db.py`) has not yet been built.
   - *Future fix:* Benchmark `/usr/bin/time -v godot --headless --quit-after 2` against the 800+ team database once generated in Phase 1.
5. **Group-split tiers are structurally supported in `CompetitionData` but not exercised against a real multi-group nation:**
   - *Limitation:* Group metadata (`group_index`) and group fixture generation function in isolation, but inter-group playoffs and promotion to parent tiers are not tested against real league structures.
   - *Why unresolved:* Packaged `data/` lacks multi-group tiers.
   - *Future fix:* Implement and test group playoff resolvers when generating multi-group leagues (e.g. Spain Primera RFEF or Italy Serie C).
6. **Promotion/relegation slots are read from data but only tested for the 3-tier synthetic case:**
   - *Limitation:* Multi-tier promotion/relegation was tested with synthetic 4-team tiers using symmetric 1-up/1-down slots.
   - *Why unresolved:* Real-world pyramids feature varying tier sizes and asymmetric quotas.
   - *Future fix:* Add parameterized unit tests verifying asymmetrical promotion/relegation quotas and multi-team boundaries.
7. **`data/players.json` parity with `league.json` holds for current 16-team file; no test covers sharded manifests:**
   - *Limitation:* `tools/verify_db.py` checks flat `data/players.json` vs `data/league.json`; it has no awareness of sharded division files.
   - *Why unresolved:* Sharded manifests were designed for `data/generated/`, which will be populated in Phase 1.
   - *Future fix:* Extend `tools/verify_db.py` to detect manifest files and crawl division shards.

---

## 4. How to run the tests

### Test Invocation
```bash
godot --headless tests/TestRunner.tscn
```

### Test Suite Assertions (`tests/run_all.gd`)
- `_test_p3_no_legacy_references`: Asserts `play_next_fixture` and `record_user_match_result` methods are absent from `CareerManager`.
- `_test_p1_cup_byes`: Asserts tournament cup preliminary bye seeding resolves correctly for non-power-of-two team counts (3, 5, 6, 7, 10, 15, 20, 60) down to a single winner.
- `_test_p1_synthetic_leagues`: Asserts fixture generation for 8-team, 20-team, 3-group (60 teams), and 10-tier (200 teams) configurations adheres to calendar fixture limits ($\le 500$).
- `_test_p1_matchday_spacing_and_capping`: Asserts `max_rounds_cap` bounds total rounds and fixtures on a 190-team division to $\le 500$ matches.
- `_test_p1_promotion_relegation_multitier`: Asserts 3-tier promotion and relegation correctly swaps clubs across tier boundaries and preserves existing career state.
- `_test_p2_sharded_league_loading`: Asserts backward compatibility with `data/league.json`, successful parsing of sharded manifests into division metadata, and slot allocation for lazy shard loading.
- `_test_p4_quick_match_isolation`: Asserts `QuickSimEngine.simulate_match` resolves exhibition fixtures without modifying or creating `CareerManager.career`.

---

## 5. Manual test scripts

### Script A: Quick Match Flow & State Isolation
1. Launch the game: run Godot and press F5 (or execute `godot`).
2. On `MainMenu`, click **Quick Match**.
3. Confirm the Quick Match exhibition dialog appears with home and away team pickers.
4. Select any two clubs and click **Play Match**.
5. Observe the match simulation result dialog displaying the scoreline, goalscorers, and match statistics.
6. Click **Close** to return to the main menu.
7. Exit the game.
8. Inspect the filesystem: verify no files were created or modified under `~/.local/share/godot/app_userdata/PowerFootball 2D/career/` or `user://career_slot*.json`.

### Script B: Custom League Ingestion
1. Prepare a custom league JSON file (e.g. `/tmp/my_league.json`).
2. Launch the game: run Godot and press F5.
3. On `MainMenu`, click **Options**.
4. In the options menu, click **Load Custom League**.
5. In the file dialog, navigate to and select `/tmp/my_league.json`, then confirm.
6. Observe status confirmation indicating the league file was ingested into `user://custom_league.json`.
7. Click **Back** to return to `MainMenu`.
8. Click **Quick Match** and inspect the team dropdown lists.
9. Verify the clubs listed match the teams defined in `/tmp/my_league.json`.

---

## 6. Appendix — Raw Outputs

### `python3 tools/verify_db.py`
```
=== PowerFootball 2D Database Verification ===
[OK] League verified: 16 teams, 288 players total across squads.
[OK] Flat players database verified: 288 records in parity with league.json.
[OK] Managers verified: 18 managers (16 club-assigned, 2 free agents).
[OK] Referees verified: 8 referees with personality spectrums, bios, and career stats.
[OK] Staff database verified: 84 staff members across clubs and free agents.
=== All Verification Checks Passed (0 errors, 0 warnings) ===
```

### `python3 tools/validate_schemas.py`
```
validate_schemas: All database schemas (league, managers, referees) verified successfully with 0 errors.
```

### `godot --headless tests/TestRunner.tscn`
```
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org

==================================================================
       POWERFOOTBALL-2D HEADLESS REGRESSION TEST RUNNER          
==================================================================
[PASS] P3: play_next_fixture removed from CareerManager
[PASS] P3: record_user_match_result removed from CareerManager
[PASS] P1: Tournament cup bye seeding handles non-power-of-two team counts (3, 5, 6, 7, 10, 15, 20, 60)
[PASS] P1: 8-team league produces exactly 56 fixtures (double round-robin)
[PASS] P1: 20-team league produces 380 fixtures (<= 500)
[PASS] P1: 60 teams across 3 groups of 20 produce 380 fixtures per group (all <= 500)
[PASS] P1: 200 teams across 10 tiers of 20 produce 380 fixtures per tier (all <= 500)
[PASS] P1: 190-team division capped to <= 500 fixtures (max_rounds_cap enforced)
[PASS] P1: 3-tier promotion & relegation swaps teams across multiple tier boundaries
[PASS] P2: Default data/league.json loads with 100% backward compatibility
WARNING: DataLoader.load_division_shard: shard file 'shards/div1.json' not found on disk.
     at: push_warning (core/variant/variant_utility.cpp:1033)
     GDScript backtrace (most recent call first):
         [0] load_division_shard (res://autoloads/DataLoader.gd:258)
         [1] _parse_json_league (res://autoloads/DataLoader.gd:222)
         [2] _test_p2_sharded_league_loading (res://tests/run_all.gd:228)
         [3] _ready (res://tests/run_all.gd:22)
[PASS] P2: Sharded manifest parsed into active divisions and league stubs
[PASS] P2: Manifest generates 4 team slots across both divisions
[PASS] P2: Division 1 team loaded correctly
[PASS] P2: Division 2 metadata stub loaded correctly
[PASS] P4: QuickSimEngine.simulate_match produces valid exhibition result
[PASS] P4: Quick match simulation does NOT modify or create career state
------------------------------------------------------------------
TOTAL TESTS: 16 passed, 0 failed
==================================================================
```

### Dead Code Grep Output
Command:
```bash
grep -rnE "play_next_fixture|record_user_match_result|_find_pending_fixture" --include="*.gd" --include="*.tscn" --exclude-dir="legacy" .
```
Output:
```
./shared/career/CareerSaveData.gd:85:## Fixture handed to the retired real-time match layer by play_next_fixture(), so
./tests/run_all.gd:44:	_assert_true(not CareerManager.has_method("play_next_fixture"), "P3: play_next_fixture removed from CareerManager")
./tests/run_all.gd:45:	_assert_true(not CareerManager.has_method("record_user_match_result"), "P3: record_user_match_result removed from CareerManager")
```

### Legacy Path Grep Output
Command:
```bash
grep -rnE "res://(pitch|entities)/" --include="*.gd" --include="*.tscn" --exclude-dir="legacy" .
```
Output:
```
(empty — zero matches across all live GDScript and scene files)
```
