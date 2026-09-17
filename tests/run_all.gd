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



