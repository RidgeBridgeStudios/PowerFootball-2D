##
## TacticsEditor
##
## Central tactical management UI for PowerFootball-2D.
## Provides an interactive pitch board (TacticsPitchView), formation picker,
## player inspector with individual role selection and tactical sliders,
## and a reserves/bench substitution panel.
##
## Usable in both PREGAME (unlimited swaps/edits) and IN_MATCH (pause screen,
## 3-substitution limit, live player stamina reads, and immediate simulation sync).
##
## Depends on: TeamManagementData, FormationRegistry, FormationLibrary,
##             PlayerRoleConfig, PlayerData, HeavyPlayerController, GameEvents.
##

class_name TacticsEditor
extends Control

signal formation_changed(team_id: int, new_formation: String)
signal lineup_changed(team_id: int)
signal substitution_made(team_id: int, out_squad_idx: int, in_squad_idx: int)
signal close_requested()

const OUTFIELD_ROLES: Array[String] = [
	"CB", "LB", "RB", "DM", "CDM", "CM", "LM", "RM", "LW", "RW", "AM", "CAM", "ST", "CF"
]

const ROLE_PRESET_PATHS: Dictionary = {
	"CB": "res://shared/roles/role_cb.tres",
	"LB": "res://shared/roles/role_lb.tres",
	"RB": "res://shared/roles/role_rb.tres",
	"DM": "res://shared/roles/role_dm.tres",
	"CDM": "res://shared/roles/role_cdm.tres",
	"CM": "res://shared/roles/role_cm.tres",
	"LM": "res://shared/roles/role_lm.tres",
	"RM": "res://shared/roles/role_rm.tres",
	"LW": "res://shared/roles/role_lw.tres",
	"RW": "res://shared/roles/role_rw.tres",
	"AM": "res://shared/roles/role_am.tres",
	"CAM": "res://shared/roles/role_am.tres",
	"ST": "res://shared/roles/role_st.tres",
	"CF": "res://shared/roles/role_st.tres",
}

@onready var team_name_label: Label = $MainLayout/HeaderBar/TeamNameLabel
@onready var formation_picker: OptionButton = $MainLayout/HeaderBar/FormationPicker
@onready var mentality_picker: OptionButton = $MainLayout/HeaderBar/MentalityPicker
@onready var subs_label: Label = $MainLayout/HeaderBar/SubsLabel

@onready var pitch_view: TacticsPitchView = $MainLayout/ContentSplit/LeftSection/PitchContainer/PitchView
@onready var hint_label: Label = $MainLayout/ContentSplit/LeftSection/HintLabel

@onready var tabs: TabContainer = $MainLayout/ContentSplit/RightSection/Tabs
@onready var inspector_panel: VBoxContainer = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent
@onready var no_player_selected_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/NoPlayerSelectedLabel

# Inspector UI widgets
@onready var player_name_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/PlayerHeader/NameLabel
@onready var player_num_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/PlayerHeader/NumberLabel
@onready var player_pos_badge: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/PlayerHeader/PosBadge
@onready var player_stats_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/PlayerStatsLabel
@onready var player_stamina_bar: ProgressBar = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/StaminaContainer/StaminaBar
@onready var player_stamina_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/StaminaContainer/StaminaLabel

@onready var role_picker: OptionButton = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/RoleSection/RolePicker
@onready var anchor_slider: HSlider = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Sliders/AnchorSlider
@onready var anchor_val_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Sliders/AnchorValLabel
@onready var press_slider: HSlider = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Sliders/PressSlider
@onready var press_val_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Sliders/PressValLabel
@onready var adv_slider: HSlider = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Sliders/AdvSlider
@onready var adv_val_label: Label = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Sliders/AdvValLabel

@onready var reset_role_btn: Button = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Actions/ResetRoleBtn
@onready var make_captain_btn: Button = $MainLayout/ContentSplit/RightSection/Tabs/PlayerTactics/InspectorContent/Actions/MakeCaptainBtn

# Bench UI widgets
@onready var bench_scroll_list: VBoxContainer = $MainLayout/ContentSplit/RightSection/Tabs/BenchReserves/BenchListScroll/BenchList
@onready var starters_scroll_list: VBoxContainer = $MainLayout/ContentSplit/RightSection/Tabs/StartingXI/StartersListScroll/StartersList

