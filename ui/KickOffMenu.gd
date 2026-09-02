##
## KickOffMenu
##
## Team-selection overlay shown by MainMenu when the player picks "Kick Off".
## Supports 4 distinct match modes (1P vs CPU, 1P vs 2P, Watch CPU vs CPU, Quick Simulation)
## and displays rich FIFA/PES-style team ratings (Overall, Stars, ATT/MID/DEF/GK units,
## formation, manager, and captain) for informed tactical selection.
##
## Depends on: DataLoader, GameManager, ManagerLoader, RefereeLoader, QuickSimEngine.
## Exposes: signal menu_closed, open()
##

extends Control

signal menu_closed

const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)
const GOLD_COLOR: Color = Color(0.95, 0.80, 0.25)
const CYAN_COLOR: Color = Color(0.35, 0.82, 0.88)
const ORANGE_COLOR: Color = Color(0.95, 0.55, 0.25)
const MUTED_COLOR: Color = Color(0.88, 0.35, 0.35)

const DURATION_OPTIONS: Array[Dictionary] = [
	{"label": "2.5 min half (5 min match)", "seconds": 150.0},
	{"label": "3 min half (6 min match)", "seconds": 180.0},
	{"label": "4 min half (8 min match)", "seconds": 240.0},
	{"label": "5 min half (10 min match)", "seconds": 300.0},
	{"label": "10 min half (20 min match)", "seconds": 600.0},
	{"label": "45 min half (90 min full real-time match)", "seconds": 2700.0},
]

const QuickSimModalScene: PackedScene = preload("res://ui/QuickSimModal.tscn")

# Mode buttons
@onready var btn_vs_cpu: Button = $Panel/Layout/ModeRow/VsCpuButton
@onready var btn_vs_player: Button = $Panel/Layout/ModeRow/VsPlayerButton
@onready var btn_vs_spectator: Button = $Panel/Layout/ModeRow/VsSpectatorButton
@onready var btn_quick_sim_mode: Button = $Panel/Layout/ModeRow/QuickSimModeButton
@onready var mode_desc_label: Label = $Panel/Layout/ModeDescLabel

# Team Lists
@onready var home_list: ItemList = $Panel/Layout/TeamRow/HomePanel/HomeList
@onready var away_list: ItemList = $Panel/Layout/TeamRow/AwayPanel/AwayList

# Home Team Card
@onready var home_name_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/NameRow/HomeNameLabel
@onready var home_ovr_badge: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/NameRow/HomeOvrBadge
@onready var home_star_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/NameRow/HomeStarLabel
@onready var home_att_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/RatingsRow/HomeAttLabel
@onready var home_mid_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/RatingsRow/HomeMidLabel
@onready var home_def_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/RatingsRow/HomeDefLabel
@onready var home_gk_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/RatingsRow/HomeGkLabel
@onready var home_formation_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/InfoRow/HomeFormationLabel
@onready var home_manager_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/InfoRow/HomeManagerLabel
@onready var home_captain_label: Label = $Panel/Layout/TeamRow/HomePanel/HomeCard/VBox/HomeCaptainLabel

# Matchup Center Panel
@onready var matchup_diff_label: Label = $Panel/Layout/TeamRow/MatchupPanel/MatchupDiffLabel
@onready var matchup_note_label: Label = $Panel/Layout/TeamRow/MatchupPanel/MatchupNoteLabel

# Away Team Card
@onready var away_name_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/NameRow/AwayNameLabel
@onready var away_ovr_badge: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/NameRow/AwayOvrBadge
@onready var away_star_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/NameRow/AwayStarLabel
@onready var away_att_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/RatingsRow/AwayAttLabel
@onready var away_mid_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/RatingsRow/AwayMidLabel
@onready var away_def_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/RatingsRow/AwayDefLabel
@onready var away_gk_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/RatingsRow/AwayGkLabel
@onready var away_formation_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/InfoRow/AwayFormationLabel
@onready var away_manager_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/InfoRow/AwayManagerLabel
@onready var away_captain_label: Label = $Panel/Layout/TeamRow/AwayPanel/AwayCard/VBox/AwayCaptainLabel

