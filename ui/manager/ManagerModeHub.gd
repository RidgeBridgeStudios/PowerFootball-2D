##
## ManagerModeHub
##
## Manager Mode central command hub and matchday simulator.
## Features:
##   - Club selection & career initialization
##   - Live League Standings table (P, W, D, L, GF, GA, GD, PTS) with live sorting
##   - Next fixture card with opponent manager, assigned referee, and venue
##   - "Quick Sim ⚡" match simulation using QuickSimEngine with probability breakdown
##   - "Play Match" real-time match launching
##   - "Simulate Round" to simulate non-player league fixtures
##   - Squad roster & player form/ratings viewer
##
## Depends on: DataLoader, ManagerLoader, RefereeLoader, GameManager, QuickSimEngine,
##             TeamData, PlayerData, ManagerData, RefereeData, MatchStatsUI.
## Exposes: open_hub(), start_new_career(team_index).
##

class_name ManagerModeHub
extends Control

const QuickSimModalScene: PackedScene = preload("res://ui/QuickSimModal.tscn")
const MatchStatsScene: PackedScene = preload("res://ui/MatchStatsUI.tscn")
const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)

class LeagueEntry:
	var team_index: int = 0
	var team_name: String = ""
	var played: int = 0
	var won: int = 0
	var drawn: int = 0
	var lost: int = 0
	var goals_for: int = 0
	var goals_against: int = 0
	var goal_diff: int = 0
	var points: int = 0

class FixtureRecord:
	var matchday: int = 1
	var home_team_idx: int = 0
	var away_team_idx: int = 0
	var played: bool = false
	var home_score: int = 0
	var away_score: int = 0

var user_team_index: int = 0
var current_matchday: int = 1
var total_matchdays: int = 1

var _standings: Array[LeagueEntry] = []
var _fixtures: Array[FixtureRecord] = []

# Node references
@onready var club_select_view: Control = $ClubSelectView
@onready var hub_view: Control = $HubView

# Club selection widgets
@onready var club_list: ItemList = $ClubSelectView/Panel/VBoxContainer/ClubList
@onready var btn_start_career: Button = $ClubSelectView/Panel/VBoxContainer/ButtonRow/StartCareerButton
@onready var btn_select_back: Button = $ClubSelectView/Panel/VBoxContainer/ButtonRow/BackButton

# Hub widgets
@onready var club_name_label: Label = $HubView/TopBar/ClubNameLabel
@onready var manager_info_label: Label = $HubView/TopBar/ManagerInfoLabel
@onready var matchday_label: Label = $HubView/TopBar/MatchdayLabel
@onready var standings_list: VBoxContainer = $HubView/MainLayout/StandingsPanel/StandingsScroll/StandingsList

@onready var opp_title_label: Label = $HubView/MainLayout/FixturePanel/FixtureCard/OpponentTitleLabel
@onready var venue_label: Label = $HubView/MainLayout/FixturePanel/FixtureCard/VenueLabel
@onready var opp_manager_label: Label = $HubView/MainLayout/FixturePanel/FixtureCard/OpponentManagerLabel
@onready var referee_label: Label = $HubView/MainLayout/FixturePanel/FixtureCard/RefereeLabel

@onready var btn_play_match: Button = $HubView/MainLayout/FixturePanel/ActionRow/PlayButton
@onready var btn_quick_sim: Button = $HubView/MainLayout/FixturePanel/ActionRow/QuickSimButton
@onready var btn_sim_round: Button = $HubView/MainLayout/FixturePanel/ActionRow/SimRoundButton
@onready var btn_squad: Button = $HubView/MainLayout/FixturePanel/ActionRow/SquadButton
@onready var btn_new_career: Button = $HubView/MainLayout/FixturePanel/ActionRow/NewCareerButton
@onready var btn_main_menu: Button = $HubView/MainLayout/FixturePanel/ActionRow/MainMenuButton

