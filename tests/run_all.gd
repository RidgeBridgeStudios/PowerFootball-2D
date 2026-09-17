##
## Headless Regression Test Runner for Phase 0 Architectural Fixes (P1-P4)
## Runnable via: godot --headless tests/TestRunner.tscn
##
extends Node

var _passed: int = 0
var _failed: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	print("==================================================================")
	print("       POWERFOOTBALL-2D HEADLESS REGRESSION TEST RUNNER          ")
	print("==================================================================")
	
	_test_p3_no_legacy_references()
	_test_p1_cup_byes()
	_test_p1_synthetic_leagues()
	_test_p1_matchday_spacing_and_capping()
	_test_p1_promotion_relegation_multitier()
	_test_p2_sharded_league_loading()
	_test_p4_quick_match_isolation()
	_test_world_database_and_continental()
	_test_relationship_batching()
	_test_player_manager_relationships_and_sounding_board()
	_test_mutiny_and_crisis_escalation()
	_test_squad_cliques_and_faction_dynamics()
	_test_incident_press_conference_pipeline()
	_test_stadium_expansion_and_infrastructure()

	print("------------------------------------------------------------------")

	print("TOTAL TESTS: %d passed, %d failed" % [_passed, _failed])
	print("==================================================================")
	if _failed > 0:
		get_tree().quit(1)
	else:
		get_tree().quit(0)


func _assert_true(cond: bool, msg: String) -> void:
	if cond:
		_passed += 1
		print("[PASS] %s" % msg)
	else:
		_failed += 1
		printerr("[FAIL] %s" % msg)


func _test_p3_no_legacy_references() -> void:
	_assert_true(not CareerManager.has_method("play_next_fixture"), "P3: play_next_fixture removed from CareerManager")
	_assert_true(not CareerManager.has_method("record_user_match_result"), "P3: record_user_match_result removed from CareerManager")


func _test_p1_cup_byes() -> void:
	var test_counts: Array[int] = [3, 5, 6, 7, 10, 15, 20, 60]
	var all_ok: bool = true
	_rng.seed = 12345

	for count: int in test_counts:
		var indices: Array[int] = []
		for i in range(count):
			indices.append(i)

		var cup: CompetitionData = CompetitionData.build_cup("Test Cup %d" % count, indices, false)
		var start_date: CareerDate = CareerDate.make(2026, 8, 1)
		var rounds_run: int = 0

		while not cup.is_complete() and rounds_run < 15:
			rounds_run += 1
			cup.draw_cup_round(start_date.advanced_by(rounds_run * 14), _rng)
			if cup.fixtures.is_empty() and cup.remaining_indices.size() > 1:
				all_ok = false
				break
			for f: FixtureData in cup.fixtures:
				if f.round_number == cup.current_round and not f.played:
					f.played = true
					f.home_score = 1
					f.away_score = 0
					cup.record_result(f, _rng)
			cup.current_round += 1

		if cup.winner_index == -1 or cup.remaining_indices.size() != 1:
			all_ok = false

	_assert_true(all_ok, "P1: Tournament cup bye seeding handles non-power-of-two team counts (3, 5, 6, 7, 10, 15, 20, 60)")


func _test_p1_synthetic_leagues() -> void:
	var start_date: CareerDate = CareerDate.make(2026, 8, 1)

	var l8_teams: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7]
	var l8_names: Array[String] = ["T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7"]
	var c8: CompetitionData = CompetitionData.build_league("L8", l8_teams, l8_names, 1)
	c8.generate_league_fixtures(start_date, 7, 1)
	_assert_true(c8.fixtures.size() == 56, "P1: 8-team league produces exactly 56 fixtures (double round-robin)")

	var l20_teams: Array[int] = []
	var l20_names: Array[String] = []
	for i in range(20):
		l20_teams.append(i)
		l20_names.append("Team %d" % i)
	var c20: CompetitionData = CompetitionData.build_league("L20", l20_teams, l20_names, 1)
	c20.generate_league_fixtures(start_date, 7, 1)
	_assert_true(c20.fixtures.size() == 380 and c20.fixtures.size() <= 500, "P1: 20-team league produces 380 fixtures (<= 500)")

	var g_ok: bool = true
	for g in range(3):
		var g_teams: Array[int] = []
		var g_names: Array[String] = []
		for i in range(20):
			var g_idx: int = g * 20 + i
			g_teams.append(g_idx)
			g_names.append("Team %d" % g_idx)
		var cg: CompetitionData = CompetitionData.build_league("Group %d" % g, g_teams, g_names, 3, g)
		cg.generate_league_fixtures(start_date, 7, 1)
		if cg.fixtures.size() > 500 or cg.fixtures.size() != 380:
			g_ok = false
	_assert_true(g_ok, "P1: 60 teams across 3 groups of 20 produce 380 fixtures per group (all <= 500)")

	var t_ok: bool = true
	for t in range(1, 11):
		var t_teams: Array[int] = []
		var t_names: Array[String] = []
		for i in range(20):
			var t_idx: int = (t - 1) * 20 + i
			t_teams.append(t_idx)
			t_names.append("Team %d" % t_idx)
		var ct: CompetitionData = CompetitionData.build_league("Tier %d" % t, t_teams, t_names, t)
		ct.generate_league_fixtures(start_date, 7, 1)
		if ct.fixtures.size() > 500 or ct.fixtures.size() != 380:
			t_ok = false
	_assert_true(t_ok, "P1: 200 teams across 10 tiers of 20 produce 380 fixtures per tier (all <= 500)")


