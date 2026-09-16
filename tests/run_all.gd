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
	if career_save != null:
		for comp: CompetitionData in career_save.competitions:
			if comp.competition_name == "European Champions Cup":
				has_uefa = true
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

	CareerManager.close_career()
	CareerSerializer.delete_slot(99)
	DataLoader.load_default_database()
