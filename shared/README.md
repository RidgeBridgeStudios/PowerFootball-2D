# shared/ — Data Models & Shared Logic

Data classes, career state, quick-sim logic, and math/data helpers used throughout the codebase. This directory spans the career world (Layer 1), the quick-sim match (Layer 2), and shared tactical data.

## Layer 1 — Career World

### PlayerData.gd

**Contract:** Pure data container for one player: identity, attributes, personality, contract, morale, and career stats. Persists across matches as a `.tres` / JSON resource. Applied to the career and quick-sim paths; there is no real-time entity that consumes physical tuning any more, but the fields remain part of the schema.

**Fields:**
- **Identity:** `player_name: String`, `shirt_number: int`, `position_role: String`, `is_captain: bool`, `nationality: String`, `secondary_nationality: String`, `date_of_birth: String`, `spoken_languages: Array[Dictionary]`
- **Physical:** `mass`, `top_speed`, `acceleration_time`, `friction_time`, `turning_penalty`, `sprint_multiplier`
- **Technical / Mental:** `vision`, `composure`, `aggression`, `formation_ball_weight`, `close_control`, `reflexes`, `determination`, `work_rate`, `leadership`, `temperament`, `professionalism`, `ambition`, `loyalty`, `adaptability`, plus a trait bitmask
- **Contract & Value:** `player_reputation`, `wage_weekly`, `contract_years`, `release_clause`, `squad_status`, `morale`, `market_value`
- **Form & Career Stats:** `form` (default 6.5), `career_goals`, `career_assists`, `career_xg`, `career_xa`, `career_xt_delta`, `career_progressive_passes`, `career_progressive_carries`, `career_packing_count`, `career_vaep`, `career_tackles_won`, `career_interceptions`, `career_clean_sheets`, `career_psxg_prevented`, `last_match_rating`, `is_unavailable`
- **Transient Match Stats:** `yellow_cards_this_match: int`, `red_cards_this_match: int`
- **Methods:** `accumulate_match_stats()`, `apply_role_defaults()`, `has_trait()`, `calculate_overall_rating()`, `calculate_market_value()`, `get_age()`

---

### TeamData.gd

**Contract:** Pure data container for one team: identity, colours, squad, staff, formation, lineup and finances.

**Fields:** `team_name`, `team_color`, `secondary_color`, `gk_color`, `squad: Array[PlayerData]`, `staff: Array[StaffData]`, `formation_override`, `substitutions_made`, `lineup_indices: Array[int]`, `role_overrides`, `captain_index`, `reputation`, `stature`, `transfer_budget`, `wage_budget_weekly`. Methods include `get_weekly_payroll()`, `update_reputation()` and `get_staff_by_role()`.

---

### LeagueData.gd

**Contract:** Top-level league container: `league_name: String` and `teams: Array[TeamData]`. Owned and persisted by `DataLoader`.

---

### ManagerData.gd

**Contract:** Pure data container for one manager: identity, career record, tactical philosophy, squad/signing preferences, personality traits, and board standing.

**Key Fields:** `manager_name`, `nationality`, `date_of_birth`, `experience`, `current_team`, `reputation`, `board_confidence`, `contract_years`, `salary_weekly`, `referee_respect`, tactical sliders (`defensive_line`, `tempo`, `width`, `pressing_intensity`, `physicality`), formations (`preferred_formation`, `attacking_formation`, `defensive_formation`), squad/signing preferences (`youth_trust`, `loyalty_bias`, `form_sensitivity`, age/mass ranges, `budget_flexibility`, …) and personality traits.

---

### RefereeData.gd

**Contract:** Pure data container for one referee: identity, personality, and match-by-match record.

**Fields:** `referee_name`, `nationality`, `experience`, `strictness`, `consistency`, `composure`, `unprofessionalism`, `incoherence`, `reputation`, `respect_rating`, `recent_match_ratings`, `matches_officiated`, `fouls_awarded`, `penalties_awarded`, `red_cards_issued`, `matchup_history`. Methods include `get_fouls_per_match()`, `evaluate_match_performance()` and `make_default()`.