# Match Duration & Action Row
@onready var duration_label: Label = $Panel/Layout/DurationRow/DurationLabel
@onready var duration_option: OptionButton = $Panel/Layout/DurationRow/DurationOption
@onready var quick_sim_notice: Label = $Panel/Layout/DurationRow/QuickSimNotice
@onready var hint_label: Label = $Panel/Layout/HintLabel
@onready var btn_back: Button = $Panel/Layout/ButtonRow/BackButton
@onready var btn_quick_sim: Button = $Panel/Layout/ButtonRow/QuickSimButton
@onready var btn_confirm: Button = $Panel/Layout/ButtonRow/ConfirmButton

var home_team_index: int = -1
var away_team_index: int = -1
var vs_mode: String = "cpu"


func _ready() -> void:
	visible = false
	btn_vs_cpu.toggled.connect(_on_vs_cpu_toggled)
	btn_vs_player.toggled.connect(_on_vs_player_toggled)
	btn_vs_spectator.toggled.connect(_on_vs_spectator_toggled)
	btn_quick_sim_mode.toggled.connect(_on_quick_sim_mode_toggled)

	home_list.item_selected.connect(_on_home_selected)
	away_list.item_selected.connect(_on_away_selected)

	if duration_option != null:
		duration_option.item_selected.connect(_on_duration_selected)
	btn_back.pressed.connect(_on_back_pressed)
	btn_quick_sim.pressed.connect(_on_quick_sim_pressed)
	btn_confirm.pressed.connect(_on_confirm_pressed)

	_populate_teams()
	_populate_durations()
	_style_lists()
	_update_team_card(true, -1)
	_update_team_card(false, -1)
	_update_matchup()
	_update_mode_ui()
	_update_confirm()


## Called by MainMenu instead of just `show()` so every re-entry starts from a
## clean selection rather than remembering the last match's teams.
func open() -> void:
	visible = true
	home_team_index = -1
	away_team_index = -1
	home_list.deselect_all()
	away_list.deselect_all()
	_update_team_card(true, -1)
	_update_team_card(false, -1)
	_update_matchup()
	_update_mode_ui()
	_update_confirm()
	btn_vs_cpu.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"action_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _populate_teams() -> void:
	home_list.clear()
	away_list.clear()
	if DataLoader.league == null:
		return

	for i: int in range(DataLoader.league.teams.size()):
		var team: TeamData = DataLoader.league.teams[i]
		var units: Dictionary = QuickSimEngine.calculate_team_units(team)
		var ovr: int = int(roundf(float(units["overall"])))
		var stars: String = QuickSimEngine.get_star_rating_string(float(units["overall"]))
		var item_text: String = "%s  •  OVR %d  %s" % [team.team_name, ovr, stars]

		home_list.add_item(item_text)
		home_list.set_item_custom_fg_color(home_list.item_count - 1, team.team_color)

		var tooltip: String = "%s\nOverall: %d  (%s)\nATT: %d  |  MID: %d  |  DEF: %d  |  GK: %d\nFormation: %s" % [
			team.team_name,
			ovr,
			stars,
			int(roundf(float(units["att"]))),
			int(roundf(float(units["mid"]))),
			int(roundf(float(units["def"]))),
			int(roundf(float(units["gk"]))),
			_get_team_formation(team)
		]
		home_list.set_item_tooltip(home_list.item_count - 1, tooltip)

		away_list.add_item(item_text)
		away_list.set_item_custom_fg_color(away_list.item_count - 1, team.team_color)
		away_list.set_item_tooltip(away_list.item_count - 1, tooltip)