# Squad modal
@onready var squad_dialog: AcceptDialog = $SquadDialog
@onready var squad_scroll_list: VBoxContainer = $SquadDialog/SquadScroll/SquadList


func _ready() -> void:
	btn_start_career.pressed.connect(_on_start_career_pressed)
	btn_select_back.pressed.connect(_on_select_back_pressed)
	club_list.item_selected.connect(_on_club_selected)

	btn_play_match.pressed.connect(_on_play_match_pressed)
	btn_quick_sim.pressed.connect(_on_quick_sim_pressed)
	btn_sim_round.pressed.connect(_on_sim_round_pressed)
	btn_squad.pressed.connect(_on_squad_pressed)
	btn_new_career.pressed.connect(_on_new_career_pressed)
	btn_main_menu.pressed.connect(_on_main_menu_pressed)

	_check_existing_career()


func _check_existing_career() -> void:
	if GameManager.has_meta(&"manager_career_active") and bool(GameManager.get_meta(&"manager_career_active")):
		user_team_index = int(GameManager.get_meta(&"manager_user_team", 0))
		_restore_career_state()
		if GameManager.has_meta(&"manager_last_match_result"):
			var res: Dictionary = GameManager.get_meta(&"manager_last_match_result")
			GameManager.remove_meta(&"manager_last_match_result")
			var fix: FixtureRecord = _get_user_next_fixture()
			if fix != null:
				fix.played = true
				fix.home_score = int(res.get("home_score", 0))
				fix.away_score = int(res.get("away_score", 0))
				_record_result_in_standings(fix.home_team_idx, fix.away_team_idx, fix.home_score, fix.away_score)
				_advance_matchday_if_ready()
				_save_career_state()
		_show_hub()
	else:
		_populate_club_list()
		_show_club_select()


func _show_club_select() -> void:
	club_select_view.visible = true
	hub_view.visible = false
	btn_start_career.disabled = true
	if club_list.item_count > 0:
		club_list.select(0)
		_on_club_selected(0)


func _show_hub() -> void:
	club_select_view.visible = false
	hub_view.visible = true
	_refresh_dashboard()


func _populate_club_list() -> void:
	club_list.clear()
	if DataLoader.league == null:
		return
	for i: int in range(DataLoader.league.teams.size()):
		var t: TeamData = DataLoader.league.teams[i]
		var mgr: ManagerData = ManagerLoader.get_or_assign_manager(t.team_name)
		var text: String = "%s  [%s]  (Rep: %.0f%% | Budget: £%dK | Manager: %s)" % [
			t.team_name, t.stature, t.reputation * 100.0, t.transfer_budget / 1000, mgr.manager_name
		]
		club_list.add_item(text)
		club_list.set_item_custom_fg_color(i, t.team_color)


func _on_club_selected(index: int) -> void:
	user_team_index = index
	btn_start_career.disabled = false


func _on_start_career_pressed() -> void:
	start_new_career(user_team_index)


func start_new_career(team_idx: int) -> void:
	user_team_index = team_idx
	GameManager.set_meta(&"manager_career_active", true)
	GameManager.set_meta(&"manager_user_team", user_team_index)

	_init_season()
	_show_hub()


func _init_season() -> void:
	current_matchday = 1
	_standings.clear()
	_fixtures.clear()

	if DataLoader.league == null:
		return

	var num_teams: int = DataLoader.league.teams.size()
	for i: int in range(num_teams):
		var t: TeamData = DataLoader.league.teams[i]
		var entry := LeagueEntry.new()
		entry.team_index = i
		entry.team_name = t.team_name
		_standings.append(entry)

	# Generate double round-robin schedule
	_generate_fixtures(num_teams)
	_save_career_state()