var _bio_container: HBoxContainer = null
var _languages_container: HBoxContainer = null

var _mgmt: TeamManagementData = null
var _team_id: int = 0
var _is_in_match: bool = false
var _live_players: Array[HeavyPlayerController] = []

var _selected_starter_slot: int = -1
var _selected_bench_slot: int = -1
var _filter_pos: String = "ALL"
var _updating_ui: bool = false


func _ready() -> void:
	_setup_bio_containers()
	_populate_formation_picker()
	_populate_mentality_picker()
	_connect_events()


func _setup_bio_containers() -> void:
	if inspector_panel == null:
		return
	_bio_container = HBoxContainer.new()
	_bio_container.name = "BioContainer"
	_bio_container.add_theme_constant_override("separation", 8)
	inspector_panel.add_child(_bio_container)
	inspector_panel.move_child(_bio_container, 1)

	_languages_container = HBoxContainer.new()
	_languages_container.name = "LanguagesContainer"
	_languages_container.add_theme_constant_override("separation", 6)
	inspector_panel.add_child(_languages_container)
	inspector_panel.move_child(_languages_container, 2)


func _populate_formation_picker() -> void:
	formation_picker.clear()
	for f: String in FormationRegistry.all_formations():
		formation_picker.add_item(f)


func _populate_mentality_picker() -> void:
	mentality_picker.clear()
	mentality_picker.add_item("Balanced")
	mentality_picker.add_item("Attacking")
	mentality_picker.add_item("Defensive")
	mentality_picker.add_item("High Press")


func _connect_events() -> void:
	formation_picker.item_selected.connect(_on_formation_selected)
	mentality_picker.item_selected.connect(_on_mentality_selected)
	pitch_view.slot_selected.connect(_on_pitch_slot_selected)
	pitch_view.slots_swapped.connect(_on_pitch_slots_swapped)

	role_picker.item_selected.connect(_on_role_picker_selected)
	anchor_slider.value_changed.connect(_on_anchor_slider_changed)
	press_slider.value_changed.connect(_on_press_slider_changed)
	adv_slider.value_changed.connect(_on_adv_slider_changed)

	reset_role_btn.pressed.connect(_on_reset_role_pressed)
	make_captain_btn.pressed.connect(_on_make_captain_pressed)

	# Filter buttons
	var filter_container: HBoxContainer = $MainLayout/ContentSplit/RightSection/Tabs/BenchReserves/FilterBar
	for child in filter_container.get_children():
		var btn := child as Button
		if btn != null:
			var filter_name: String = btn.name.trim_prefix("Filter")
			btn.pressed.connect(func(): _set_position_filter(filter_name))


## Configures the editor with management data for one team.
func setup(mgmt: TeamManagementData, team_id: int, in_match: bool = false, live_players: Array[HeavyPlayerController] = []) -> void:
	_mgmt = mgmt
	_team_id = team_id
	_is_in_match = in_match
	_live_players = live_players
	_selected_starter_slot = -1
	_selected_bench_slot = -1

	team_name_label.text = mgmt.team.team_name if mgmt != null and mgmt.team != null else "Tactics"
	subs_label.visible = in_match
	_refresh_subs_counter()

	# Select current formation in picker
	var f_idx: int = FormationRegistry.all_formations().find(mgmt.formation)
	formation_picker.selected = f_idx if f_idx >= 0 else 0

	pitch_view.setup(_mgmt, _is_in_match, _live_players)
	_refresh_all()


func _refresh_all() -> void:
	_refresh_subs_counter()
	_rebuild_bench_list()
	_rebuild_starters_list()
	_update_inspector()
	pitch_view.queue_redraw()


func _refresh_subs_counter() -> void:
	if not _is_in_match or _mgmt == null:
		return
	var remaining: int = maxi(0, 3 - _mgmt.substitutions_used)
	subs_label.text = "Subs remaining: %d / 3" % remaining
	if remaining == 0:
		subs_label.modulate = Color(0.9, 0.3, 0.3)
	else:
		subs_label.modulate = Color(0.3, 0.9, 0.4)