## Green focus outline on whichever ItemList currently has keyboard focus, so
## the active panel (Tab switches between them) reads at a glance.
func _style_lists() -> void:
	for list: ItemList in [home_list, away_list]:
		var focus_style := StyleBoxFlat.new()
		focus_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		focus_style.border_width_left = 2
		focus_style.border_width_top = 2
		focus_style.border_width_right = 2
		focus_style.border_width_bottom = 2
		focus_style.border_color = ACCENT_COLOR
		focus_style.corner_radius_top_left = 4
		focus_style.corner_radius_top_right = 4
		focus_style.corner_radius_bottom_right = 4
		focus_style.corner_radius_bottom_left = 4
		list.add_theme_stylebox_override("focus", focus_style)


func _on_vs_cpu_toggled(pressed: bool) -> void:
	if pressed:
		vs_mode = "cpu"
		_update_mode_ui()


func _on_vs_player_toggled(pressed: bool) -> void:
	if pressed:
		vs_mode = "local"
		_update_mode_ui()


func _on_vs_spectator_toggled(pressed: bool) -> void:
	if pressed:
		vs_mode = "spectator"
		_update_mode_ui()


func _on_quick_sim_mode_toggled(pressed: bool) -> void:
	if pressed:
		vs_mode = "quick_sim"
		_update_mode_ui()


func _update_mode_ui() -> void:
	match vs_mode:
		"cpu":
			mode_desc_label.text = "1P vs CPU — Take control of the Home team against the CPU."
			btn_confirm.text = "KICK OFF!"
			duration_label.visible = true
			duration_option.visible = true
			quick_sim_notice.visible = false
		"local":
			mode_desc_label.text = "1P vs 2P — Local head-to-head match: 1P (Home) vs 2P (Away)."
			btn_confirm.text = "KICK OFF (2P)!"
			duration_label.visible = true
			duration_option.visible = true
			quick_sim_notice.visible = false
		"spectator":
			mode_desc_label.text = "Watch CPU vs CPU — Real-time tactical simulation with camera & live telemetry."
			btn_confirm.text = "WATCH MATCH"
			duration_label.visible = true
			duration_option.visible = true
			quick_sim_notice.visible = false
		"quick_sim":
			mode_desc_label.text = "Quick Simulation — Instant analytical outcome with Poisson xG, timeline & full analytics."
			btn_confirm.text = "SIMULATE MATCH ⚡"
			duration_label.visible = false
			duration_option.visible = false
			quick_sim_notice.visible = true

	_update_confirm()


func _on_home_selected(index: int) -> void:
	home_team_index = index
	_update_team_card(true, index)
	_update_matchup()
	_update_confirm()


func _on_away_selected(index: int) -> void:
	away_team_index = index
	_update_team_card(false, index)
	_update_matchup()
	_update_confirm()