func _generate_fixtures(num_teams: int) -> void:
	_fixtures.clear()
	var team_indices: Array[int] = []
	for i in range(num_teams):
		team_indices.append(i)

	if num_teams < 2:
		return

	var is_odd: bool = (num_teams % 2 != 0)
	if is_odd:
		team_indices.append(-1) # Bye

	var total_rounds: int = (team_indices.size() - 1) * 2
	var half_size: int = team_indices.size() / 2

	var current_teams: Array[int] = team_indices.duplicate()

	for r in range(team_indices.size() - 1):
		var m_day: int = r + 1
		for i in range(half_size):
			var t1: int = current_teams[i]
			var t2: int = current_teams[current_teams.size() - 1 - i]
			if t1 != -1 and t2 != -1:
				var fix := FixtureRecord.new()
				fix.matchday = m_day
				fix.home_team_idx = t1 if r % 2 == 0 else t2
				fix.away_team_idx = t2 if r % 2 == 0 else t1
				_fixtures.append(fix)

		# Rotate teams (keep index 0 fixed)
		var last_elem: int = current_teams.pop_back()
		current_teams.insert(1, last_elem)

	# Second half of season (reverse home/away)
	var first_half_count: int = _fixtures.size()
	for i in range(first_half_count):
		var orig: FixtureRecord = _fixtures[i]
		var rev_fix := FixtureRecord.new()
		rev_fix.matchday = orig.matchday + (team_indices.size() - 1)
		rev_fix.home_team_idx = orig.away_team_idx
		rev_fix.away_team_idx = orig.home_team_idx
		_fixtures.append(rev_fix)

	total_matchdays = total_rounds


func _refresh_dashboard() -> void:
	if DataLoader.league == null:
		return

	var user_team: TeamData = DataLoader.get_team(user_team_index)
	var user_mgr: ManagerData = ManagerLoader.get_or_assign_manager(user_team.team_name)

	club_name_label.text = "%s  •  %s (Rep: %.0f%%)" % [user_team.team_name, user_team.stature, user_team.reputation * 100.0]
	manager_info_label.text = "Manager: %s (Rep: %.0f%% | Board: %.0f%% | Ref Respect: %.0f%%)" % [
		user_mgr.manager_name, user_mgr.reputation * 100.0, user_mgr.board_confidence * 100.0, user_mgr.referee_respect * 100.0
	]
	matchday_label.text = "Matchday %d / %d  •  Budget: £%dK  •  Payroll: £%dK/wk" % [
		current_matchday, maxi(total_matchdays, 1), user_team.transfer_budget / 1000, user_team.get_weekly_payroll() / 1000
	]

	_rebuild_standings_ui()
	_update_next_fixture_card()