func _on_formation_selected(idx: int) -> void:
	if _mgmt == null:
		return
	var new_form: String = FormationRegistry.all_formations()[idx]
	_mgmt.formation = new_form
	_mgmt.team.formation_override = new_form
	pitch_view.setup(_mgmt, _is_in_match, _live_players)
	_refresh_all()
	formation_changed.emit(_team_id, new_form)
	GameEvents.formation_changed.emit(_team_id, new_form)


func _on_mentality_selected(idx: int) -> void:
	if _mgmt == null or _mgmt.manager == null:
		return
	match idx:
		0: # Balanced
			_mgmt.manager.tempo = 0.50
			_mgmt.manager.pressing_intensity = 0.50
			_mgmt.manager.defensive_line = 0.50
		1: # Attacking
			_mgmt.manager.tempo = 0.75
			_mgmt.manager.pressing_intensity = 0.65
			_mgmt.manager.defensive_line = 0.65
		2: # Defensive
			_mgmt.manager.tempo = 0.35
			_mgmt.manager.pressing_intensity = 0.35
			_mgmt.manager.defensive_line = 0.30
		3: # High Press
			_mgmt.manager.tempo = 0.85
			_mgmt.manager.pressing_intensity = 0.90
			_mgmt.manager.defensive_line = 0.75


func _on_pitch_slot_selected(slot: int) -> void:
	_selected_starter_slot = slot
	_selected_bench_slot = -1
	_update_inspector()
	if slot >= 0:
		tabs.current_tab = 0 # Switch to Player Tactics tab
		hint_label.text = "Selected slot #%d. Click another starter to swap, or select a bench substitute." % (slot + 1)
	else:
		hint_label.text = "Click any player on the pitch or bench to edit tactics."


func _on_pitch_slots_swapped(slot_a: int, slot_b: int) -> void:
	if _mgmt == null:
		return
	_mgmt.reshuffle(slot_a, slot_b)
	_selected_starter_slot = slot_b
	_refresh_all()
	lineup_changed.emit(_team_id)
	GameEvents.lineup_changed.emit(_team_id)
	hint_label.text = "Reshuffled player positions on pitch."


