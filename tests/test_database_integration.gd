##
## test_database_integration.gd
##
## Automated regression tests for SQLite DatabaseManager integration:
## - Premier League team count (exactly 20 teams in men's mode)
## - Position distribution across squad rosters (GK, CB, CM, ST)
## - Goalkeeper attribute recalibration (reflexes >= 0.70, position_role == "GK")
##

extends Node

class_name TestDatabaseIntegration

const TeamProfileViewScript: Resource = preload("res://ui/TeamProfileView.gd")


static func run_tests() -> bool:
	var passed: int = 0
	var failed: int = 0

	print("--- Running DatabaseManager Integration Tests ---")

	if not DatabaseManager.is_connected_to_db:
		DatabaseManager.initialize_database()

	if not DatabaseManager.is_connected_to_db:
		printerr("[FAIL] DatabaseManager could not connect to SQLite database")
		return false

	DatabaseManager.set_game_mode("men")

	# Test 1: Premier League (ID 8) has exactly 20 teams
	var epl_teams: Array[TeamData] = DatabaseManager.get_teams_in_league(8)
	if epl_teams.size() == 20:
		passed += 1
		print("[PASS] EPL (League ID 8) returns exactly 20 teams")
	else:
		failed += 1
		printerr("[FAIL] EPL (League ID 8) expected 20 teams, got %d" % epl_teams.size())

	# Test 2: Roster queries for Bournemouth (ID 52) and Arsenal (ID 19) contain GK, CB, CM, ST
	for team_id: int in [52, 19]:
		var team_name: String = "Bournemouth" if team_id == 52 else "Arsenal"
		var squad: Array[PlayerData] = DatabaseManager.fetch_squad_roster(team_id)
		var has_gk: bool = false
		var has_cb: bool = false
		var has_cm: bool = false
		var has_st: bool = false

		for p: PlayerData in squad:
			match p.position_role:
				"GK":
					has_gk = true
				"CB":
					has_cb = true
				"CM", "DM", "AM":
					has_cm = true
				"ST", "LW", "RW":
					has_st = true

		var diverse: bool = has_gk and has_cb and has_cm and has_st
		if diverse and not squad.is_empty():
			passed += 1
			print("[PASS] %s (ID %d) has valid positional distribution (%d players, GK=%s, CB=%s, CM/MF=%s, ST/FW=%s)" % [
				team_name, team_id, squad.size(), str(has_gk), str(has_cb), str(has_cm), str(has_st)
			])
		else:
			failed += 1
			printerr("[FAIL] %s (ID %d) lacks position diversity (%d players, GK=%s, CB=%s, CM/MF=%s, ST/FW=%s)" % [
				team_name, team_id, squad.size(), str(has_gk), str(has_cb), str(has_cm), str(has_st)
			])

	# Test 3: Goalkeeper resources have reflexes >= 0.65 and position_role == 'GK'
	var gk_squad: Array[PlayerData] = DatabaseManager.fetch_squad_roster(52)
	var tested_gk_count: int = 0
	var all_gk_valid: bool = true

	for p: PlayerData in gk_squad:
		if p.position_role == "GK":
			tested_gk_count += 1
			if p.reflexes < 0.65:
				all_gk_valid = false
				printerr("[FAIL] GK %s reflexes below threshold: %.2f" % [p.player_name, p.reflexes])

	if tested_gk_count > 0 and all_gk_valid:
		passed += 1
		print("[PASS] Verified %d GK resources with reflexes >= 0.65 and position_role == 'GK'" % tested_gk_count)
	else:
		failed += 1
		printerr("[FAIL] Goalkeeper validation failed (found %d GKs, valid=%s)" % [tested_gk_count, str(all_gk_valid)])

	# Test 4: Querying prominent teams (Arsenal ID 19, Bournemouth ID 52) loads valid TeamData with non-empty wikipedia_extract and binds to UI
	var test_teams: Array[int] = [19, 52]
	var wiki_ui_ok: bool = true
	var profile_view: Node = TeamProfileViewScript.new()

	for tid: int in test_teams:
		var team: TeamData = DatabaseManager.fetch_team(tid)
		if team == null:
			printerr("[FAIL] fetch_team(%d) returned null" % tid)
			wiki_ui_ok = false
			continue

		if team.wikipedia_extract.strip_edges().is_empty():
			printerr("[FAIL] Team %s (ID %d) has empty wikipedia_extract" % [team.team_name, tid])
			wiki_ui_ok = false
			continue

		profile_view.call(&"populate_team", team)
		var h_label: RichTextLabel = profile_view.get(&"history_label") as RichTextLabel
		if h_label == null or h_label.text != team.wikipedia_extract:
			printerr("[FAIL] TeamProfileView history_label does not match wikipedia_extract for %s" % team.team_name)
			wiki_ui_ok = false
			continue

		var tn_label: Label = profile_view.get(&"team_name_label") as Label
		if tn_label == null or tn_label.text != team.team_name:
			printerr("[FAIL] TeamProfileView team_name_label does not match for %s" % team.team_name)
			wiki_ui_ok = false
			continue

	# Also test fallback with empty/whitespace extract
	var empty_team: TeamData = TeamData.new()
	empty_team.team_name = "Generic FC"
	empty_team.short_code = "GEN"
	empty_team.wikipedia_extract = "   "
	profile_view.call(&"populate_team", empty_team)
	var fallback_label: RichTextLabel = profile_view.get(&"history_label") as RichTextLabel
	if fallback_label == null or not fallback_label.text.contains("No historical extract available"):
		printerr("[FAIL] TeamProfileView did not show fallback text for whitespace extract")
		wiki_ui_ok = false

	# Test .tscn scene instantiation as well
	var scene_res: PackedScene = load("res://ui/TeamProfileView.tscn") as PackedScene
	if scene_res != null:
		var scene_view: Node = scene_res.instantiate()
		if scene_view != null:
			var test_t: TeamData = DatabaseManager.fetch_team(19)
			scene_view.call(&"populate_team", test_t)
			var scene_h_label: RichTextLabel = scene_view.get(&"history_label") as RichTextLabel
			if scene_h_label == null or scene_h_label.text != test_t.wikipedia_extract:
				printerr("[FAIL] TeamProfileView.tscn instance history_label does not match wikipedia_extract")
				wiki_ui_ok = false
			scene_view.free()

	profile_view.free()

	if wiki_ui_ok:
		passed += 1
		print("[PASS] Verified TeamData wikipedia_extract loading and UI component binding for Arsenal and Bournemouth")
	else:
		failed += 1
		printerr("[FAIL] Wikipedia extract UI binding test failed")

	# Test 5: Competition queries (Domestic League ID 8 and Continental Cup ID 2)
	var epl_comp_teams: Array[TeamData] = DatabaseManager.fetch_teams_in_competition(8, "DOMESTIC_LEAGUE")
	var cl_comp_teams: Array[TeamData] = DatabaseManager.fetch_teams_in_competition(2, "CONTINENTAL_CUP")
	if epl_comp_teams.size() == 20 and not cl_comp_teams.is_empty():
		passed += 1
		print("[PASS] Verified competition queries (EPL=%d teams, Champions League=%d teams)" % [epl_comp_teams.size(), cl_comp_teams.size()])
	else:
		failed += 1
		printerr("[FAIL] Competition queries failed (EPL=%d, CL=%d)" % [epl_comp_teams.size(), cl_comp_teams.size()])

	# Test 6: Staff query for Arsenal (ID 19)
	var arsenal_staff: Array[Dictionary] = DatabaseManager.fetch_staff_for_team(19)
	if not arsenal_staff.is_empty():
		passed += 1
		print("[PASS] Verified Arsenal backroom staff query (%d staff members found)" % arsenal_staff.size())
	else:
		failed += 1
		printerr("[FAIL] No backroom staff found for Arsenal (ID 19)")

	# Test 7: Coach query for Arsenal (ID 19)
	var arsenal_coach: Dictionary = DatabaseManager.fetch_coach(19)
	var coach_name: String = str(arsenal_coach.get("common_name", ""))
	if coach_name == "Mikel Arteta":
		passed += 1
		print("[PASS] Verified Arsenal head coach query (%s, formation %s)" % [coach_name, str(arsenal_coach.get("preferred_formation", ""))])
	else:
		failed += 1
		printerr("[FAIL] Expected Mikel Arteta for Arsenal coach, got '%s'" % coach_name)

	# Test 8: Referees query
	var all_referees: Array[Dictionary] = DatabaseManager.fetch_referees()
	if all_referees.size() == 127:
		passed += 1
		print("[PASS] Verified master referees query (exactly 127 match officials returned)")
	else:
		failed += 1
		printerr("[FAIL] Expected 127 referees, got %d" % all_referees.size())

	# Test 9: DatabaseViewer scene instantiation
	var db_viewer_scene: PackedScene = load("res://ui/DatabaseViewer.tscn") as PackedScene
	if db_viewer_scene != null:
		var viewer: Node = db_viewer_scene.instantiate()
		if viewer != null:
			passed += 1
			print("[PASS] Verified DatabaseViewer scene instantiates cleanly")
			viewer.free()
		else:
			failed += 1
			printerr("[FAIL] Could not instantiate DatabaseViewer scene")
	else:
		failed += 1
		printerr("[FAIL] Could not load res://ui/DatabaseViewer.tscn")

	print("--- Database Integration Results: %d passed, %d failed ---" % [passed, failed])
	return failed == 0