func _rebuild_standings_ui() -> void:
	for child: Node in standings_list.get_children():
		child.queue_free()

	# Sort standings by Points desc, GD desc, GF desc
	_standings.sort_custom(func(a: LeagueEntry, b: LeagueEntry) -> bool:
		if a.points != b.points:
			return a.points > b.points
		if a.goal_diff != b.goal_diff:
			return a.goal_diff > b.goal_diff
		return a.goals_for > b.goals_for
	)

	# Header row
	var header := HBoxContainer.new()
	header.theme_override_constants.separation = 8
	var h_pos := _make_label("Pos", 32, HORIZONTAL_ALIGNMENT_LEFT, Color(0.7, 0.7, 0.7))
	var h_club := _make_label("Club", 160, HORIZONTAL_ALIGNMENT_LEFT, Color(0.7, 0.7, 0.7))
	var h_p := _make_label("P", 28, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.7, 0.7))
	var h_w := _make_label("W", 28, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.7, 0.7))
	var h_d := _make_label("D", 28, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.7, 0.7))
	var h_l := _make_label("L", 28, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.7, 0.7))
	var h_gf := _make_label("GF", 32, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.7, 0.7))
	var h_ga := _make_label("GA", 32, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.7, 0.7))
	var h_gd := _make_label("GD", 32, HORIZONTAL_ALIGNMENT_RIGHT, Color(0.7, 0.7, 0.7))
	var h_pts := _make_label("PTS", 36, HORIZONTAL_ALIGNMENT_RIGHT, ACCENT_COLOR)

	for h in [h_pos, h_club, h_p, h_w, h_d, h_l, h_gf, h_ga, h_gd, h_pts]:
		header.add_child(h)
	standings_list.add_child(header)

	# Standings rows
	for pos in range(_standings.size()):
		var e: LeagueEntry = _standings[pos]
		var is_user: bool = (e.team_index == user_team_index)
		var row_color: Color = ACCENT_COLOR if is_user else Color(0.9, 0.9, 0.9)

		var row := HBoxContainer.new()
		row.theme_override_constants.separation = 8
		row.add_child(_make_label(str(pos + 1), 32, HORIZONTAL_ALIGNMENT_LEFT, row_color))
		row.add_child(_make_label(e.team_name, 160, HORIZONTAL_ALIGNMENT_LEFT, row_color))
		row.add_child(_make_label(str(e.played), 28, HORIZONTAL_ALIGNMENT_RIGHT, row_color))
		row.add_child(_make_label(str(e.won), 28, HORIZONTAL_ALIGNMENT_RIGHT, row_color))
		row.add_child(_make_label(str(e.drawn), 28, HORIZONTAL_ALIGNMENT_RIGHT, row_color))
		row.add_child(_make_label(str(e.lost), 28, HORIZONTAL_ALIGNMENT_RIGHT, row_color))
		row.add_child(_make_label(str(e.goals_for), 32, HORIZONTAL_ALIGNMENT_RIGHT, row_color))
		row.add_child(_make_label(str(e.goals_against), 32, HORIZONTAL_ALIGNMENT_RIGHT, row_color))
		var gd_str: String = "+%d" % e.goal_diff if e.goal_diff > 0 else str(e.goal_diff)
		row.add_child(_make_label(gd_str, 32, HORIZONTAL_ALIGNMENT_RIGHT, row_color))
		row.add_child(_make_label(str(e.points), 36, HORIZONTAL_ALIGNMENT_RIGHT, ACCENT_COLOR if is_user else Color.WHITE))

		standings_list.add_child(row)


func _make_label(text: String, min_width: int, align: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(float(min_width), 0.0)
	lbl.horizontal_alignment = align
	lbl.add_theme_color_override("font_color", color)
	return lbl


func _get_user_next_fixture() -> FixtureRecord:
	for fix: FixtureRecord in _fixtures:
		if fix.matchday == current_matchday and not fix.played:
			if fix.home_team_idx == user_team_index or fix.away_team_idx == user_team_index:
				return fix
	return null


func _update_next_fixture_card() -> void:
	var fix: FixtureRecord = _get_user_next_fixture()
	if fix == null:
		opp_title_label.text = "Season Finished / No Fixture"
		venue_label.text = ""
		opp_manager_label.text = ""
		referee_label.text = ""
		btn_play_match.disabled = true
		btn_quick_sim.disabled = true
		btn_sim_round.disabled = true
		return

	var is_home: bool = (fix.home_team_idx == user_team_index)
	var opp_idx: int = fix.away_team_idx if is_home else fix.home_team_idx
	var opp_team: TeamData = DataLoader.get_team(opp_idx)
	var opp_mgr: ManagerData = ManagerLoader.get_or_assign_manager(opp_team.team_name)
	var home_team: TeamData = DataLoader.get_team(fix.home_team_idx)
	var away_team: TeamData = DataLoader.get_team(fix.away_team_idx)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home_team.team_name, away_team.team_name)

	opp_title_label.text = "vs  %s" % opp_team.team_name
	venue_label.text = "Venue: %s (%s)" % ["Home Ground" if is_home else "Away Ground", "Home Advantage" if is_home else "Hostile Crowd"]
	opp_manager_label.text = "Opponent Manager: %s (Style: %s | Form: %s)" % [opp_mgr.manager_name, opp_mgr.preferred_playstyle, opp_team.formation_override]
	referee_label.text = "Official: %s (Strictness: %.0f%% | Respect Rating: %.0f%%)" % [ref.referee_name, ref.strictness * 100.0, ref.respect_rating * 100.0]

	btn_play_match.disabled = false
	btn_quick_sim.disabled = false
	btn_sim_round.disabled = false


