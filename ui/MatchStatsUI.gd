##
## MatchStatsUI
##
## Full-time overlay: a scoreboard page (final score, match duration,
## Continue), a stats page (possession/shots/passes/fouls/cards/corners/
## offsides side by side), and a player ratings page (per-player 1-10 scores,
## home/away columns) — three pages living on this one CanvasLayer rather than
## as separate scenes, so nothing needs to be re-instantiated between them.
##
## Flow: Scoreboard --[Continue]--> Team Stats --[Back to Menu]--> Player
## Ratings --[Back to Menu]--> Main Menu, with a [<- Back] on the ratings page
## returning to Team Stats. The stats page's button keeps its original label
## and now advances to ratings instead of exiting directly — only the ratings
## page's own "Back to Menu" actually leaves the match.
##
## Built entirely in code (no hand-authored child nodes in the .tscn) — same
## convention HUD.gd already uses for its shootout overlay and sub-banner.
##
## Depends on: GameManager, MatchStatsTracker, DataLoader, PlayerData.
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

## Rating thresholds and their label colours (Section: Page 3 layout).
const RATING_GOLD_THRESHOLD: float = 8.0
const RATING_GOLD_COLOR: Color = Color(0.82, 0.60, 0.0)
const RATING_LOW_THRESHOLD: float = 6.0
const RATING_LOW_COLOR: Color = Color(0.63, 0.18, 0.18)

var _score_label: Label = null
var _duration_label: Label = null
var _stats_home_name_label: Label = null
var _stats_away_name_label: Label = null
var _scoreboard_panel: PanelContainer = null
var _stats_panel: PanelContainer = null
var _ratings_panel: PanelContainer = null
var _home_value_labels: Array[Label] = []
var _away_value_labels: Array[Label] = []
var _home_ratings_vbox: VBoxContainer = null
var _away_ratings_vbox: VBoxContainer = null

var _team_a_name: String = "Team A"
var _team_b_name: String = "Team B"

## Cached by _prepare_ratings_data() at the page 1 -> page 2 transition so
## page 3 has no computation delay when the player reaches it.
var _cached_ratings: Dictionary[int, float] = {}


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

	_ratings_panel = _build_ratings_panel()
	_ratings_panel.visible = false
	content.add_child(_ratings_panel)


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
	back_button.pressed.connect(_on_stats_continue_pressed)
	vbox.add_child(back_button)

	return panel


func _build_ratings_panel() -> PanelContainer:
	var panel: PanelContainer = _build_panel_shell()
	panel.name = "RatingsPanel"

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "PLAYER RATINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	vbox.add_child(columns)

	_home_ratings_vbox = VBoxContainer.new()
	_home_ratings_vbox.add_theme_constant_override("separation", 4)
	_home_ratings_vbox.custom_minimum_size = Vector2(160.0, 0.0)
	columns.add_child(_home_ratings_vbox)

	_away_ratings_vbox = VBoxContainer.new()
	_away_ratings_vbox.add_theme_constant_override("separation", 4)
	_away_ratings_vbox.custom_minimum_size = Vector2(160.0, 0.0)
	columns.add_child(_away_ratings_vbox)

	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 12)
	vbox.add_child(button_row)

	var back_arrow_button := Button.new()
	back_arrow_button.text = "← Back"
	back_arrow_button.custom_minimum_size = Vector2(100.0, 36.0)
	back_arrow_button.pressed.connect(_on_ratings_back_arrow_pressed)
	button_row.add_child(back_arrow_button)

	var back_to_menu_button := Button.new()
	back_to_menu_button.text = "Back to Menu"
	back_to_menu_button.custom_minimum_size = Vector2(140.0, 36.0)
	back_to_menu_button.pressed.connect(_on_ratings_back_to_menu_pressed)
	button_row.add_child(back_to_menu_button)

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

	_cached_ratings.clear()
	_scoreboard_panel.visible = true
	_stats_panel.visible = false
	_ratings_panel.visible = false


func _format_stat(stat_key: String, value: Variant) -> String:
	if stat_key.ends_with("_pct"):
		return "%.0f%%" % float(value)
	return str(int(value))


func _on_continue_pressed() -> void:
	_scoreboard_panel.visible = false
	_stats_panel.visible = true
	_prepare_ratings_data()


## Page 2's original "Back to Menu" button — no longer exits directly. It now
## advances to the ratings page first; only the ratings page's own "Back to
## Menu" (_on_ratings_back_to_menu_pressed) actually leaves the match.
func _on_stats_continue_pressed() -> void:
	_stats_panel.visible = false
	_populate_ratings_page()
	_ratings_panel.visible = true


func _on_ratings_back_arrow_pressed() -> void:
	_ratings_panel.visible = false
	_stats_panel.visible = true


func _on_ratings_back_to_menu_pressed() -> void:
	stats_dismissed.emit()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## Runs the rating calculation once, ahead of the player reaching page 3.
func _prepare_ratings_data() -> void:
	_cached_ratings = MatchStatsTracker.compute_all_ratings()


func _populate_ratings_page() -> void:
	if _cached_ratings.is_empty():
		_prepare_ratings_data()
	_fill_ratings_column(_home_ratings_vbox, GameManager.TEAM_A)
	_fill_ratings_column(_away_ratings_vbox, GameManager.TEAM_B)


## player_id keys are `team * 1000 + squad_index` (see MatchStatsTracker) —
## decoded here rather than threaded through as a separate lookup table.
func _fill_ratings_column(vbox: VBoxContainer, team: int) -> void:
	for child: Node in vbox.get_children():
		child.queue_free()

	var rows: Array[Array] = []
	for key: int in _cached_ratings:
		if key / 1000 != team:
			continue
		var squad_index: int = key % 1000
		var player_data: PlayerData = DataLoader.get_player(team, squad_index)
		if player_data == null:
			continue
		var row: Array = [player_data, _cached_ratings[key]]
		rows.append(row)

	rows.sort_custom(_rating_row_sorts_higher_first)

	for row: Array in rows:
		vbox.add_child(_build_rating_row(row[0] as PlayerData, row[1] as float))


func _rating_row_sorts_higher_first(a: Array, b: Array) -> bool:
	return float(a[1]) > float(b[1])


func _build_rating_row(player_data: PlayerData, rating: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var number_label := Label.new()
	number_label.text = str(player_data.shirt_number)
	number_label.custom_minimum_size = Vector2(24.0, 0.0)
	row.add_child(number_label)

	var name_label := Label.new()
	name_label.text = _surname(player_data.player_name)
	name_label.custom_minimum_size = Vector2(96.0, 0.0)
	row.add_child(name_label)

	var rating_label := Label.new()
	rating_label.text = "%.1f" % rating
	rating_label.custom_minimum_size = Vector2(36.0, 0.0)
	rating_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if rating >= RATING_GOLD_THRESHOLD:
		rating_label.add_theme_color_override("font_color", RATING_GOLD_COLOR)
	elif rating < RATING_LOW_THRESHOLD:
		rating_label.add_theme_color_override("font_color", RATING_LOW_COLOR)
	row.add_child(rating_label)

	return row


func _surname(full_name: String) -> String:
	var parts: PackedStringArray = full_name.split(" ", false)
	if parts.is_empty():
		return full_name
	return parts[parts.size() - 1]