---

### StaffData.gd

**Contract:** Pure data container for one backroom staff member.

**Fields:** `staff_name`, `role`, `team_name`, `nationality`, `date_of_birth`, `experience`, `coaching`, `judging_ability`, `physiotherapy`, `tactical_knowledge`, `salary_weekly`, `contract_years`.

---

### TeamManagementData.gd

**Contract:** Lineup and bench management handler. Built with `from_team(team, manager)`, it validates and swaps between the starting XI and the bench (`swap()`, `reshuffle()`, `apply_to_team()`), tracks `substitutions_used`, slot roles (`get_slot_role()`, `set_slot_role()`), custom per-slot `PlayerRoleConfig` instances and the captain slot.

---

### NationDatabase.gd

**Contract:** Static nationality/language reference data: nation keys, flag emojis, primary languages, and helper builders (`get_flag_key()`, `get_flag_texture()`, `get_flag_emoji()`, `get_primary_language_for_nation()`, `create_nationality_badge()`, `create_language_badge()`).

---

### shared/career/*

The persisted career-state layer: `CareerSaveData` (the single live save object owned by `CareerManager`), `CareerDate`, `CareerSerializer`, `FixtureData`, `CompetitionData`, `LeagueTableRow`, `ClubFinances`, `ContractData`, `InboxEngine`, `InboxItem`, `MoraleEngine`, `PlayerCareerState`, `PlayerDevelopmentEngine`, `RelationshipData`, `ScoutingNetwork`, `ScoutReport`, `TrainingSchedule`, `TransferMarket`, `TransferOffer`, `WorldEvent`, `YouthAcademy`, `BoardState`, `ManagerCareerProfile`, and `CareerThemePalette`.

---

### CareerProgressionEngine.gd

**Contract:** Static match-day progression: `process_matchday_progression()` folds a resolved fixture's per-player ratings and events into `PlayerData` growth and career records.

---

## Layer 2 — Quick-Sim Match

### QuickSimEngine.gd

**Contract:** The match resolver. `simulate_match()` turns two teams, their managers, a referee and optional lineups into a `QuickSimResult` (scoreline, probabilities, events, team stats, advanced stats, per-player events and ratings). `apply_to_match_stats_tracker()` is the single publishing choke point into `GameManager` + `MatchStatsTracker`. Team-strength helpers (`calculate_team_units()`, `get_star_rating_value()`) are also here.

**DO NOT:** write match state anywhere else, or add a second match resolver.

---

### PlayerRatingCalculator.gd

**Contract:** Pure function turning one player's `PlayerMatchEvents` into a 1.0–10.0 rating. `BASE_RATING = 6.70`, `MIN_RATING = 1.0`, `MAX_RATING = 10.0`; a sent-off player is confined to `[5.20, 5.80]`. No state, no signals, no Node.

---

### UtilityMath.gd

**Contract:** Shared analytical math for quick-sim and career analytics: intercept solving (`calculate_intercept_point()`, `solve_pass_intercept()`), lane/segment geometry, decay and sigmoid curves, xG/PSxG/xT models, packing, progressive-action and VAEP helpers.

---

## Shared Tactical Data

### FormationLibrary.gd

**Contract:** Static formation definitions keyed by name (`get_formation(name)`), returning per-slot role and offset dictionaries. Consumed by `TeamManagementData` and the tactics UI.

---

### FormationRegistry.gd

**Contract:** Lightweight registry of available formation names (`all_formations()`) and their normalized slot positions (`positions_for(formation)`).

---

### PlayerRoleConfig.gd

**Contract:** Data-driven role tuning resource (`.tres` presets in `shared/roles/`): `role_name`, `anchor_weight`, `max_chase_distance`, pass utility weights `w_dist` / `w_angle` / `w_press` / `w_adv`, and normalized `pitch_bounds`. Custom per-slot configs are managed through `TeamManagementData`.

**DO NOT:** assume a config is assigned — always guard reads with `if config != null`.