func _test_p1_matchday_spacing_and_capping() -> void:
	var big_teams: Array[int] = []
	var big_names: Array[String] = []
	for i in range(190):
		big_teams.append(i)
		big_names.append("Big %d" % i)

	var start_date: CareerDate = CareerDate.make(2026, 8, 1)
	var c_big: CompetitionData = CompetitionData.build_league("Big 190", big_teams, big_names, 1)
	var max_cap: int = 500 / (190 / 2) # max_rounds_cap = 5 rounds
	c_big.generate_league_fixtures(start_date, 3, 1, true, max_cap)
	_assert_true(c_big.total_rounds <= max_cap and c_big.fixtures.size() == max_cap * (190 / 2) and c_big.fixtures.size() <= 500, "P1: 190-team division capped to <= 500 fixtures (max_rounds_cap enforced)")


func _test_p1_promotion_relegation_multitier() -> void:
	var prev_career: CareerSaveData = CareerManager.career
	var prof := ManagerCareerProfile.new()
	prof.manager_name = "Test Manager"
	var save := CareerSaveData.make_new(prof, 2, CareerDate.make(2026, 8, 1), 12345)
	save.tier_indices = [
		[0, 1, 2, 3],
		[4, 5, 6, 7],
		[8, 9, 10, 11]
	]
	save.tier_1_indices = [0, 1, 2, 3]
	save.tier_2_indices = [4, 5, 6, 7]

	var c1: CompetitionData = CompetitionData.build_league("T1", [0, 1, 2, 3], ["A", "B", "C", "D"], 1, -1, 0, 1)
	var c2: CompetitionData = CompetitionData.build_league("T2", [4, 5, 6, 7], ["E", "F", "G", "H"], 2, -1, 1, 1)
	var c3: CompetitionData = CompetitionData.build_league("T3", [8, 9, 10, 11], ["I", "J", "K", "L"], 3, -1, 1, 0)
	save.competitions = [c1, c2, c3]

	c1.row_for(0).points = 10
	c1.row_for(1).points = 8
	c1.row_for(2).points = 6
	c1.row_for(3).points = 1

	c2.row_for(4).points = 12
	c2.row_for(5).points = 7
	c2.row_for(6).points = 5
	c2.row_for(7).points = 2

	c3.row_for(8).points = 15
	c3.row_for(9).points = 6
	c3.row_for(10).points = 4
	c3.row_for(11).points = 1

	CareerManager.career = save
	CareerManager._apply_promotion_relegation()

	var t1_has_4: bool = save.tier_indices[0].has(4) and not save.tier_indices[0].has(3)
	var t2_has_3_and_8: bool = save.tier_indices[1].has(3) and save.tier_indices[1].has(8) and not save.tier_indices[1].has(4) and not save.tier_indices[1].has(7)
	var t3_has_7: bool = save.tier_indices[2].has(7) and not save.tier_indices[2].has(8)

	_assert_true(t1_has_4 and t2_has_3_and_8 and t3_has_7, "P1: 3-tier promotion & relegation swaps teams across multiple tier boundaries")
	CareerManager.career = prev_career


func _test_p2_sharded_league_loading() -> void:
	var flat_ok: bool = DataLoader._parse_json_league("res://data/league.json")
	_assert_true(flat_ok and DataLoader.league.teams.size() == 16 and not DataLoader.manifest_mode, "P2: Default data/league.json loads with 100% backward compatibility")

	var test_manifest: Dictionary = {
		"league_name": "Sharded Test Pyramid",
		"divisions": [
			{
				"name": "Division One",
				"tier_index": 1,
				"group_index": null,
				"team_count": 2,
				"promotion_slots": 0,
				"relegation_slots": 1,
				"shard": "shards/div1.json",
				"teams": [
					{"team_name": "Div1 Alpha", "reputation": 0.8},
					{"team_name": "Div1 Beta", "reputation": 0.75}
				]
			},
			{
				"name": "Division Two",
				"tier_index": 2,
				"group_index": null,
				"team_count": 2,
				"promotion_slots": 1,
				"relegation_slots": 0,
				"shard": "shards/div2.json",
				"teams": [
					{"team_name": "Div2 Gamma", "reputation": 0.5},
					{"team_name": "Div2 Delta", "reputation": 0.45}
				]
			}
		]
	}

	var tmp_path: String = "user://test_manifest.json"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(test_manifest, "	"))
	f.close()

	var manifest_ok: bool = DataLoader._parse_json_league(tmp_path)
	_assert_true(manifest_ok and DataLoader.manifest_mode and DataLoader.divisions.size() == 2, "P2: Sharded manifest parsed into active divisions and league stubs")
	_assert_true(DataLoader.league.teams.size() == 4, "P2: Manifest generates 4 team slots across both divisions")
	_assert_true(DataLoader.league.teams[0].team_name == "Div1 Alpha", "P2: Division 1 team loaded correctly")
	_assert_true(DataLoader.league.teams[2].team_name == "Div2 Gamma", "P2: Division 2 metadata stub loaded correctly")

	DataLoader._parse_json_league("res://data/league.json")


func _test_p4_quick_match_isolation() -> void:
	var initial_career: CareerSaveData = CareerManager.career
	var home: TeamData = DataLoader.get_team(0)
	var away: TeamData = DataLoader.get_team(1)
	var home_mgr: ManagerData = ManagerLoader.get_or_assign_manager(home.team_name)
	var away_mgr: ManagerData = ManagerLoader.get_or_assign_manager(away.team_name)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home.team_name, away.team_name)

	var result: QuickSimEngine.QuickSimResult = QuickSimEngine.simulate_match(
		home, away, home_mgr, away_mgr, ref, home.lineup_indices, away.lineup_indices
	)

	_assert_true(result != null and result.home_score >= 0 and result.away_score >= 0, "P4: QuickSimEngine.simulate_match produces valid exhibition result")
	_assert_true(CareerManager.career == initial_career, "P4: Quick match simulation does NOT modify or create career state")