func _update_inspector() -> void:
	if _selected_starter_slot < 0 or _mgmt == null or _selected_starter_slot >= _mgmt.lineup.size():
		inspector_panel.visible = false
		no_player_selected_label.visible = true
		return

	var squad_idx: int = _mgmt.lineup[_selected_starter_slot]
	if squad_idx < 0 or squad_idx >= _mgmt.team.squad.size():
		inspector_panel.visible = false
		no_player_selected_label.visible = true
		return

	var p: PlayerData = _mgmt.team.squad[squad_idx]
	inspector_panel.visible = true
	no_player_selected_label.visible = false

	_updating_ui = true

	player_name_label.text = p.player_name
	player_num_label.text = "#%d" % p.shirt_number
	var active_role: String = _mgmt.get_slot_role(_selected_starter_slot)
	player_pos_badge.text = "[ %s ]" % active_role

	# Update Bio container (flag, nationality, age, DOB)
	if _bio_container != null:
		for child: Node in _bio_container.get_children():
			child.queue_free()

		if p.nationality != "":
			var nat_badge: HBoxContainer = NationDatabase.create_nationality_badge(p.nationality, true, 13)
			_bio_container.add_child(nat_badge)

		if p.secondary_nationality != "":
			var sec_badge: HBoxContainer = NationDatabase.create_nationality_badge(p.secondary_nationality, true, 12)
			sec_badge.modulate = Color(0.85, 0.85, 0.85, 0.85)
			_bio_container.add_child(sec_badge)

		var age_lbl := Label.new()
		age_lbl.add_theme_font_size_override("font_size", 12)
		age_lbl.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95))
		age_lbl.text = "• Age: %s" % p.get_age_detail_string()
		_bio_container.add_child(age_lbl)

	# Update Spoken Languages container (Football Manager pills)
	if _languages_container != null:
		for child: Node in _languages_container.get_children():
			child.queue_free()

		var lang_title := Label.new()
		lang_title.add_theme_font_size_override("font_size", 11)
		lang_title.add_theme_color_override("font_color", Color(0.65, 0.70, 0.75))
		lang_title.text = "Languages:"
		_languages_container.add_child(lang_title)

		for l_dict: Dictionary in p.spoken_languages:
			var l_name: String = str(l_dict.get("language", "English"))
			var l_lvl: String = str(l_dict.get("level", "Fluent"))
			var l_prof: float = float(l_dict.get("proficiency", 0.8))
			var pill: PanelContainer = NationDatabase.create_language_badge(l_name, l_lvl, l_prof, 11)
			_languages_container.add_child(pill)

	player_stats_label.text = "Pace: %.0f  |  Vision: %.0f%%  |  Comp: %.0f%%  |  Agg: %.0f%%\nForm: %.1f ★  |  Goals: %d  |  Assists: %d" % [
		p.top_speed, p.vision * 100.0, p.composure * 100.0, p.aggression * 100.0,
		p.form, p.career_goals, p.career_assists
	]

	# Stamina
	var st_ratio: float = _resolve_player_stamina(p)
	player_stamina_bar.value = st_ratio * 100.0
	player_stamina_label.text = "%d%%" % int(st_ratio * 100.0)

	# Populate role picker
	role_picker.clear()
	var is_gk_slot: bool = (_selected_starter_slot == 0)
	if is_gk_slot:
		role_picker.add_item("GK")
		role_picker.selected = 0
		role_picker.disabled = true
	else:
		role_picker.disabled = false
		for r: String in OUTFIELD_ROLES:
			role_picker.add_item(r)
		var r_idx: int = OUTFIELD_ROLES.find(active_role)
		role_picker.selected = r_idx if r_idx >= 0 else 0

	# Tactical role config sliders
	var config: PlayerRoleConfig = _get_or_create_slot_config(_selected_starter_slot, active_role)
	anchor_slider.value = config.anchor_weight
	anchor_val_label.text = "%.2f (%s)" % [config.anchor_weight, "Rigid" if config.anchor_weight > 0.65 else ("Roam" if config.anchor_weight < 0.45 else "Balanced")]

	press_slider.value = config.max_chase_distance
	press_val_label.text = "%.0f px" % config.max_chase_distance

	adv_slider.value = config.w_adv
	adv_val_label.text = "%.2f" % config.w_adv

	make_captain_btn.text = "Captain ★" if (_selected_starter_slot == _mgmt.captain_slot) else "Make Captain"
	make_captain_btn.disabled = (_selected_starter_slot == _mgmt.captain_slot)

	_updating_ui = false


func _get_or_create_slot_config(slot: int, role_name: String) -> PlayerRoleConfig:
	var existing: PlayerRoleConfig = _mgmt.get_slot_role_config(slot)
	if existing != null:
		return existing

	var path: String = ROLE_PRESET_PATHS.get(role_name, "res://shared/roles/role_cm.tres")
	var base_res := load(path) as PlayerRoleConfig
	var new_cfg: PlayerRoleConfig = base_res.duplicate() if base_res != null else PlayerRoleConfig.new()
	new_cfg.role_name = role_name
	_mgmt.set_slot_role_config(slot, new_cfg)
	return new_cfg


func _on_role_picker_selected(idx: int) -> void:
	if _updating_ui or _selected_starter_slot < 0:
		return
	var new_role: String = role_picker.get_item_text(idx)
	_mgmt.set_slot_role(_selected_starter_slot, new_role)

	# Create fresh config for the new role preset
	var path: String = ROLE_PRESET_PATHS.get(new_role, "res://shared/roles/role_cm.tres")
	var base_res := load(path) as PlayerRoleConfig
	var new_cfg: PlayerRoleConfig = base_res.duplicate() if base_res != null else PlayerRoleConfig.new()
	new_cfg.role_name = new_role
	_mgmt.set_slot_role_config(_selected_starter_slot, new_cfg)

	_refresh_all()
	lineup_changed.emit(_team_id)
	GameEvents.lineup_changed.emit(_team_id)


func _on_anchor_slider_changed(val: float) -> void:
	if _updating_ui or _selected_starter_slot < 0:
		return
	var role_str: String = _mgmt.get_slot_role(_selected_starter_slot)
	var config: PlayerRoleConfig = _get_or_create_slot_config(_selected_starter_slot, role_str)
	config.anchor_weight = val
	anchor_val_label.text = "%.2f (%s)" % [val, "Rigid" if val > 0.65 else ("Roam" if val < 0.45 else "Balanced")]
	_sync_live_player_role_config(_selected_starter_slot, config)


