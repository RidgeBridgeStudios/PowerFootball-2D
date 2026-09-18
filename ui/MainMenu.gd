##
## MainMenu
##
## Entry point of the game (res://ui/SplashScreen.tscn is run/main_scene and
## hands off here). Owns the three top-level menu buttons and the quit
## confirmation popup; OptionsMenu is a separate scene instanced as a child and
## shown/hidden as an overlay rather than a swapped scene, so the menu list
## underneath never has to reload state.
##
## The manager-only pivot retired the Kick Off and Practice Arena buttons along
## with the real-time PitchScene they launched, and with them the locked
## "Player Career" placeholder — Manager Mode is now the single playable mode.
##
## Depends on: OptionsMenu.
## Exposes: nothing — this is a scene root, not a service other scripts call into.
##

extends Control

const MENU_FONT_SIZE: int = 22
const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)
const TEXT_COLOR: Color = Color(0.909804, 0.941176, 0.913725)

@onready var menu_list: VBoxContainer = $MenuList
@onready var btn_manager: Button = $MenuList/ManagerButton
@onready var btn_quick_match: Button = $MenuList/QuickMatchButton
@onready var btn_jukebox: Button = $MenuList/JukeboxButton
@onready var btn_options: Button = $MenuList/OptionsButton
@onready var btn_quit: Button = $MenuList/QuitButton

@onready var options_menu: Control = $OptionsMenu
@onready var menu_music: AudioStreamPlayer = $MenuMusic

@onready var quit_dialog: ConfirmationDialog = $QuitDialog
@onready var jukebox_dialog: AcceptDialog = $JukeboxDialog
@onready var jukebox: Jukebox = $JukeboxDialog/Jukebox

var _last_focused_button: Button = null
var _quick_match_overlay: Control = null
var _qm_division_opt: OptionButton = null
var _qm_home_opt: OptionButton = null
var _qm_away_opt: OptionButton = null
var _qm_result_label: Label = null
var _qm_events_label: Label = null
var _qm_stats_label: Label = null
var _music_playlist: Array[AudioStream] = []
var _current_track_index: int = 0


func _ready() -> void:
	btn_manager.pressed.connect(_on_manager_pressed)
	if btn_quick_match != null:
		btn_quick_match.pressed.connect(_on_quick_match_pressed)
	if btn_jukebox != null:
		btn_jukebox.pressed.connect(_on_jukebox_pressed)
	btn_options.pressed.connect(_on_options_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

	options_menu.menu_closed.connect(_return_to_main_menu)

	quit_dialog.confirmed.connect(_on_quit_confirmed)
	quit_dialog.visibility_changed.connect(_on_quit_visibility_changed)
	if jukebox_dialog != null:
		jukebox_dialog.visibility_changed.connect(_on_jukebox_visibility_changed)
	if jukebox != null:
		jukebox.playlist_changed.connect(_on_jukebox_playlist_changed)
	if menu_music != null:
		menu_music.finished.connect(_on_menu_music_finished)

	_style_menu_buttons()
	_start_menu_music()
	_build_quick_match_overlay()
	btn_manager.grab_focus()


func _on_manager_pressed() -> void:
	# Entry point is the creation/slot screen, not the hub: it decides whether
	# to load an existing slot or start a new career, and only then hands off
	# to ManagerModeRoot with CareerManager already populated.
	get_tree().change_scene_to_file("res://ui/manager_mode/ManagerCreationScreen.tscn")


func _on_jukebox_pressed() -> void:
	_last_focused_button = btn_jukebox
	if jukebox_dialog != null:
		jukebox_dialog.popup_centered()


func _on_jukebox_visibility_changed() -> void:
	if jukebox_dialog != null and not jukebox_dialog.visible and is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()


func _on_options_pressed() -> void:
	_last_focused_button = btn_options
	menu_list.hide()
	options_menu.open()


func _on_quit_pressed() -> void:
	_last_focused_button = btn_quit
	quit_dialog.popup_centered()


func _on_quit_confirmed() -> void:
	get_tree().quit()


func _on_quit_visibility_changed() -> void:
	if not quit_dialog.visible and is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()


func _return_to_main_menu() -> void:
	options_menu.hide()
	menu_list.show()
	if is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()
	else:
		btn_manager.grab_focus()


## Every button left here is a real, focusable destination — the pivot removed
## the styled-but-locked "Coming Soon" pattern along with the Player Career
## placeholder that used it.
func _style_menu_buttons() -> void:
	var buttons: Array[Button] = [btn_manager, btn_options, btn_quit]
	if btn_quick_match != null:
		buttons.insert(1, btn_quick_match)
	if btn_jukebox != null:
		buttons.insert(buttons.size() - 2, btn_jukebox)
	for button: Button in buttons:
		button.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
		button.add_theme_color_override("font_color", TEXT_COLOR)
		button.add_theme_color_override("font_hover_color", ACCENT_COLOR)
		button.add_theme_color_override("font_pressed_color", ACCENT_COLOR)
		button.add_theme_color_override("font_focus_color", ACCENT_COLOR)
		button.add_theme_stylebox_override("normal", _make_stylebox(Color(0.0, 0.0, 0.0, 0.0), 0))
		button.add_theme_stylebox_override("hover", _make_stylebox(Color(0.24, 0.86, 0.41, 0.06), 4))
		button.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.24, 0.86, 0.41, 0.1), 4))
		button.add_theme_stylebox_override("focus", _make_stylebox(Color(0.24, 0.86, 0.41, 0.06), 4))