func _test_world_database_and_continental() -> void:
	var ok: bool = DataLoader.load_world_database()
	_assert_true(ok and DataLoader.manifest_mode and DataLoader.divisions.size() == 20, "World DB: 20 divisions loaded from manifest")
	_assert_true(DataLoader.league.teams.size() == 372, "World DB: 372 total clubs indexed in league stubs")

	var shard_ok: bool = DataLoader.load_division_shard(DataLoader.divisions[0])
	_assert_true(shard_ok, "World DB: Division 0 shard loaded successfully")
	var team0: TeamData = DataLoader.get_team(0)
	_assert_true(team0 != null and team0.squad.size() >= 18, "World DB: Team 0 has full 18-player squad")
	_assert_true(team0.squad[0].position_role == "GK", "World DB: Starter index 0 is GK")
	_assert_true(team0.lineup_indices.size() == 11, "World DB: Team 0 has 11-player starting lineup")

	var dummy_profile := ManagerCareerProfile.new()
	dummy_profile.manager_name = "Test Manager"
	dummy_profile.tactical = ManagerData.new()
	dummy_profile.tactical.manager_name = "Test Manager"
	var career_save: CareerSaveData = CareerManager.start_new_career(dummy_profile, 0, 99)
	_assert_true(career_save != null, "World DB: CareerManager.start_new_career succeeds in world DB mode")

	var has_uefa: bool = false
	var has_americas: bool = false
	var has_world_club: bool = false
	var has_domestic_cup: bool = false
	var uefa_comp: CompetitionData = null
	if career_save != null:
		for comp: CompetitionData in career_save.competitions:
			if comp.competition_name == "European Champions Cup":
				has_uefa = true
				uefa_comp = comp
			elif comp.competition_name == "Copa Continental":
				has_americas = true
			elif comp.competition_name == "World Club Championship":
				has_world_club = true
			elif comp.kind == CompetitionData.Kind.KNOCKOUT_CUP:
				has_domestic_cup = true

	_assert_true(has_uefa, "World DB: European Champions Cup generated")
	_assert_true(has_americas, "World DB: Copa Continental generated")
	_assert_true(has_world_club, "World DB: World Club Championship generated")
	_assert_true(has_domestic_cup, "World DB: Division Domestic Cup generated")

	# Continental Multi-stage verification
	if uefa_comp != null:
		_assert_true(uefa_comp.stage == CompetitionData.Stage.GROUP_STAGE, "Continental: Stage is GROUP_STAGE")
		_assert_true(uefa_comp.group_tables.size() > 0, "Continental: Has group tables")
		var sorted_g: Array[LeagueTableRow] = uefa_comp.sorted_group_table(0)
		_assert_true(sorted_g.size() >= 2, "Continental: Group table has teams")
		# Verify serialization of multi-stage state
		var saved_ok: bool = CareerSerializer.save_to_slot(career_save, 99)
		_assert_true(saved_ok, "Continental: Saved career with multi-stage continental")
		var loaded: CareerSaveData = CareerSerializer.load_from_slot(99)
		_assert_true(loaded != null, "Continental: Loaded career slot 99")
		var loaded_uefa: CompetitionData = null
		for c_l: CompetitionData in loaded.competitions:
			if c_l.competition_name == "European Champions Cup":
				loaded_uefa = c_l
				break
		_assert_true(loaded_uefa != null and loaded_uefa.stage == CompetitionData.Stage.GROUP_STAGE, "Continental: Loaded stage matches")
		_assert_true(loaded_uefa.group_tables.size() == uefa_comp.group_tables.size(), "Continental: Loaded group tables count matches")

	CareerManager.close_career()
	CareerSerializer.delete_slot(99)
	DataLoader.load_default_database()


func _test_relationship_batching() -> void:
	# 1. Direct micro-event unit test on RelationshipData
	var rel := RelationshipData.neutral(100)
	var initial_trust: float = rel.trust # 0.5
	# 10 passes completed: delta = 10 * 0.01 = 0.10, but capped at PASS_COMPLETION_TRUST_CAP (0.05)
	rel.batch_match_micro_events(10, 0, 0, 0, false, false, false, 100)
	_assert_true(is_equal_approx(rel.trust, initial_trust + 0.05), "RelBatch: pass completions trust capped at +0.05")

	# Assists: +0.04 for assist_from, +0.03 for assist_to
	var rel2 := RelationshipData.neutral(100)
	rel2.batch_match_micro_events(0, 0, 1, 1, false, false, false, 100)
	_assert_true(is_equal_approx(rel2.trust, 0.5 + 0.07), "RelBatch: assists adjust trust (+0.07)")

	# Red card: rivalry +0.05, trust -0.03
	var rel3 := RelationshipData.neutral(100)
	rel3.batch_match_micro_events(0, 0, 0, 0, true, false, false, 100)
	_assert_true(is_equal_approx(rel3.rivalry_score, 0.05) and is_equal_approx(rel3.trust, 0.47), "RelBatch: teammate red card adds rivalry and penalizes trust")

	# 2. No-op when career is null
	var dummy_fixture := FixtureData.new()
	dummy_fixture.home_team_index = 0
	dummy_fixture.away_team_index = 1
	dummy_fixture.home_score = 1
	dummy_fixture.away_score = 0
	CareerManager.career = null
	# Must safely no-op without crashing
	CareerManager._apply_fixture_result(dummy_fixture, {}, {})
	_assert_true(CareerManager.career == null, "RelBatch: _apply_fixture_result no-ops when career is null")

	# 3. End-to-end career fixture simulation batches relationships
	var dummy_profile := ManagerCareerProfile.new()
	dummy_profile.manager_name = "Test Manager"
	dummy_profile.tactical = ManagerData.new()
	dummy_profile.tactical.manager_name = "Test Manager"
	var cs: CareerSaveData = CareerManager.start_new_career(dummy_profile, 0, 98)

	if cs != null:
		var home_team: TeamData = DataLoader.get_team(0)
		var p0_sq: int = home_team.lineup_indices[0]
		var p1_sq: int = home_team.lineup_indices[1]
		var p0_state: PlayerCareerState = cs.state_for_squad(0, p0_sq)
		var rel_before: RelationshipData = p0_state.relationship_with(p1_sq, cs.today.to_ordinal())
		var initial_last: int = rel_before.last_interaction_ordinal

		var f: FixtureData = CareerManager.simulate_next_fixture()
		_assert_true(f != null, "RelBatch: CareerManager simulated next fixture")
		var rel_after: RelationshipData = p0_state.relationship_with(p1_sq, cs.today.to_ordinal())
		_assert_true(rel_after.last_interaction_ordinal >= initial_last, "RelBatch: relationship last_interaction_ordinal updated after fixture")

		CareerManager.close_career()
		CareerSerializer.delete_slot(98)
		DataLoader.load_default_database()