func _update_team_card(is_home: bool, team_index: int) -> void:
	var name_lbl: Label = home_name_label if is_home else away_name_label
	var ovr_badge: Label = home_ovr_badge if is_home else away_ovr_badge
	var star_lbl: Label = home_star_label if is_home else away_star_label
	var att_lbl: Label = home_att_label if is_home else away_att_label
	var mid_lbl: Label = home_mid_label if is_home else away_mid_label
	var def_lbl: Label = home_def_label if is_home else away_def_label
	var gk_lbl: Label = home_gk_label if is_home else away_gk_label
	var form_lbl: Label = home_formation_label if is_home else away_formation_label
	var mgr_lbl: Label = home_manager_label if is_home else away_manager_label
	var capt_lbl: Label = home_captain_label if is_home else away_captain_label

	if team_index < 0:
		name_lbl.text = "Select Home Team" if is_home else "Select Away Team"
		name_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.78))
		ovr_badge.text = "OVR --"
		ovr_badge.add_theme_color_override("font_color", Color(0.65, 0.72, 0.68))
		star_lbl.text = "★★★★★"
		star_lbl.add_theme_color_override("font_color", Color(0.4, 0.45, 0.42))
		att_lbl.text = "ATT: --"
		att_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.62))
		mid_lbl.text = "MID: --"
		mid_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.62))
		def_lbl.text = "DEF: --"
		def_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.62))
		gk_lbl.text = "GK: --"
		gk_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.62))
		form_lbl.text = "Formation: --"
		mgr_lbl.text = "Manager: --"
		capt_lbl.text = "Captain: --"
		return

	var team: TeamData = DataLoader.get_team(team_index)
	if team == null:
		return

	var units: Dictionary = QuickSimEngine.calculate_team_units(team)
	var ovr: int = int(roundf(float(units["overall"])))
	var att: int = int(roundf(float(units["att"])))
	var mid: int = int(roundf(float(units["mid"])))
	var def_val: int = int(roundf(float(units["def"])))
	var gk: int = int(roundf(float(units["gk"])))
	var stars: String = QuickSimEngine.get_star_rating_string(float(units["overall"]))

	name_lbl.text = team.team_name
	name_lbl.add_theme_color_override("font_color", team.team_color)

	ovr_badge.text = "%d OVR" % ovr
	ovr_badge.add_theme_color_override("font_color", _get_rating_color(float(ovr)))

	star_lbl.text = stars
	star_lbl.add_theme_color_override("font_color", GOLD_COLOR)

	att_lbl.text = "ATT: %d" % att
	att_lbl.add_theme_color_override("font_color", _get_rating_color(float(att)))

	mid_lbl.text = "MID: %d" % mid
	mid_lbl.add_theme_color_override("font_color", _get_rating_color(float(mid)))

	def_lbl.text = "DEF: %d" % def_val
	def_lbl.add_theme_color_override("font_color", _get_rating_color(float(def_val)))

	gk_lbl.text = "GK: %d" % gk
	gk_lbl.add_theme_color_override("font_color", _get_rating_color(float(gk)))

	form_lbl.text = "Formation: %s" % _get_team_formation(team)

	var mgr: ManagerData = ManagerLoader.get_or_assign_manager(team.team_name)
	mgr_lbl.text = "Manager: %s" % (mgr.manager_name if mgr != null else "Unknown")

	capt_lbl.text = "Captain: %s" % _get_team_captain_name(team)


func _update_matchup() -> void:
	if home_team_index == -1 or away_team_index == -1:
		matchup_diff_label.text = ""
		matchup_note_label.text = ""
		return

	var home_team: TeamData = DataLoader.get_team(home_team_index)
	var away_team: TeamData = DataLoader.get_team(away_team_index)
	if home_team == null or away_team == null:
		return

	var h_units: Dictionary = QuickSimEngine.calculate_team_units(home_team)
	var a_units: Dictionary = QuickSimEngine.calculate_team_units(away_team)

	var h_ovr: int = int(roundf(float(h_units["overall"])))
	var a_ovr: int = int(roundf(float(a_units["overall"])))
	var diff: int = h_ovr - a_ovr

	if diff > 0:
		matchup_diff_label.text = "Home +%d OVR" % diff
		matchup_diff_label.add_theme_color_override("font_color", ACCENT_COLOR)
	elif diff < 0:
		matchup_diff_label.text = "Away +%d OVR" % abs(diff)
		matchup_diff_label.add_theme_color_override("font_color", CYAN_COLOR)
	else:
		matchup_diff_label.text = "Even Matchup"
		matchup_diff_label.add_theme_color_override("font_color", GOLD_COLOR)

	var h_att: int = int(roundf(float(h_units["att"])))
	var h_def: int = int(roundf(float(h_units["def"])))
	var a_att: int = int(roundf(float(a_units["att"])))
	var a_def: int = int(roundf(float(a_units["def"])))
	matchup_note_label.text = "H ATT %d vs A DEF %d\nH DEF %d vs A ATT %d" % [h_att, a_def, h_def, a_att]


func _get_rating_color(rating: float) -> Color:
	if rating >= 80.0:
		return ACCENT_COLOR
	elif rating >= 75.0:
		return CYAN_COLOR
	elif rating >= 70.0:
		return GOLD_COLOR
	elif rating >= 65.0:
		return ORANGE_COLOR
	else:
		return MUTED_COLOR