func _on_press_slider_changed(val: float) -> void:
	if _updating_ui or _selected_starter_slot < 0:
		return
	var role_str: String = _mgmt.get_slot_role(_selected_starter_slot)
	var config: PlayerRoleConfig = _get_or_create_slot_config(_selected_starter_slot, role_str)
	config.max_chase_distance = val
	press_val_label.text = "%.0f px" % val
	_sync_live_player_role_config(_selected_starter_slot, config)


func _on_adv_slider_changed(val: float) -> void:
	if _updating_ui or _selected_starter_slot < 0:
		return
	var role_str: String = _mgmt.get_slot_role(_selected_starter_slot)
	var config: PlayerRoleConfig = _get_or_create_slot_config(_selected_starter_slot, role_str)
	config.w_adv = val
	adv_val_label.text = "%.2f" % val
	_sync_live_player_role_config(_selected_starter_slot, config)


func _on_reset_role_pressed() -> void:
	if _selected_starter_slot < 0:
		return
	var default_role: String = FormationLibrary.get_formation(_mgmt.formation)[_selected_starter_slot].get("role", "CM")
	_mgmt.set_slot_role(_selected_starter_slot, default_role)
	var path: String = ROLE_PRESET_PATHS.get(default_role, "res://shared/roles/role_cm.tres")
	var base_res := load(path) as PlayerRoleConfig
	if base_res != null:
		_mgmt.set_slot_role_config(_selected_starter_slot, base_res.duplicate())
	_refresh_all()
	lineup_changed.emit(_team_id)
	GameEvents.lineup_changed.emit(_team_id)


func _on_make_captain_pressed() -> void:
	if _selected_starter_slot < 0 or _mgmt == null:
		return
	_mgmt.set_captain(_selected_starter_slot)
	_refresh_all()


func _sync_live_player_role_config(slot: int, config: PlayerRoleConfig) -> void:
	if not _is_in_match or _mgmt == null or slot >= _mgmt.lineup.size():
		return
	var target_sq_idx: int = _mgmt.lineup[slot]
	for player in _live_players:
		if is_instance_valid(player) and player.squad_index == target_sq_idx:
			player.role_config = config
			break


func _rebuild_bench_list() -> void:
	for child in bench_scroll_list.get_children():
		child.queue_free()

	if _mgmt == null or _mgmt.team == null:
		return

	for bi in range(_mgmt.bench.size()):
		var sq_idx: int = _mgmt.bench[bi]
		if sq_idx < 0 or sq_idx >= _mgmt.team.squad.size():
			continue
		var p: PlayerData = _mgmt.team.squad[sq_idx]

		if not _matches_pos_filter(p.position_role):
			continue

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var is_selected_bench: bool = (bi == _selected_bench_slot)

		var st_ratio: float = _resolve_player_stamina(p)
		var st_text: String = "Stamina:%d%%" % int(st_ratio * 100.0) if _is_in_match else ""

		var nat_emoji: String = NationDatabase.get_flag_emoji(p.nationality)
		btn.text = " %s #%d  %-14s [%-3s]  ★%.1f  Spd:%.0f Vis:%.0f  %s%s" % [
			nat_emoji, p.shirt_number, p.player_name, p.position_role, p.form,
			p.top_speed, p.vision * 100.0, st_text,
			"  ⚠ UNAVAIL" if p.is_unavailable else ""
		]

		var cannot_sub: bool = _is_in_match and (_mgmt.substitutions_used >= 3 or p.is_unavailable)
		btn.disabled = cannot_sub or p.is_unavailable

		if is_selected_bench:
			btn.modulate = Color(1.0, 0.9, 0.3)
		elif p.is_unavailable:
			btn.modulate = Color(0.5, 0.5, 0.5)

		var b := bi
		btn.pressed.connect(func(): _on_bench_item_clicked(b))
		bench_scroll_list.add_child(btn)