func _test_player_manager_relationships_and_sounding_board() -> void:
	# 1. Key convention and predicates
	var team_idx: int = 5
	var mgr_key: int = RelationshipData.manager_relationship_key(team_idx)
	_assert_true(mgr_key == 100005, "MgrRel: manager_relationship_key(5) == 100005")
	_assert_true(RelationshipData.is_manager_key(mgr_key), "MgrRel: is_manager_key(100005) is true")
	_assert_true(not RelationshipData.is_manager_key(5012), "MgrRel: is_manager_key(5012) is false")

	# 2. PlayerCareerState manager relationship initialization and sync
	var state := PlayerCareerState.new()
	state.manager_trust = 0.65
	var rel: RelationshipData = state.manager_relationship(team_idx, 50)
	_assert_true(rel != null, "MgrRel: state.manager_relationship creates edge")
	_assert_true(is_equal_approx(rel.trust, 0.65), "MgrRel: fresh edge inherits manager_trust")

	state.adjust_manager_trust(-0.15, "left out of the squad", team_idx, 51)
	_assert_true(is_equal_approx(rel.trust, 0.50), "MgrRel: adjust_manager_trust updates edge trust")
	_assert_true(is_equal_approx(state.manager_trust, 0.50), "MgrRel: adjust_manager_trust syncs state.manager_trust")

	# 3. Benching resentment scaling by (1.0 - loyalty)
	var low_loyalty: float = 0.20
	var low_loss: float = RelationshipData.BENCHING_RESENTMENT_BASE_TRUST_DELTA * clampf(1.0 - low_loyalty, 0.0, 1.0)
	_assert_true(is_equal_approx(low_loss, -0.048), "MgrRel: low loyalty (0.2) incurs -0.048 trust delta")

	var max_loyalty: float = 1.0
	var zero_loss: float = RelationshipData.BENCHING_RESENTMENT_BASE_TRUST_DELTA * clampf(1.0 - max_loyalty, 0.0, 1.0)
	_assert_true(is_equal_approx(zero_loss, 0.0), "MgrRel: max loyalty (1.0) incurs 0.0 benching resentment")

	# 4. Captain sounding board dialogue generation and resolution
	var captain_data := PlayerData.new()
	captain_data.player_name = "Jordan Henderson"
	captain_data.traits = 64 # CaptainMaterial
	captain_data.is_captain = true
	captain_data.morale = 0.70

	var captain_state := PlayerCareerState.new()
	captain_state.player_key = 12
	captain_state.squad_index = 0
	captain_state.team_index = 0
	captain_state.manager_trust = 0.50

	var today := CareerDate.make(2026, 9, 17)
	var team := TeamData.new()
	team.team_name = "Test FC"
	team.squad = [captain_data]

	var item: InboxItem = InboxEngine.build_captain_sounding_board(captain_data, captain_state, team, today)
	_assert_true(item != null, "SoundingBoard: item created successfully")
	_assert_true(item.requires_decision(), "SoundingBoard: requires decision")
	_assert_true(item.option_count() == 4, "SoundingBoard: has 4 dialogue options")
	_assert_true(String(item.payload.get("kind", "")) == "sounding_board", "SoundingBoard: payload kind is sounding_board")

	var career: CareerSaveData = CareerSaveData.make_new(null, 0, today, 1)
	career.player_states[captain_state.player_key] = captain_state

	# Resolve option 0 (Rally the squad)
	var event: WorldEvent = InboxEngine.resolve(career, item, 0, team, today)
	_assert_true(event != null and item.is_resolved, "SoundingBoard: resolved with WorldEvent")
	_assert_true(captain_state.manager_trust > 0.55, "SoundingBoard: captain trust increased after rally")
	var captain_rel: RelationshipData = captain_state.manager_relationship(0, today.to_ordinal())
	_assert_true(is_equal_approx(captain_rel.trust, captain_state.manager_trust), "SoundingBoard: manager edge trust in sync with manager_trust")