func _on_play_match_pressed() -> void:
	var fix: FixtureRecord = _get_user_next_fixture()
	if fix == null:
		return

	GameManager.set_meta(&"home_team_index", fix.home_team_idx)
	GameManager.set_meta(&"away_team_index", fix.away_team_idx)
	GameManager.set_meta(&"vs_mode", "cpu")
	GameManager.set_meta(&"simulate_match", false)
	GameManager.set_meta(&"practice_mode", false)
	GameManager.set_meta(&"stats_return_scene", "res://ui/manager/ManagerModeHub.tscn")
	_save_career_state()

	get_tree().change_scene_to_file("res://pitch/PitchScene.tscn")


func _on_quick_sim_pressed() -> void:
	var fix: FixtureRecord = _get_user_next_fixture()
	if fix == null:
		return

	var home_team: TeamData = DataLoader.get_team(fix.home_team_idx)
	var away_team: TeamData = DataLoader.get_team(fix.away_team_idx)
	var home_mgr: ManagerData = ManagerLoader.get_or_assign_manager(home_team.team_name)
	var away_mgr: ManagerData = ManagerLoader.get_or_assign_manager(away_team.team_name)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home_team.team_name, away_team.team_name)

	var modal: QuickSimModal = QuickSimModalScene.instantiate() as QuickSimModal
	add_child(modal)
	modal.setup_match(home_team, away_team, home_mgr, away_mgr, ref, home_team.lineup_indices, away_team.lineup_indices)
	modal.open()
	modal.match_completed.connect(func(res: QuickSimEngine.QuickSimResult):
		fix.played = true
		fix.home_score = res.home_score
		fix.away_score = res.away_score
		_record_result_in_standings(fix.home_team_idx, fix.away_team_idx, res.home_score, res.away_score)
		CareerProgressionEngine.process_matchday_progression(
			home_team, away_team, home_mgr, away_mgr, ref,
			res.home_score, res.away_score,
			res.home_fouls + res.away_fouls,
			res.home_yellows + res.away_yellows,
			res.home_reds + res.away_reds,
			0
		)
	)
	modal.modal_closed.connect(func():
		modal.queue_free()
		_advance_matchday_if_ready()
		_save_career_state()
		_refresh_dashboard()
	)


func _on_sim_round_pressed() -> void:
	# Simulates all unplayed matches in the current matchday
	for fix: FixtureRecord in _fixtures:
		if fix.matchday == current_matchday and not fix.played:
			var home_t: TeamData = DataLoader.get_team(fix.home_team_idx)
			var away_t: TeamData = DataLoader.get_team(fix.away_team_idx)
			var home_m: ManagerData = ManagerLoader.get_or_assign_manager(home_t.team_name)
			var away_m: ManagerData = ManagerLoader.get_or_assign_manager(away_t.team_name)
			var ref: RefereeData = RefereeLoader.get_or_assign_referee(home_t.team_name, away_t.team_name)

			var res: QuickSimEngine.QuickSimResult = QuickSimEngine.simulate_match(
				home_t, away_t, home_m, away_m, ref, home_t.lineup_indices, away_t.lineup_indices
			)
			QuickSimEngine.apply_to_match_stats_tracker(res, home_t, away_t, ref, home_m, away_m)

			fix.played = true
			fix.home_score = res.home_score
			fix.away_score = res.away_score
			_record_result_in_standings(fix.home_team_idx, fix.away_team_idx, res.home_score, res.away_score)
			CareerProgressionEngine.process_matchday_progression(
				home_t, away_t, home_m, away_m, ref,
				res.home_score, res.away_score,
				res.home_fouls + res.away_fouls,
				res.home_yellows + res.away_yellows,
				res.home_reds + res.away_reds,
				0
			)

	_advance_matchday_if_ready()
	_save_career_state()
	_refresh_dashboard()