func _rebuild_starters_list() -> void:
	for child in starters_scroll_list.get_children():
		child.queue_free()

	if _mgmt == null or _mgmt.team == null:
		return

	for slot in range(_mgmt.lineup.size()):
		var sq_idx: int = _mgmt.lineup[slot]
		if sq_idx < 0 or sq_idx >= _mgmt.team.squad.size():
			continue
		var p: PlayerData = _mgmt.team.squad[sq_idx]
		var slot_role: String = _mgmt.get_slot_role(slot)

		var btn := Button.new()
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var is_selected: bool = (slot == _selected_starter_slot)

		var cap_marker: String = " (C)" if (slot == _mgmt.captain_slot) else ""
		var st_ratio: float = _resolve_player_stamina(p)
		var st_text: String = "Stamina:%d%%" % int(st_ratio * 100.0) if _is_in_match else ""

		var nat_emoji: String = NationDatabase.get_flag_emoji(p.nationality)
		btn.text = " %s #%d  %-14s [%-3s]  ★%.1f  Spd:%.0f%s  %s" % [
			nat_emoji, p.shirt_number, p.player_name + cap_marker, slot_role, p.form,
			p.top_speed, cap_marker, st_text
		]

		if is_selected:
			btn.modulate = Color(0.3, 0.9, 1.0)

		var s := slot
		btn.pressed.connect(func(): _on_starter_item_clicked(s))
		starters_scroll_list.add_child(btn)


func _on_starter_item_clicked(slot: int) -> void:
	if _selected_starter_slot == slot:
		_selected_starter_slot = -1
		pitch_view.set_selected_slot(-1)
		_update_inspector()
		_rebuild_starters_list()
		hint_label.text = "Deselected player."
	elif _selected_starter_slot >= 0:
		# Swapping two starters
		var prev_slot: int = _selected_starter_slot
		_mgmt.reshuffle(prev_slot, slot)
		_selected_starter_slot = slot
		pitch_view.set_selected_slot(slot)
		_refresh_all()
		lineup_changed.emit(_team_id)
		GameEvents.lineup_changed.emit(_team_id)
		hint_label.text = "Swapped starter positions."
	else:
		_selected_starter_slot = slot
		pitch_view.set_selected_slot(slot)
		_update_inspector()
		_rebuild_starters_list()
		hint_label.text = "Selected starter #%d. Click another starter or bench player to swap." % (slot + 1)


func _on_bench_item_clicked(bench_slot: int) -> void:
	if _selected_starter_slot >= 0:
		# Swap selected starter with clicked bench player
		var out_idx: int = _mgmt.lineup[_selected_starter_slot]
		var in_idx: int = _mgmt.bench[bench_slot]
		if _mgmt.swap(_selected_starter_slot, bench_slot, _is_in_match):
			if _is_in_match:
				substitution_made.emit(_team_id, out_idx, in_idx)
				GameEvents.substitution_made.emit(_team_id, out_idx, in_idx)
			lineup_changed.emit(_team_id)
			GameEvents.lineup_changed.emit(_team_id)
			hint_label.text = "Substituted #%d with #%d." % [_mgmt.team.squad[out_idx].shirt_number, _mgmt.team.squad[in_idx].shirt_number]
			_selected_starter_slot = -1
			pitch_view.set_selected_slot(-1)
			_refresh_all()
	else:
		_selected_bench_slot = bench_slot if _selected_bench_slot != bench_slot else -1
		_rebuild_bench_list()
		if _selected_bench_slot >= 0:
			hint_label.text = "Bench player selected. Click a starter on the pitch or in the XI list to swap in!"
		else:
			hint_label.text = "Bench selection cleared."


func _set_position_filter(filter: String) -> void:
	_filter_pos = filter
	_rebuild_bench_list()


func _matches_pos_filter(role: String) -> bool:
	if _filter_pos == "ALL":
		return true
	match _filter_pos:
		"GK":
			return role == "GK"
		"DEF":
			return role in ["CB", "LB", "RB", "LWB", "RWB"]
		"MID":
			return role in ["DM", "CDM", "CM", "LM", "RM", "AM", "CAM"]
		"ATT":
			return role in ["LW", "RW", "ST", "CF"]
		_:
			return true


func _resolve_player_stamina(p: PlayerData) -> float:
	if not _is_in_match:
		return 1.0
	for node in _live_players:
		if is_instance_valid(node) and node.squad_index == p.shirt_number:
			var max_st: float = maxf(node.stamina_max, 1.0)
			return clampf(node.current_stamina / max_st, 0.0, 1.0)
	return 1.0