func _test_mutiny_and_crisis_escalation() -> void:
	# 1. Dual condition threshold evaluation
	var team := TeamData.new()
	team.team_name = "Mutiny FC"

	var p_leader := PlayerData.new()
	p_leader.player_name = "Skipper"
	p_leader.traits = WorldEventGenerator.TRAIT_CAPTAIN_MATERIAL
	p_leader.morale = 0.80

	var p_regular := PlayerData.new()
	p_regular.player_name = "Winger"
	p_regular.morale = 0.70

	team.squad = [p_leader, p_regular]

	var today := CareerDate.make(2026, 9, 17)
	var career: CareerSaveData = CareerSaveData.make_new(null, 0, today, 1)

	var st_leader := PlayerCareerState.new()
	st_leader.player_key = 0
	st_leader.squad_index = 0
	st_leader.team_index = 0
	st_leader.manager_trust = 0.60

	var st_regular := PlayerCareerState.new()
	st_regular.player_key = 1
	st_regular.squad_index = 1
	st_regular.team_index = 0
	st_regular.manager_trust = 0.50

	career.player_states[0] = st_leader
	career.player_states[1] = st_regular

	# Baseline: high morale, high trust -> false
	_assert_true(not WorldEventGenerator.check_mutiny_threshold(team, career), "Mutiny: healthy squad does not trigger threshold")

	# Case A: low squad morale (< 0.35), but leader trust healthy (>= 0.30) -> false
	p_leader.morale = 0.20
	p_regular.morale = 0.20
	st_leader.manager_trust = 0.50
	_assert_true(not WorldEventGenerator.check_mutiny_threshold(team, career), "Mutiny: low morale alone with healthy leader trust does not trigger")

	# Case B: healthy squad morale (>= 0.35), but leader trust low (< 0.30) -> false
	p_leader.morale = 0.80
	p_regular.morale = 0.80
	st_leader.manager_trust = 0.15
	_assert_true(not WorldEventGenerator.check_mutiny_threshold(team, career), "Mutiny: low leader trust alone with healthy squad morale does not trigger")

	# Case C: low squad morale (< 0.35) AND leader trust low (< 0.30) -> true!
	p_leader.morale = 0.20
	p_regular.morale = 0.20
	st_leader.manager_trust = 0.15
	_assert_true(WorldEventGenerator.check_mutiny_threshold(team, career), "Mutiny: dual condition strictly met triggers mutiny threshold")

	# 2. Squad leader detection
	var leaders: Array[PlayerData] = WorldEventGenerator.get_squad_leaders(team)
	_assert_true(leaders.size() == 1 and leaders[0].player_name == "Skipper", "Mutiny: squad leaders correctly identified")

	# 3. InboxItem builders and non-closure options
	var warn_item: InboxItem = InboxEngine.build_mutiny_warning(team, today)
	_assert_true(warn_item != null and warn_item.priority >= 0.90, "Mutiny: warning inbox item generated with high priority")
	_assert_true(warn_item.option_count() == 3, "Mutiny: warning item provides 3 tactical manager choices")
	_assert_true(String(warn_item.payload.get("kind", "")) == "mutiny_warning", "Mutiny: payload kind is mutiny_warning")

	var board_item: InboxItem = InboxEngine.build_mutiny_board_ultimatum(team, career.board, today)
	_assert_true(board_item != null and board_item.priority == 1.0, "Mutiny: board ultimatum has priority 1.0")
	_assert_true(board_item.category == InboxItem.Category.BOARD, "Mutiny: board ultimatum is in Category.BOARD")

	# 4. Action resolution effects
	var initial_trust: float = st_leader.manager_trust
	var res_event: WorldEvent = InboxEngine.resolve(career, warn_item, 0, team, today) # Concede option
	_assert_true(res_event != null and warn_item.is_resolved, "Mutiny: warning option resolved into WorldEvent")
	_assert_true(st_leader.manager_trust > initial_trust, "Mutiny: conceding to mutiny leaders increases leader trust")
	_assert_true(p_leader.morale > 0.20, "Mutiny: conceding increases squad morale")

	# 5. BoardState crisis intervention
	career.board = BoardState.make_for_club(team, 25000)
	var board: BoardState = career.board
	_assert_true(board != null, "Mutiny: career board exists")
	var conf_before: float = board.confidence
	board.trigger_board_intervention("Full dressing room mutiny", 0.20)
	_assert_true(board.board_intervention_active, "Mutiny: board_intervention_active is set")
	_assert_true(board.confidence < conf_before, "Mutiny: board confidence drops on intervention")
	_assert_true(not board.patience_notes.is_empty(), "Mutiny: intervention reason logged in patience_notes")

	board.clear_board_intervention()
	_assert_true(not board.board_intervention_active, "Mutiny: clear_board_intervention resets active flag")

	# 6. Serialization round-trip for board_intervention_active
	board.board_intervention_active = true
	var serialized: Dictionary = CareerSerializer._board_to_dict(board)
	_assert_true(bool(serialized.get("board_intervention_active", false)) == true, "Mutiny: board_intervention_active serialized")
	var deserialized: BoardState = CareerSerializer._board_from_dict(serialized)
	_assert_true(deserialized.board_intervention_active, "Mutiny: board_intervention_active deserialized")