func _record_result_in_standings(home_idx: int, away_idx: int, h_score: int, a_score: int) -> void:
	var h_entry: LeagueEntry = _get_entry(home_idx)
	var a_entry: LeagueEntry = _get_entry(away_idx)
	if h_entry == null or a_entry == null:
		return

	h_entry.played += 1
	a_entry.played += 1
	h_entry.goals_for += h_score
	h_entry.goals_against += a_score
	a_entry.goals_for += a_score
	a_entry.goals_against += h_score

	h_entry.goal_diff = h_entry.goals_for - h_entry.goals_against
	a_entry.goal_diff = a_entry.goals_for - a_entry.goals_against

	if h_score > a_score:
		h_entry.won += 1
		h_entry.points += 3
		a_entry.lost += 1
	elif a_score > h_score:
		a_entry.won += 1
		a_entry.points += 3
		h_entry.lost += 1
	else:
		h_entry.drawn += 1
		h_entry.points += 1
		a_entry.drawn += 1
		a_entry.points += 1


func _get_entry(team_idx: int) -> LeagueEntry:
	for e: LeagueEntry in _standings:
		if e.team_index == team_idx:
			return e
	return null


func _advance_matchday_if_ready() -> void:
	var all_played: bool = true
	for fix: FixtureRecord in _fixtures:
		if fix.matchday == current_matchday and not fix.played:
			all_played = false
			break
	if all_played and current_matchday < total_matchdays:
		current_matchday += 1


func _on_squad_pressed() -> void:
	var user_team: TeamData = DataLoader.get_team(user_team_index)
	for child: Node in squad_scroll_list.get_children():
		child.queue_free()

	for slot in range(user_team.squad.size()):
		var p: PlayerData = user_team.squad[slot]
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 8)

		var nat_badge: HBoxContainer = NationDatabase.create_nationality_badge(p.nationality, false, 12)
		item.add_child(nat_badge)

		var card := Label.new()
		var archetype: String = p.get_personality_archetype()
		var lang_summary: String = ""
		if not p.spoken_languages.is_empty():
			var l_names: Array[String] = []
			for l: Dictionary in p.spoken_languages:
				var l_emoji: String = NationDatabase.get_flag_emoji(str(l.get("language", "")))
				l_names.append("%s %s" % [l_emoji, l.get("language", "")])
			lang_summary = "  |  " + (", ".join(l_names))

		card.text = "#%d  %s  [%s]  Age: %s  OVR: %d  Archetype: %s%s  Wage: £%d/wk  Years: %d  Morale: %.0f%%  Form: %.1f" % [
			p.shirt_number, p.player_name, p.position_role, p.get_age_detail_string(), p.calculate_overall_rating(),
			archetype, lang_summary, p.wage_weekly, p.contract_years, p.morale * 100.0, p.form
		]
		item.add_child(card)
		squad_scroll_list.add_child(item)

	# Backroom Staff section
	if not user_team.staff.is_empty():
		var staff_sep := HSeparator.new()
		squad_scroll_list.add_child(staff_sep)

		var staff_hdr := Label.new()
		staff_hdr.text = "=== BACKROOM STAFF ==="
		staff_hdr.add_theme_font_size_override("font_size", 14)
		staff_hdr.add_theme_color_override("font_color", Color(0.95, 0.82, 0.45))
		squad_scroll_list.add_child(staff_hdr)

		for s: StaffData in user_team.staff:
			var s_item := HBoxContainer.new()
			s_item.add_theme_constant_override("separation", 8)
			var s_flag: HBoxContainer = NationDatabase.create_nationality_badge(s.nationality, false, 12)
			s_item.add_child(s_flag)

			var s_card := Label.new()
			var s_langs: Array[String] = []
			for l: Dictionary in s.spoken_languages:
				var s_emoji: String = NationDatabase.get_flag_emoji(str(l.get("language", "")))
				s_langs.append("%s %s" % [s_emoji, l.get("language", "")])
			var s_lang_str: String = "  |  " + (", ".join(s_langs)) if not s_langs.is_empty() else ""

			s_card.text = "%s: %s  •  Age: %s  •  %s%s  •  Salary: £%d/wk" % [
				s.role, s.staff_name, s.get_age_detail_string(), s.get_specialty_summary(),
				s_lang_str, s.salary_weekly
			]
			s_item.add_child(s_card)
			squad_scroll_list.add_child(s_item)

	squad_dialog.popup_centered()


