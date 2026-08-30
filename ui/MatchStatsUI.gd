##
## MatchStatsUI
##
## Full-time overlay: a scoreboard page (final score, match duration, Continue)
## followed by a stats page (possession/shots/passes/fouls/cards/corners/
## offsides side by side) reached by pressing Continue — both pages live on
## this one CanvasLayer rather than as separate scenes, so nothing needs to be
## re-instantiated between them. "Back to Menu" on the stats page is the only
## way out, matching the brief: Continue advances to the stats screen, the
## stats screen is what actually returns to the main menu.
##
## Built entirely in code (no hand-authored child nodes in the .tscn) — same
## convention HUD.gd already uses for its shootout overlay and sub-banner.
##
## Depends on: GameManager, MatchStatsTracker.
## Exposes: populate(team_a_name, team_b_name), stats_dismissed signal.
##

class_name MatchStatsUI
extends CanvasLayer

## Path to the scene shown once the stats screen is dismissed.
const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"

## Order and display label for each stat row. Keys match
## MatchStatsTracker.get_stats() dictionary keys; "_pct" values render with a
## trailing "%".
const STAT_ROWS: Array[Array] = [
	["possession_pct", "Possession"],
	["shots", "Shots"],
	["shots_on_target", "Shots on Target"],
	["passes_attempted", "Passes Attempted"],
	["pass_completion_pct", "Pass Completion"],
	["fouls", "Fouls Committed"],
	["yellow_cards", "Yellow Cards"],
	["red_cards", "Red Cards"],
	["corners", "Corners"],
	["offsides", "Offsides"],
]

## Emitted once "Back to Menu" is pressed, before the scene change fires —
## PitchScene resets MatchStatsTracker in response.
signal stats_dismissed

var _score_label: Label = null
var _duration_label: Label = null
var _stats_home_name_label: Label = null
var _stats_away_name_label: Label = null
var _scoreboard_panel: PanelContainer = null
var _stats_panel: PanelContainer = null
var _home_value_labels: Array[Label] = []
var _away_value_labels: Array[Label] = []

var _team_a_name: String = "Team A"
var _team_b_name: String = "Team B"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.85)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var content := Control.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	_scoreboard_panel = _build_scoreboard_panel()
	content.add_child(_scoreboard_panel)

	_stats_panel = _build_stats_panel()
	_stats_panel.visible = false
	content.add_child(_stats_panel)


func _build_panel_shell() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.95)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 32.0
	style.content_margin_right = 32.0
	style.content_margin_top = 24.0
	style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", style)

	return panel


func _build_scoreboard_panel() -> PanelContainer:
	var panel: PanelContainer = _build_panel_shell()
	panel.name = "ScoreboardPanel"

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "FULL TIME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 22)
	vbox.add_child(_score_label)

	_duration_label = Label.new()
	_duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_duration_label)

	var continue_button := Button.new()
	continue_button.text = "Continue"
	continue_button.custom_minimum_size = Vector2(140.0, 36.0)
	continue_button.pressed.connect(_on_continue_pressed)
	vbox.add_child(continue_button)

	return panel


func _build_stats_panel() -> PanelContainer:
	var panel: PanelContainer = _build_panel_shell()
	panel.name = "StatsPanel"

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MATCH STATISTICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var header := HBoxContainer.new()
	vbox.add_child(header)

	_stats_home_name_label = Label.new()
	_stats_home_name_label.custom_minimum_size = Vector2(140.0, 0.0)
	_stats_home_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_stats_home_name_label)

	var header_spacer := Label.new()
	header_spacer.custom_minimum_size = Vector2(160.0, 0.0)
	header.add_child(header_spacer)

	_stats_away_name_label = Label.new()
	_stats_away_name_label.custom_minimum_size = Vector2(140.0, 0.0)
	_stats_away_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(_stats_away_name_label)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("v_separation", 6)
	grid.add_theme_constant_override("h_separation", 16)
	vbox.add_child(grid)

	_home_value_labels.clear()
	_away_value_labels.clear()
	for row: Array in STAT_ROWS:
		var stat_label_text: String = row[1]

		var home_value := Label.new()
		home_value.custom_minimum_size = Vector2(140.0, 0.0)
		home_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(home_value)
		_home_value_labels.append(home_value)

		var stat_label := Label.new()
		stat_label.text = stat_label_text
		stat_label.custom_minimum_size = Vector2(160.0, 0.0)
		stat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(stat_label)

		var away_value := Label.new()
		away_value.custom_minimum_size = Vector2(140.0, 0.0)
		away_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grid.add_child(away_value)
		_away_value_labels.append(away_value)

	var back_button := Button.new()
	back_button.text = "Back to Menu"
	back_button.custom_minimum_size = Vector2(140.0, 36.0)
	back_button.pressed.connect(_on_back_pressed)
	vbox.add_child(back_button)

	return panel


## Fills both pages from GameManager and MatchStatsTracker. Called once by
## PitchScene immediately before show().
func populate(team_a_name: String, team_b_name: String) -> void:
	_team_a_name = team_a_name
	_team_b_name = team_b_name

	_score_label.text = "%s   %s   %s" % [team_a_name, GameManager.get_score_string(), team_b_name]
	_duration_label.text = "Match Duration: %s" % GameManager.get_clock_string()

	_stats_home_name_label.text = team_a_name
	_stats_away_name_label.text = team_b_name

	var home_stats: Dictionary = MatchStatsTracker.get_stats(GameManager.TEAM_A)
	var away_stats: Dictionary = MatchStatsTracker.get_stats(GameManager.TEAM_B)

	for i: int in range(STAT_ROWS.size()):
		var stat_key: String = STAT_ROWS[i][0]
		_home_value_labels[i].text = _format_stat(stat_key, home_stats[stat_key])
		_away_value_labels[i].text = _format_stat(stat_key, away_stats[stat_key])

	_scoreboard_panel.visible = true
	_stats_panel.visible = false


func _format_stat(stat_key: String, value: Variant) -> String:
	if stat_key.ends_with("_pct"):
		return "%.0f%%" % float(value)
	return str(int(value))


func _on_continue_pressed() -> void:
	_scoreboard_panel.visible = false
	_stats_panel.visible = true


func _on_back_pressed() -> void:
	stats_dismissed.emit()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)