func _test_squad_cliques_and_faction_dynamics() -> void:
	# 1. Mutual trust clique edge testing
	var r_ab := RelationshipData.new()
	var r_ba := RelationshipData.new()
	r_ab.trust = 0.80
	r_ba.trust = 0.75
	_assert_true(RelationshipData.is_mutual_trust_clique(r_ab, r_ba), "Clique: mutual trust >= 0.70 passes clique threshold")
	r_ba.trust = 0.50
	_assert_true(not RelationshipData.is_mutual_trust_clique(r_ab, r_ba), "Clique: one-way trust fails mutual clique threshold")

	# 2. NationDatabase nationality and language sharing
	_assert_true(NationDatabase.share_nationality("Norwegian", "Norway"), "Clique: shared nationality recognized")
	_assert_true(not NationDatabase.share_nationality("Norwegian", "Sweden"), "Clique: different nationality recognized")
	_assert_true(NationDatabase.share_language("England", "USA"), "Clique: shared language English recognized across nations")
	_assert_true(NationDatabase.share_language("Spain", "Argentina"), "Clique: shared language Spanish recognized across nations")
	_assert_true(not NationDatabase.share_language("England", "France"), "Clique: distinct languages recognized")

	# 3. Pairwise social affinity calculation
	var p0 := PlayerData.new()
	p0.nationality = "Spain"
	p0.player_reputation = 0.85
	p0.traits = 64 # CaptainMaterial
	p0.morale = 0.70

	var p1 := PlayerData.new()
	p1.nationality = "Spain"
	p1.player_reputation = 0.60
	p1.morale = 0.70

	var st0 := PlayerCareerState.new()
	st0.player_key = 0
	st0.squad_index = 0
	st0.team_index = 0
	st0.manager_trust = 0.20

	var st1 := PlayerCareerState.new()
	st1.player_key = 1
	st1.squad_index = 1
	st1.team_index = 0
	st1.manager_trust = 0.15

	var rel01 := RelationshipData.new()
	rel01.trust = 0.65
	var rel10 := RelationshipData.new()
	rel10.trust = 0.65
	st0.relationships[1] = rel01
	st1.relationships[0] = rel10

	var affinity_01: float = MoraleEngine.calculate_social_affinity(p0, st0, p1, st1, 0, 1)
	_assert_true(affinity_01 >= 0.75, "Clique: affinity boosts above 0.70 from shared nationality and manager resentment")

	# 4. Bitmask Bron-Kerbosch Clique Detection
	var team := TeamData.new()
	team.team_name = "Faction FC"

	var p2 := PlayerData.new()
	p2.nationality = "Spain"
	p2.player_reputation = 0.70
	p2.morale = 0.70

	var st2 := PlayerCareerState.new()
	st2.player_key = 2
	st2.squad_index = 2
	st2.team_index = 0
	st2.manager_trust = 0.25

	var rel02 := RelationshipData.new()
	rel02.trust = 0.75
	var rel20 := RelationshipData.new()
	rel20.trust = 0.75
	st0.relationships[2] = rel02
	st2.relationships[0] = rel20

	var rel12 := RelationshipData.new()
	rel12.trust = 0.70
	var rel21 := RelationshipData.new()
	rel21.trust = 0.70
	st1.relationships[2] = rel12
	st2.relationships[1] = rel21

	# French sub-clique (players 3, 4, 5)
	var p3 := PlayerData.new()
	p3.nationality = "France"
	p3.traits = 512 # VeteranLeader
	p3.player_reputation = 0.80
	p3.morale = 0.85

	var p4 := PlayerData.new()
	p4.nationality = "France"
	p4.morale = 0.85

	var p5 := PlayerData.new()
	p5.nationality = "France"
	p5.traits = 4 # PressureImmune
	p5.morale = 0.85

	var st3 := PlayerCareerState.new()
	st3.player_key = 3
	st3.squad_index = 3
	st3.team_index = 0

	var st4 := PlayerCareerState.new()
	st4.player_key = 4
	st4.squad_index = 4
	st4.team_index = 0

	var st5 := PlayerCareerState.new()
	st5.player_key = 5
	st5.squad_index = 5
	st5.team_index = 0

	var rel34 := RelationshipData.new()
	rel34.trust = 0.80
	var rel43 := RelationshipData.new()
	rel43.trust = 0.80
	st3.relationships[4] = rel34
	st4.relationships[3] = rel43

	var rel35 := RelationshipData.new()
	rel35.trust = 0.80
	var rel53 := RelationshipData.new()
	rel53.trust = 0.80
	st3.relationships[5] = rel35
	st5.relationships[3] = rel53

	var rel45 := RelationshipData.new()
	rel45.trust = 0.80
	var rel54 := RelationshipData.new()
	rel54.trust = 0.80
	st4.relationships[5] = rel45
	st5.relationships[4] = rel54

	team.squad = [p0, p1, p2, p3, p4, p5]

	var today := CareerDate.make(2026, 9, 18)
	var career: CareerSaveData = CareerSaveData.make_new(null, 0, today, 1)
	career.player_states[0] = st0
	career.player_states[1] = st1
	career.player_states[2] = st2
	career.player_states[3] = st3
	career.player_states[4] = st4
	career.player_states[5] = st5

	var cliques: Array[PackedInt32Array] = MoraleEngine.detect_squad_cliques(team, career)
	_assert_true(cliques.size() == 2, "Clique: Bron-Kerbosch identifies exactly 2 disjoint cliques of size 3")

	# 5. Faction leader detection
	var leader_c1: int = MoraleEngine.get_clique_leader(team, career, cliques[0])
	var leader_c2: int = MoraleEngine.get_clique_leader(team, career, cliques[1])
	_assert_true(leader_c1 == 0 or leader_c1 == 3, "Clique: leader identified for clique 1")
	_assert_true(leader_c2 == 0 or leader_c2 == 3, "Clique: leader identified for clique 2")
	_assert_true(leader_c1 != leader_c2, "Clique: two distinct leaders identified for opposing cliques")

	# 6. Peer diffusion with numerical damping
	p0.morale = 0.10
	var initial_m1: float = p1.morale
	MoraleEngine.propagate_clique_morale(team, career)
	_assert_true(p1.morale < initial_m1, "Diffusion: member morale drops following leader swing")
	_assert_true(p1.morale >= initial_m1 - MoraleEngine.MAX_DIFFUSION_STEP, "Diffusion: member drop capped by MAX_DIFFUSION_STEP")
	_assert_true(p1.morale >= 0.0 and p1.morale <= 1.0, "Diffusion: morale bounded within [0.0, 1.0]")

	# 7. Trait susceptibility damping
	p3.morale = 0.50
	p4.morale = 0.80
	p5.morale = 0.80
	MoraleEngine.propagate_clique_morale(team, career)
	var drop_normal: float = 0.80 - p4.morale
	var drop_immune: float = 0.80 - p5.morale
	_assert_true(drop_immune < drop_normal, "Diffusion: PressureImmune trait dampens peer contagion")

	# 8. Multi-step numerical stability & feedback loop prevention
	for _step in range(25):
		MoraleEngine.propagate_clique_morale(team, career)
	for p: PlayerData in team.squad:
		_assert_true(p.morale >= 0.0 and p.morale <= 1.0, "Stability: all squad morale strictly in [0.0, 1.0] after 25 diffusion steps")