func _get_team_formation(team: TeamData) -> String:
	if team == null:
		return "4-4-2"
	if team.formation_override != "":
		return team.formation_override
	var mgr: ManagerData = ManagerLoader.get_or_assign_manager(team.team_name)
	if mgr != null and mgr.preferred_formation != "":
		return mgr.preferred_formation
	return "4-4-2"


func _get_team_captain_name(team: TeamData) -> String:
	if team == null:
		return "--"
	for p: PlayerData in team.squad:
		if p.is_captain:
			return "%s (#%d)" % [p.player_name, p.shirt_number]
	if team.captain_index >= 0 and team.captain_index < team.squad.size():
		var p_capt: PlayerData = team.squad[team.captain_index]
		return "%s (#%d)" % [p_capt.player_name, p_capt.shirt_number]
	if team.squad.size() > 0:
		var p_first: PlayerData = team.squad[0]
		return "%s (#%d)" % [p_first.player_name, p_first.shirt_number]
	return "--"


func _update_confirm() -> void:
	var both_selected: bool = home_team_index != -1 and away_team_index != -1
	btn_confirm.disabled = not both_selected
	btn_quick_sim.disabled = not both_selected

	if both_selected:
		match vs_mode:
			"quick_sim":
				hint_label.text = "Teams selected. Ready for Quick Simulation!"
			"spectator":
				hint_label.text = "Teams selected. Ready to Watch Simulation!"
			_:
				hint_label.text = "Teams selected. KICK OFF ready!"
		btn_confirm.grab_focus()
	else:
		hint_label.text = "Select both teams to continue"


func _on_quick_sim_pressed() -> void:
	if home_team_index == -1 or away_team_index == -1:
		return

	var home_team: TeamData = DataLoader.get_team(home_team_index)
	var away_team: TeamData = DataLoader.get_team(away_team_index)
	var home_mgr: ManagerData = ManagerLoader.get_or_assign_manager(home_team.team_name)
	var away_mgr: ManagerData = ManagerLoader.get_or_assign_manager(away_team.team_name)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home_team.team_name, away_team.team_name)

	var modal: QuickSimModal = QuickSimModalScene.instantiate() as QuickSimModal
	add_child(modal)
	modal.setup_match(home_team, away_team, home_mgr, away_mgr, ref, home_team.lineup_indices, away_team.lineup_indices)
	modal.open()
	modal.modal_closed.connect(func():
		modal.queue_free()
		btn_quick_sim.grab_focus()
	)


func _populate_durations() -> void:
	if duration_option == null:
		return
	duration_option.clear()
	var selected_idx: int = 0
	for i: int in range(DURATION_OPTIONS.size()):
		var opt: Dictionary = DURATION_OPTIONS[i]
		duration_option.add_item(opt["label"])
		if is_equal_approx(opt["seconds"], GameManager.half_duration_real_sec):
			selected_idx = i
	duration_option.select(selected_idx)


func _on_duration_selected(index: int) -> void:
	if index >= 0 and index < DURATION_OPTIONS.size():
		var sec: float = DURATION_OPTIONS[index]["seconds"]
		GameManager.set_half_duration(sec)


func _on_confirm_pressed() -> void:
	if home_team_index == -1 or away_team_index == -1:
		return

	if vs_mode == "quick_sim":
		_on_quick_sim_pressed()
		return

	GameManager.set_meta(&"home_team_index", home_team_index)
	GameManager.set_meta(&"away_team_index", away_team_index)
	GameManager.set_meta(&"vs_mode", vs_mode)
	GameManager.set_meta(&"simulate_match", vs_mode == "spectator")
	GameManager.set_meta(&"practice_mode", false)
	GameManager.set_meta(&"half_duration_real_sec", GameManager.half_duration_real_sec)
	get_tree().change_scene_to_file("res://pitch/PitchScene.tscn")


func _on_back_pressed() -> void:
	menu_closed.emit()