func _on_new_career_pressed() -> void:
	GameManager.set_meta(&"manager_career_active", false)
	_populate_club_list()
	_show_club_select()


func _on_select_back_pressed() -> void:
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")


func _on_main_menu_pressed() -> void:
	_save_career_state()
	get_tree().change_scene_to_file("res://ui/MainMenu.tscn")


# --- Persistence helpers ------------------------------------------------------

func _save_career_state() -> void:
	var standings_data: Array[Dictionary] = []
	for e: LeagueEntry in _standings:
		standings_data.append({
			"idx": e.team_index,
			"name": e.team_name,
			"p": e.played,
			"w": e.won,
			"d": e.drawn,
			"l": e.lost,
			"gf": e.goals_for,
			"ga": e.goals_against,
			"pts": e.points,
		})

	var fixtures_data: Array[Dictionary] = []
	for f: FixtureRecord in _fixtures:
		fixtures_data.append({
			"md": f.matchday,
			"h": f.home_team_idx,
			"a": f.away_team_idx,
			"pl": f.played,
			"hs": f.home_score,
			"as": f.away_score,
		})

	GameManager.set_meta(&"manager_career_active", true)
	GameManager.set_meta(&"manager_user_team", user_team_index)
	GameManager.set_meta(&"manager_matchday", current_matchday)
	GameManager.set_meta(&"manager_total_matchdays", total_matchdays)
	GameManager.set_meta(&"manager_standings", standings_data)
	GameManager.set_meta(&"manager_fixtures", fixtures_data)


func _restore_career_state() -> void:
	current_matchday = int(GameManager.get_meta(&"manager_matchday", 1))
	total_matchdays = int(GameManager.get_meta(&"manager_total_matchdays", 1))

	_standings.clear()
	var s_arr: Array = GameManager.get_meta(&"manager_standings", [])
	for d: Dictionary in s_arr:
		var e := LeagueEntry.new()
		e.team_index = int(d.get("idx", 0))
		e.team_name = String(d.get("name", ""))
		e.played = int(d.get("p", 0))
		e.won = int(d.get("w", 0))
		e.drawn = int(d.get("d", 0))
		e.lost = int(d.get("l", 0))
		e.goals_for = int(d.get("gf", 0))
		e.goals_against = int(d.get("ga", 0))
		e.goal_diff = e.goals_for - e.goals_against
		e.points = int(d.get("pts", 0))
		_standings.append(e)

	_fixtures.clear()
	var f_arr: Array = GameManager.get_meta(&"manager_fixtures", [])
	for fd: Dictionary in f_arr:
		var f := FixtureRecord.new()
		f.matchday = int(fd.get("md", 1))
		f.home_team_idx = int(fd.get("h", 0))
		f.away_team_idx = int(fd.get("a", 0))
		f.played = bool(fd.get("pl", false))
		f.home_score = int(fd.get("hs", 0))
		f.away_score = int(fd.get("as", 0))
		_fixtures.append(f)