func _test_incident_press_conference_pipeline() -> void:
	# 1. Question generation citing player name, event tag, and sentiment
	var q_train: String = PressOffice.generate_incident_question(
		&"training_incident", "Marcus Cole", -0.35, false, "North United"
	)
	_assert_true(q_train.contains("Marcus Cole"), "PressOffice: Question cites primary player name")
	_assert_true(q_train.contains("training ground clash"), "PressOffice: Question cites training clash context")
	_assert_true(q_train.contains("North United"), "PressOffice: Pre-match question cites opponent")

	var q_party: String = PressOffice.generate_incident_question(
		&"nightlife_incident", "Leo Vance", -0.40, true, "South City"
	)
	_assert_true(q_party.contains("Leo Vance"), "PressOffice: Question cites nightlife player name")
	_assert_true(q_party.contains("partying"), "PressOffice: Question cites partying incident")
	_assert_true(q_party.contains("Following today's match"), "PressOffice: Post-match question cites timing")

	var q_mutiny: String = PressOffice.generate_incident_question(
		&"mutiny_warning", "Senior Captain", -0.85, false, "Rival FC"
	)
	_assert_true(q_mutiny.contains("Senior Captain") and q_mutiny.contains("mutiny"), "PressOffice: Mutiny question cites mutiny and leader")

	# 2. Quote generation with trait influences
	var mgr := ManagerData.new()
	mgr.traits = 16 # Disciplinarian
	var ctx := PressOffice.PressContext.new()
	ctx.event = "incident_reaction"
	ctx.player_name = "Marcus Cole"
	ctx.match_result = "discipline"
	var quote_disc: String = PressOffice.new().generate_quote(mgr, ctx)
	_assert_true(quote_disc.contains("Marcus Cole"), "PressOffice: Quote cites player name")
	_assert_true(quote_disc.contains("Accountability matters"), "PressOffice: Disciplinarian trait appends accountability")

	mgr.traits = 128 # MediaSavvy
	var quote_media: String = PressOffice.new().generate_quote(mgr, ctx)
	_assert_true(quote_media.contains("internally through the appropriate channels"), "PressOffice: MediaSavvy replaces quote")

	# 3. Build incident press conference item
	var today := CareerDate.make(2026, 9, 18)
	var ev: WorldEvent = WorldEvent.make(
		&"training_incident", WorldEvent.Category.TRAINING, today, "Training bust up", -0.30, 0.65
	).with_player(1000, "Marcus Cole")

	var item: InboxItem = InboxEngine.build_incident_press_conference(ev, false, today, "North United")
	_assert_true(item != null, "InboxEngine: build_incident_press_conference creates item")
	_assert_true(item.subject_player_name == "Marcus Cole", "InboxEngine: Item cites subject player name")
	_assert_true(item.option_count() == 3, "InboxEngine: Item has 3 distinct response options")

	# 4. Resolve options and assert effects on player trust and board confidence
	var p := PlayerData.new()
	p.player_name = "Marcus Cole"
	p.morale = 0.50
	var team := TeamData.new()
	team.team_name = "Test FC"
	team.squad = [p]

	var state := PlayerCareerState.new()
	state.player_key = 1000
	state.manager_trust = 0.50
	state.squad_index = 0
	state.team_index = 1

	var career := CareerSaveData.make_new(null, 1, today, 1)
	career.player_states[1000] = state
	career.board = BoardState.new()
	career.board.confidence = 0.60
	career.profile = ManagerCareerProfile.new()

	# Option 0: Defend player
	var init_trust: float = state.manager_trust
	var init_board: float = career.board.confidence
	var res_ev0: WorldEvent = InboxEngine.resolve(career, item, 0, team, today)
	_assert_true(res_ev0 != null, "InboxEngine: Resolving defend option succeeds")
	_assert_true(state.manager_trust > init_trust, "InboxEngine: Defending player raises player trust")
	_assert_true(career.board.confidence < init_board, "InboxEngine: Defending player under negative incident risks board confidence")

	# Option 1: Discipline player
	var item2: InboxItem = InboxEngine.build_incident_press_conference(ev, false, today, "North United")
	var pre_disc_trust: float = state.manager_trust
	var pre_disc_board: float = career.board.confidence
	var res_ev1: WorldEvent = InboxEngine.resolve(career, item2, 1, team, today)
	_assert_true(res_ev1 != null, "InboxEngine: Resolving discipline option succeeds")
	_assert_true(state.manager_trust < pre_disc_trust, "InboxEngine: Disciplining player publicly reduces player trust")
	_assert_true(career.board.confidence > pre_disc_board, "InboxEngine: Disciplining player publicly raises board confidence")

	# 5. CareerManager incident dispatch
	CareerManager.career = career
	WorldEventLog.bind(career)
	WorldEventLog.clear()
	var unhandled_ev: WorldEvent = WorldEvent.make(
		&"nightlife_incident", WorldEvent.Category.PERSONAL_LIFE, today, "Late night partying", -0.40, 0.70
	).with_player(1000, "Marcus Cole")
	WorldEventLog.log_event(unhandled_ev)

	var dispatched: Array[InboxItem] = CareerManager.check_and_dispatch_incident_press_conferences(false, "Rival FC")
	_assert_true(not dispatched.is_empty(), "CareerManager: Unhandled incident dispatched to press conference")
	_assert_true(dispatched[0].subject_player_name == "Marcus Cole", "CareerManager: Dispatched conference targets incident player")