func _on_quick_match_pressed() -> void:
	_last_focused_button = btn_quick_match
	menu_list.hide()
	_populate_quick_match_teams()
	_quick_match_overlay.show()


func _build_quick_match_overlay() -> void:
	_quick_match_overlay = Control.new()
	_quick_match_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quick_match_overlay.visible = false
	add_child(_quick_match_overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320.0
	panel.offset_top = -240.0
	panel.offset_right = 320.0
	panel.offset_bottom = 240.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.05, 0.95)
	style.border_color = ACCENT_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)
	_quick_match_overlay.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)

	var title := Label.new()
	title.text = "⚡ QUICK MATCH SIMULATION"
	title.add_theme_font_size_override("font_size", 22)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)

	var div_row := HBoxContainer.new()
	var div_lbl := Label.new()
	div_lbl.text = "Division:"
	div_lbl.custom_minimum_size = Vector2(100, 0)
	div_row.add_child(div_lbl)
	_qm_division_opt = OptionButton.new()
	_qm_division_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_qm_division_opt.item_selected.connect(_on_qm_division_selected)
	div_row.add_child(_qm_division_opt)
	layout.add_child(div_row)

	var home_row := HBoxContainer.new()
	var home_lbl := Label.new()
	home_lbl.text = "Home Team:"
	home_lbl.custom_minimum_size = Vector2(100, 0)
	home_row.add_child(home_lbl)
	_qm_home_opt = OptionButton.new()
	_qm_home_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	home_row.add_child(_qm_home_opt)
	layout.add_child(home_row)

	var away_row := HBoxContainer.new()
	var away_lbl := Label.new()
	away_lbl.text = "Away Team:"
	away_lbl.custom_minimum_size = Vector2(100, 0)
	away_row.add_child(away_lbl)
	_qm_away_opt = OptionButton.new()
	_qm_away_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	away_row.add_child(_qm_away_opt)
	layout.add_child(away_row)

	var sim_btn := Button.new()
	sim_btn.text = "⚽ Kick Off Simulation"
	sim_btn.custom_minimum_size = Vector2(0, 38)
	sim_btn.pressed.connect(_on_qm_simulate_pressed)
	layout.add_child(sim_btn)

	_qm_result_label = Label.new()
	_qm_result_label.add_theme_font_size_override("font_size", 20)
	_qm_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_qm_result_label)

	_qm_events_label = Label.new()
	_qm_events_label.add_theme_font_size_override("font_size", 13)
	_qm_events_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qm_events_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_qm_events_label)

	_qm_stats_label = Label.new()
	_qm_stats_label.add_theme_font_size_override("font_size", 12)
	_qm_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_qm_stats_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	layout.add_child(_qm_stats_label)

	var back_btn := Button.new()
	back_btn.text = "← Back to Menu"
	back_btn.pressed.connect(_on_qm_back_pressed)
	layout.add_child(back_btn)


func _populate_quick_match_teams() -> void:
	if DataLoader.league == null:
		return
	_qm_division_opt.clear()
	if not DataLoader.divisions.is_empty():
		_qm_division_opt.get_parent().show()
		for d: Dictionary in DataLoader.divisions:
			_qm_division_opt.add_item(str(d.get("name", "Division")))
	else:
		_qm_division_opt.get_parent().hide()
	_refresh_team_options()


func _on_qm_division_selected(idx: int) -> void:
	if idx >= 0 and idx < DataLoader.divisions.size():
		DataLoader.load_division_shard(DataLoader.divisions[idx])
	_refresh_team_options()


func _refresh_team_options() -> void:
	if DataLoader.league == null:
		return
	_qm_home_opt.clear()
	_qm_away_opt.clear()

	var teams_to_show: Array[TeamData] = []
	if not DataLoader.divisions.is_empty() and _qm_division_opt.item_count > 0:
		var sel_div: int = _qm_division_opt.selected
		if sel_div >= 0 and sel_div < DataLoader.divisions.size():
			var desc: Dictionary = DataLoader.divisions[sel_div]
			var start_idx: int = DataLoader._get_division_start_team_index(desc)
			var count: int = int(desc.get("team_count", 0))
			for i: int in range(count):
				var t_idx: int = start_idx + i
				if t_idx < DataLoader.league.teams.size():
					teams_to_show.append(DataLoader.league.teams[t_idx])
	if teams_to_show.is_empty():
		teams_to_show = DataLoader.league.teams

	for i: int in range(teams_to_show.size()):
		var t: TeamData = teams_to_show[i]
		_qm_home_opt.add_item(t.team_name, i)
		_qm_away_opt.add_item(t.team_name, i)

	if teams_to_show.size() >= 2:
		_qm_home_opt.select(0)
		_qm_away_opt.select(1)