func _test_stadium_expansion_and_infrastructure() -> void:
	var today: CareerDate = CareerDate.make(2026, 8, 1)
	var team: TeamData = TeamData.new()
	team.team_name = "Infrastructure FC"
	team.reputation = 0.75
	team.transfer_budget = 10_000_000
	team.wage_budget_weekly = 150_000

	var fin: ClubFinances = ClubFinances.from_team(team, 20000)
	var board: BoardState = BoardState.new()
	board.club_name = team.team_name
	board.stadium_capacity = 20000
	board.confidence = 0.70
	board.training_facilities = 2
	board.youth_facilities = 2
	board.medical_facility = 2

	# 1. Verification of default status
	_assert_true(not fin.is_expansion_underway(), "Finances: No expansion underway initially")
	_assert_true(not fin.is_facility_upgrade_underway(), "Finances: No facility upgrade underway initially")

	# 2. Gate receipts scaling with capacity
	var gate_initial: int = fin.book_matchday(team.reputation, 0.5)
	_assert_true(gate_initial > 0, "Finances: Initial matchday gate receipt booked")

	# 3. Board confidence reaction to financial health
	var conf_before: float = board.confidence
	board.apply_financial_health(-2_000_000, fin.wage_budget_weekly)
	_assert_true(board.confidence < conf_before, "BoardState: Severe debt reduces board confidence")

	var conf_debt: float = board.confidence
	board.apply_financial_health(10_000_000, fin.wage_budget_weekly)
	_assert_true(board.confidence > conf_debt, "BoardState: Strong positive balance boosts board confidence")

	# 4. CareerManager setup for request & construction testing
	var career := CareerSaveData.make_new(null, 0, today, 0)
	career.club_finances = {0: fin}
	career.board = board
	CareerManager.career = career
	WorldEventLog.bind(career)
	CareerManager._rng.seed = 42
	board.confidence = 1.0
	board.trajectory = 1.0

	# Request stadium expansion with high balance -> lump sum expense
	fin.balance = 25_000_000
	var initial_balance: int = fin.balance
	CareerManager.file_board_request(BoardState.RequestKind.STADIUM_EXPANSION)

	_assert_true(fin.is_expansion_underway(), "CareerManager: Stadium expansion underway after request approved")
	_assert_true(fin.stadium_expansion_capacity > 0, "CareerManager: Expansion capacity tracked")
	_assert_true(fin.expansion_cost > 0, "CareerManager: Expansion cost tracked")
	_assert_true(fin.expansion_completion_date != null, "CareerManager: Expansion completion date set")
	_assert_true(fin.balance < initial_balance, "CareerManager: Capital expense deducted from balance")

	var added_cap: int = fin.stadium_expansion_capacity
	# Advance day until completion
	career.today = fin.expansion_completion_date.advanced_by(1)
	CareerManager._process_infrastructure_construction()

	_assert_true(fin.stadium_capacity == 20000 + added_cap, "CareerManager: Stadium capacity increased upon completion")
	_assert_true(board.stadium_capacity == fin.stadium_capacity, "CareerManager: Board stadium capacity synchronized")
	_assert_true(not fin.is_expansion_underway(), "CareerManager: Expansion flags cleared upon completion")

	# Matchday gate receipt with new expanded capacity
	fin.reset_season_ledger()
	var gate_expanded: int = fin.book_matchday(team.reputation, 0.5)
	_assert_true(gate_expanded > gate_initial, "Finances: Gate receipts accurately scaled with expanded capacity")

	# 5. Facility upgrade flow
	_assert_true(board.training_facilities == 2, "BoardState: Initial training facility tier is 2")
	fin.balance = 20_000_000
	board.confidence = 1.0
	board.trajectory = 1.0
	CareerManager._rng.seed = 42
	var pre_fac_balance: int = fin.balance
	CareerManager.file_board_request(BoardState.RequestKind.TRAINING_FACILITIES)

	_assert_true(fin.is_facility_upgrade_underway(int(BoardState.RequestKind.TRAINING_FACILITIES)), "CareerManager: Facility upgrade underway")
	_assert_true(fin.facility_upgrade_cost > 0, "CareerManager: Facility upgrade cost tracked")
	_assert_true(fin.balance < pre_fac_balance, "CareerManager: Facility upgrade cost deducted")

	career.today = fin.facility_upgrade_completion_date.advanced_by(1)
	CareerManager._process_infrastructure_construction()

	_assert_true(board.training_facilities == 3, "CareerManager: Training facility tier upgraded to 3 upon completion")
	_assert_true(not fin.is_facility_upgrade_underway(), "CareerManager: Facility upgrade flags cleared upon completion")
	_assert_true(board.facility_multiplier(board.training_facilities) == 1.0, "BoardState: Facility multiplier accurate for tier 3")

	# 6. Serialization roundtrip
	fin.stadium_expansion_capacity = 3500
	fin.expansion_cost = 2_625_000
	fin.expansion_completion_date = CareerDate.make(2027, 1, 15)
	fin.facility_upgrade_type = int(BoardState.RequestKind.YOUTH_FACILITIES)
	fin.facility_upgrade_cost = 3_750_000
	fin.facility_upgrade_completion_date = CareerDate.make(2027, 2, 20)
	board.medical_facility = 4

	var serialized: Dictionary = CareerSerializer.to_dict(career)
	var deserialized: CareerSaveData = CareerSerializer.from_dict(serialized)

	var d_fin: ClubFinances = deserialized.club_finances.get(0, null) as ClubFinances
	_assert_true(d_fin != null, "Serializer: ClubFinances deserialized")
	_assert_true(d_fin.stadium_expansion_capacity == 3500, "Serializer: stadium_expansion_capacity roundtripped")
	_assert_true(d_fin.expansion_cost == 2_625_000, "Serializer: expansion_cost roundtripped")
	_assert_true(d_fin.expansion_completion_date != null and d_fin.expansion_completion_date.to_iso() == "2027-01-15", "Serializer: expansion_completion_date roundtripped")
	_assert_true(d_fin.facility_upgrade_type == int(BoardState.RequestKind.YOUTH_FACILITIES), "Serializer: facility_upgrade_type roundtripped")
	_assert_true(d_fin.facility_upgrade_cost == 3_750_000, "Serializer: facility_upgrade_cost roundtripped")
	_assert_true(d_fin.facility_upgrade_completion_date != null and d_fin.facility_upgrade_completion_date.to_iso() == "2027-02-20", "Serializer: facility_upgrade_completion_date roundtripped")
	_assert_true(deserialized.board.medical_facility == 4, "Serializer: medical_facility roundtripped")