func _on_qm_simulate_pressed() -> void:
	if DataLoader.league == null:
		return
	var h_idx: int = _qm_home_opt.get_selected_id()
	var a_idx: int = _qm_away_opt.get_selected_id()
	var home: TeamData = DataLoader.get_team(h_idx)
	var away: TeamData = DataLoader.get_team(a_idx)
	if home == null or away == null:
		return

	var home_mgr: ManagerData = ManagerLoader.get_or_assign_manager(home.team_name)
	var away_mgr: ManagerData = ManagerLoader.get_or_assign_manager(away.team_name)
	var ref: RefereeData = RefereeLoader.get_or_assign_referee(home.team_name, away.team_name)

	var result: QuickSimEngine.QuickSimResult = QuickSimEngine.simulate_match(
		home, away, home_mgr, away_mgr, ref, home.lineup_indices, away.lineup_indices
	)

	_qm_result_label.text = "%s  %d - %d  %s" % [
		home.team_name, result.home_score, result.away_score, away.team_name
	]

	var event_strs: Array[String] = []
	for ev: QuickSimEngine.MatchEventRecord in result.events:
		if ev.event_type == "goal":
			event_strs.append("⚽ %d' %s" % [ev.minute, ev.player_name])
		elif ev.event_type == "red_card":
			event_strs.append("🟥 %d' %s" % [ev.minute, ev.player_name])
	_qm_events_label.text = " | ".join(event_strs) if not event_strs.is_empty() else "No major match events"

	var h_shots: int = int(result.home_stats.get("shots", 0))
	var a_shots: int = int(result.away_stats.get("shots", 0))
	var h_poss: int = int(result.home_stats.get("possession_pct", 50))
	var a_poss: int = 100 - h_poss
	_qm_stats_label.text = "Possession: %d%% - %d%%  |  Shots: %d - %d  |  xG: %.2f - %.2f" % [
		h_poss, a_poss, h_shots, a_shots, result.probabilities.home_xg, result.probabilities.away_xg
	]


func _on_qm_back_pressed() -> void:
	_quick_match_overlay.hide()
	menu_list.show()
	if is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()
	else:
		btn_manager.grab_focus()


## OptionsMenu is an overlay shown/hidden inside this same scene (see class doc
## above), so this single player already covers both the main menu list and the
## options screen with no extra wiring.
func _start_menu_music() -> void:
	if jukebox != null and not jukebox.get_active_playlist().is_empty():
		_music_playlist = jukebox.get_active_playlist().duplicate()
	elif menu_music != null and menu_music.stream != null:
		_music_playlist = [menu_music.stream]
	_current_track_index = 0
	_play_current_track()


func _play_current_track() -> void:
	if menu_music == null:
		return
	if _music_playlist.is_empty():
		menu_music.stop()
		return

	if _current_track_index >= _music_playlist.size() or _current_track_index < 0:
		_current_track_index = 0

	var stream: AudioStream = _music_playlist[_current_track_index]
	if stream == null:
		return

	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = (
			AudioStreamWAV.LOOP_FORWARD if _music_playlist.size() == 1 else AudioStreamWAV.LOOP_DISABLED
		)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = (_music_playlist.size() == 1)

	menu_music.stream = stream
	menu_music.bus = &"Music"
	menu_music.play()


func _on_menu_music_finished() -> void:
	if _music_playlist.is_empty():
		return
	_current_track_index = (_current_track_index + 1) % _music_playlist.size()
	_play_current_track()


func _on_jukebox_playlist_changed(active_playlist: Array[AudioStream]) -> void:
	_music_playlist = active_playlist.duplicate()
	if _music_playlist.is_empty():
		if menu_music != null:
			menu_music.stop()
		return

	var current_stream: AudioStream = menu_music.stream if menu_music != null else null
	var found_idx: int = _music_playlist.find(current_stream)
	if found_idx != -1:
		_current_track_index = found_idx
		if current_stream is AudioStreamWAV:
			(current_stream as AudioStreamWAV).loop_mode = (
				AudioStreamWAV.LOOP_FORWARD if _music_playlist.size() == 1 else AudioStreamWAV.LOOP_DISABLED
			)
		elif current_stream is AudioStreamOggVorbis:
			(current_stream as AudioStreamOggVorbis).loop = (_music_playlist.size() == 1)
		if menu_music != null and not menu_music.playing:
			menu_music.play()
	else:
		_current_track_index = 0
		_play_current_track()


func _make_stylebox(bg_color: Color, left_border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_width_left = left_border
	box.border_color = ACCENT_COLOR
	box.content_margin_left = 32.0
	box.content_margin_right = 32.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box
