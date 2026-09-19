##
## MatchStatsUI
##
## Full-time interactive match analytics overlay.
## Features:
##   - Sleek Tab Navigation:
##     Tab 0: Match Summary & Man of the Match (MOTM) Spotlight
##     Tab 1: Traditional Match Statistics (with comparative progress bars)
##     Tab 2: Moneyball & Advanced Analytics Dashboard (with metric explanations & visual bars)
##     Tab 3: Comprehensive 22-Player Performance Matrix (ratings badges, xG, xA, ΔxT, Packing, Tackles, VAEP)
##   - Team color-coded visual comparison bars and leader highlights
##   - Seamless modal overlay mode or scene-return navigation
##
## Depends on: GameManager, MatchStatsTracker, DataLoader, PlayerData, PlayerRatingCalculator.
## Exposes: populate(team_a_name, team_b_name), stats_dismissed signal,
##          custom_return_scene, is_overlay_mode.
##

class_name MatchStatsUI
extends CanvasLayer

const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"
const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)
const GOLD_COLOR: Color = Color(1.0, 0.82, 0.2)
const SILVER_COLOR: Color = Color(0.85, 0.88, 0.92)
const LOW_RATING_COLOR: Color = Color(0.9, 0.35, 0.35)
const GOOD_RATING_COLOR: Color = Color(0.24, 0.86, 0.5)

signal stats_dismissed

var custom_return_scene: String = ""
var is_overlay_mode: bool = false

## Order and display label for traditional stat rows.
const STAT_ROWS: Array[Array] = [
	["possession_pct", "Possession", "pct"],
	["shots", "Total Shots", "int"],
	["shots_on_target", "Shots on Target", "int"],
	["passes_attempted", "Passes Attempted", "int"],
	["pass_completion_pct", "Pass Completion", "pct"],
	["corners", "Corner Kicks", "int"],
	["fouls", "Fouls Committed", "int"],
	["yellow_cards", "Yellow Cards", "int"],
	["red_cards", "Red Cards", "int"],
	["offsides", "Offsides", "int"],
]

## Order, display format, and analytical description for Moneyball stat rows.
const ADVANCED_STAT_ROWS: Array[Array] = [
	["xg", "Expected Goals (xG)", "float_2", "Total quality of goalscoring chances generated"],
	["psxg", "Post-Shot xG (PSxG)", "float_2", "Shot placement accuracy and difficulty for goalkeeper"],
	["goals_prevented", "GK Goals Prevented", "float_2", "Goals saved above/below expectation (PSxG - Conceded)"],
	["field_tilt_pct", "Field Tilt %", "pct", "Share of territorial possession in opponent final third"],
	["ppda", "PPDA (Pressing Index)", "float_1", "Passes allowed per defensive action (lower = more intense press)"],
	["xt_delta", "Expected Threat (ΔxT)", "float_2", "Net value added by advancing ball into dangerous attacking zones"],
	["packing_total", "Packing Rate", "int", "Opponent players bypassed with forward passes"],
	["impect_total", "Impect Rate", "int", "Opponent defenders bypassed into shooting positions"],
	["progressive_passes", "Progressive Passes", "int", "Completed passes moving ball ≥25% closer to goal"],
	["progressive_carries", "Progressive Carries", "int", "Controlled runs moving ball ≥25% closer to goal"],
	["vaep_total", "Team VAEP Score", "float_2", "Holistic player action value on winning probability"],
]

enum TabIndex { SUMMARY = 0, STATS = 1, ADVANCED = 2, RATINGS = 3 }

var _current_tab: TabIndex = TabIndex.SUMMARY

var _team_a_name: String = "Team A"
var _team_b_name: String = "Team B"
var _cached_ratings: Dictionary[int, float] = {}

# Top banner nodes
var _banner_score_label: Label = null
var _banner_home_name: Button = null
var _banner_away_name: Button = null
var _banner_headline: Label = null

# Tab buttons
var _tab_buttons: Array[Button] = []

# Panels
var _panels: Array[PanelContainer] = []
var _summary_panel: PanelContainer = null
var _stats_panel: PanelContainer = null
var _advanced_panel: PanelContainer = null
var _ratings_panel: PanelContainer = null

# Summary page nodes
var _motm_card_box: VBoxContainer = null
var _summary_bars_vbox: VBoxContainer = null

# Traditional stats widgets
var _stats_rows_vbox: VBoxContainer = null

# Advanced stats widgets
var _adv_rows_vbox: VBoxContainer = null

# Player performance matrix widgets
var _home_matrix_vbox: VBoxContainer = null
var _away_matrix_vbox: VBoxContainer = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.name = "DimBackground"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.02, 0.94)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var root_box := VBoxContainer.new()
	root_box.name = "RootBox"
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 10)
	root_box.offset_left = 32.0
	root_box.offset_top = 16.0
	root_box.offset_right = -32.0
	root_box.offset_bottom = -16.0
	add_child(root_box)

	# 1. Top Match Score Banner
	var top_banner := _build_match_banner()
	root_box.add_child(top_banner)

	# 2. Modern Tab Navigation Bar
	var tab_bar := _build_tab_bar()
	root_box.add_child(tab_bar)

	# 3. Content Panel Container (holds the 4 tab views)
	var content_holder := PanelContainer.new()
	content_holder.name = "ContentHolder"
	content_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.08, 0.07, 0.95)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_bottom = 16.0
	content_holder.add_theme_stylebox_override("panel", panel_style)
	root_box.add_child(content_holder)

	_summary_panel = _build_summary_tab()
	_stats_panel = _build_traditional_stats_tab()
	_advanced_panel = _build_advanced_stats_tab()
	_ratings_panel = _build_ratings_tab()

	_panels = [_summary_panel, _stats_panel, _advanced_panel, _ratings_panel]
	for p: PanelContainer in _panels:
		content_holder.add_child(p)

	# 4. Bottom Action Bar
	var bottom_bar := _build_bottom_bar()
	root_box.add_child(bottom_bar)

	_switch_tab(TabIndex.SUMMARY)


func _build_match_banner() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.04, 0.90)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 20.0
	style.content_margin_right = 20.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 24)
	panel.add_child(hbox)

	_banner_home_name = CareerTheme.team_link(_team_a_name, 240, ACCENT_COLOR)
	_banner_home_name.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_banner_home_name.add_theme_font_size_override("font_size", 22)
	_banner_home_name.pressed.connect(func() -> void:
		CareerTheme.DatabaseViewerScript.call(&"inspect_team", _team_a_name)
	)
	hbox.add_child(_banner_home_name)

	var score_box := VBoxContainer.new()
	score_box.alignment = BoxContainer.ALIGNMENT_CENTER
	score_box.add_theme_constant_override("separation", 2)

	var ft_badge := Label.new()
	ft_badge.text = "FULL TIME"
	ft_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ft_badge.add_theme_font_size_override("font_size", 12)
	ft_badge.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	score_box.add_child(ft_badge)

	_banner_score_label = Label.new()
	_banner_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_score_label.add_theme_font_size_override("font_size", 30)
	_banner_score_label.text = "0 - 0"
	score_box.add_child(_banner_score_label)

	_banner_headline = Label.new()
	_banner_headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_headline.add_theme_font_size_override("font_size", 12)
	_banner_headline.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	score_box.add_child(_banner_headline)

	hbox.add_child(score_box)

	_banner_away_name = CareerTheme.team_link(_team_b_name, 240, Color(0.9, 0.9, 0.9))
	_banner_away_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_banner_away_name.add_theme_font_size_override("font_size", 22)
	_banner_away_name.pressed.connect(func() -> void:
		CareerTheme.DatabaseViewerScript.call(&"inspect_team", _team_b_name)
	)
	hbox.add_child(_banner_away_name)

	return panel


func _build_tab_bar() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)

	var tab_names: Array[String] = [
		"🏆 Overview & Summary",
		"📊 Match Statistics",
		"💡 Moneyball Analytics",
		"👥 Player Ratings & Matrix"
	]

	_tab_buttons.clear()
	for i: int in range(tab_names.size()):
		var btn := Button.new()
		btn.text = tab_names[i]
		btn.custom_minimum_size = Vector2(200.0, 36.0)
		var t_idx: TabIndex = i as TabIndex
		btn.pressed.connect(func(): _switch_tab(t_idx))
		_tab_buttons.append(btn)
		hbox.add_child(btn)

	return hbox


func _build_summary_tab() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SummaryTab"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 16)
	scroll.add_child(vbox)

	# Top Highlights Row (MOTM Card + Quick Comparison Bars)
	var highlights_row := HBoxContainer.new()
	highlights_row.add_theme_constant_override("separation", 20)
	vbox.add_child(highlights_row)

	# Left: MOTM Spotlight Card
	var motm_panel := PanelContainer.new()
	motm_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	motm_panel.size_flags_stretch_ratio = 1.0
	var motm_style := StyleBoxFlat.new()
	motm_style.bg_color = Color(0.10, 0.12, 0.10, 0.95)
	motm_style.border_width_left = 2
	motm_style.border_color = GOLD_COLOR
	motm_style.corner_radius_top_left = 6
	motm_style.corner_radius_top_right = 6
	motm_style.corner_radius_bottom_left = 6
	motm_style.corner_radius_bottom_right = 6
	motm_style.content_margin_left = 16.0
	motm_style.content_margin_right = 16.0
	motm_style.content_margin_top = 12.0
	motm_style.content_margin_bottom = 12.0
	motm_panel.add_theme_stylebox_override("panel", motm_style)

	_motm_card_box = VBoxContainer.new()
	_motm_card_box.add_theme_constant_override("separation", 6)
	motm_panel.add_child(_motm_card_box)
	highlights_row.add_child(motm_panel)

	# Right: Key Match Visual Comparison Bars
	var bars_panel := PanelContainer.new()
	bars_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars_panel.size_flags_stretch_ratio = 1.3
	var bars_style := StyleBoxFlat.new()
	bars_style.bg_color = Color(0.08, 0.10, 0.08, 0.95)
	bars_style.corner_radius_top_left = 6
	bars_style.corner_radius_top_right = 6
	bars_style.corner_radius_bottom_left = 6
	bars_style.corner_radius_bottom_right = 6
	bars_style.content_margin_left = 16.0
	bars_style.content_margin_right = 16.0
	bars_style.content_margin_top = 12.0
	bars_style.content_margin_bottom = 12.0
	bars_panel.add_theme_stylebox_override("panel", bars_style)

	_summary_bars_vbox = VBoxContainer.new()
	_summary_bars_vbox.add_theme_constant_override("separation", 8)
	bars_panel.add_child(_summary_bars_vbox)
	highlights_row.add_child(bars_panel)

	return panel


func _build_traditional_stats_tab() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "TraditionalStatsTab"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	_stats_rows_vbox = VBoxContainer.new()
	_stats_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_rows_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_stats_rows_vbox)

	return panel


func _build_advanced_stats_tab() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "AdvancedStatsTab"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	_adv_rows_vbox = VBoxContainer.new()
	_adv_rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_adv_rows_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(_adv_rows_vbox)

	return panel


func _build_ratings_tab() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "RatingsTab"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 24)
	scroll.add_child(hbox)

	_home_matrix_vbox = VBoxContainer.new()
	_home_matrix_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_matrix_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(_home_matrix_vbox)

	_away_matrix_vbox = VBoxContainer.new()
	_away_matrix_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_away_matrix_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(_away_matrix_vbox)

	return panel


func _build_bottom_bar() -> HBoxContainer:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)

	var prev_btn := Button.new()
	prev_btn.text = "← Previous"
	prev_btn.custom_minimum_size = Vector2(130.0, 36.0)
	prev_btn.pressed.connect(_on_prev_pressed)
	hbox.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "Next →"
	next_btn.custom_minimum_size = Vector2(130.0, 36.0)
	next_btn.pressed.connect(_on_next_pressed)
	hbox.add_child(next_btn)

	var done_btn := Button.new()
	done_btn.text = "Return / Continue"
	done_btn.custom_minimum_size = Vector2(180.0, 36.0)
	done_btn.add_theme_color_override("font_color", ACCENT_COLOR)
	done_btn.pressed.connect(_on_ratings_back_to_menu_pressed)
	hbox.add_child(done_btn)

	return hbox


func _switch_tab(tab_idx: TabIndex) -> void:
	_current_tab = tab_idx
	for i: int in range(_panels.size()):
		_panels[i].visible = (i == int(_current_tab))
		if i < _tab_buttons.size():
			if i == int(_current_tab):
				_tab_buttons[i].add_theme_color_override("font_color", ACCENT_COLOR)
			else:
				_tab_buttons[i].remove_theme_color_override("font_color")


func _on_prev_pressed() -> void:
	var prev: int = (int(_current_tab) - 1 + _panels.size()) % _panels.size()
	_switch_tab(prev as TabIndex)


func _on_next_pressed() -> void:
	var next_val: int = (int(_current_tab) + 1) % _panels.size()
	_switch_tab(next_val as TabIndex)


## Populates all 4 tabs with match data from MatchStatsTracker and GameManager.
func populate(team_a_name: String, team_b_name: String) -> void:
	_team_a_name = team_a_name
	_team_b_name = team_b_name

	# Update top banner
	_banner_home_name.text = team_a_name
	_banner_away_name.text = team_b_name
	_banner_score_label.text = "%d - %d" % [GameManager.score[0], GameManager.score[1]]

	if GameManager.score[0] > GameManager.score[1]:
		_banner_headline.text = "%s victory at full time" % team_a_name
	elif GameManager.score[1] > GameManager.score[0]:
		_banner_headline.text = "%s claim victory away from home" % team_b_name
	else:
		_banner_headline.text = "Stalemate at full time — honors even"

	# Compute ratings once
	_cached_ratings = MatchStatsTracker.compute_all_ratings()

	_populate_summary_tab()
	_populate_traditional_stats()
	_populate_advanced_stats()
	_populate_ratings_matrix()

	_switch_tab(TabIndex.SUMMARY)


func _populate_summary_tab() -> void:
	for child: Node in _motm_card_box.get_children():
		child.queue_free()
	for child: Node in _summary_bars_vbox.get_children():
		child.queue_free()

	# 1. Find Man of the Match (highest rated player)
	var best_key: int = -1
	var best_rating: float = -1.0
	for key: int in _cached_ratings:
		var r: float = _cached_ratings[key]
		if r > best_rating:
			best_rating = r
			best_key = key

	var motm_p: PlayerData = null
	var motm_team_name: String = ""
	var motm_events: PlayerRatingCalculator.PlayerMatchEvents = null

	if best_key != -1:
		var team_id: int = best_key / 1000
		var sq_idx: int = best_key % 1000
		motm_p = DataLoader.get_player(team_id, sq_idx)
		motm_team_name = _team_a_name if team_id == 0 else _team_b_name
		motm_events = MatchStatsTracker.get_player_events(best_key)

	var title_lbl := Label.new()
	title_lbl.text = "⭐  MAN OF THE MATCH"
	title_lbl.add_theme_color_override("font_color", GOLD_COLOR)
	title_lbl.add_theme_font_size_override("font_size", 16)
	_motm_card_box.add_child(title_lbl)

	if motm_p != null:
		var name_btn: Button = CareerTheme.player_link(motm_p)
		name_btn.text = "%s (#%d, %s)" % [motm_p.player_name, motm_p.shirt_number, motm_p.position_role]
		name_btn.add_theme_font_size_override("font_size", 20)
		_motm_card_box.add_child(name_btn)

		var team_btn: Button = CareerTheme.team_link(motm_team_name)
		team_btn.add_theme_color_override("font_color", Color(0.7, 0.85, 0.7))
		_motm_card_box.add_child(team_btn)

		var rtg_lbl := Label.new()
		rtg_lbl.text = "Match Rating: %.1f / 10.0" % best_rating
		rtg_lbl.add_theme_font_size_override("font_size", 18)
		rtg_lbl.add_theme_color_override("font_color", GOLD_COLOR)
		_motm_card_box.add_child(rtg_lbl)

		if motm_events != null:
			var stats_desc := Label.new()
			var parts: Array[String] = []
			if motm_events.goals > 0:
				parts.append("⚽ %d Goals" % motm_events.goals)
			if motm_events.assists > 0:
				parts.append("🎯 %d Assists" % motm_events.assists)
			if motm_events.shots_on_target > 0:
				parts.append("%d Shots on Target (%.2f xG)" % [motm_events.shots_on_target, motm_events.xg])
			if motm_events.tackles_won > 0:
				parts.append("%d Tackles Won" % motm_events.tackles_won)
			if motm_events.packing_count > 0:
				parts.append("%d Bypassed (Packing)" % motm_events.packing_count)
			if motm_events.kept_clean_sheet:
				parts.append("🛡 Clean Sheet")
			stats_desc.text = " • ".join(parts) if not parts.is_empty() else "Comprehensive all-round midfield display"
			stats_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			stats_desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
			_motm_card_box.add_child(stats_desc)

	# 2. Key Highlights Comparison Bars
	var h_stats: Dictionary = MatchStatsTracker.get_stats(0)
	var a_stats: Dictionary = MatchStatsTracker.get_stats(1)
	var h_adv: Dictionary = MatchStatsTracker.get_advanced_stats(0)
	var a_adv: Dictionary = MatchStatsTracker.get_advanced_stats(1)

	var bars_title := Label.new()
	bars_title.text = "KEY MATCH COMPARISONS"
	bars_title.add_theme_color_override("font_color", ACCENT_COLOR)
	bars_title.add_theme_font_size_override("font_size", 16)
	_summary_bars_vbox.add_child(bars_title)

	_summary_bars_vbox.add_child(_create_stat_bar_row("Possession Share", float(h_stats["possession_pct"]), float(a_stats["possession_pct"]), "%.0f%%"))
	_summary_bars_vbox.add_child(_create_stat_bar_row("Expected Goals (xG)", float(h_adv["xg"]), float(a_adv["xg"]), "%.2f"))
	_summary_bars_vbox.add_child(_create_stat_bar_row("Field Tilt % (Final Third)", float(h_adv["field_tilt_pct"]), float(a_adv["field_tilt_pct"]), "%.0f%%"))
	_summary_bars_vbox.add_child(_create_stat_bar_row("Total Shots", float(h_stats["shots"]), float(a_stats["shots"]), "%.0f"))
	_summary_bars_vbox.add_child(_create_stat_bar_row("Packing Rate (Bypassed)", float(h_adv["packing_total"]), float(a_adv["packing_total"]), "%.0f"))


func _populate_traditional_stats() -> void:
	for child: Node in _stats_rows_vbox.get_children():
		child.queue_free()

	var h_stats: Dictionary = MatchStatsTracker.get_stats(0)
	var a_stats: Dictionary = MatchStatsTracker.get_stats(1)

	for row_def: Array in STAT_ROWS:
		var stat_key: String = row_def[0]
		var stat_label: String = row_def[1]
		var fmt: String = row_def[2]
		var val_h: float = float(h_stats[stat_key])
		var val_a: float = float(a_stats[stat_key])

		var fmt_str: String = "%.0f%%" if fmt == "pct" else "%.0f"
		_stats_rows_vbox.add_child(_create_stat_bar_row(stat_label, val_h, val_a, fmt_str))


func _populate_advanced_stats() -> void:
	for child: Node in _adv_rows_vbox.get_children():
		child.queue_free()

	var h_adv: Dictionary = MatchStatsTracker.get_advanced_stats(0)
	var a_adv: Dictionary = MatchStatsTracker.get_advanced_stats(1)

	for row_def: Array in ADVANCED_STAT_ROWS:
		var stat_key: String = row_def[0]
		var stat_label: String = row_def[1]
		var fmt: String = row_def[2]
		var desc: String = row_def[3]

		var val_h: float = float(h_adv[stat_key])
		var val_a: float = float(a_adv[stat_key])

		var fmt_str: String = "%.0f%%" if fmt == "pct" else ("%.2f" if fmt == "float_2" else ("%.1f" if fmt == "float_1" else "%.0f"))
		var card := _create_advanced_metric_card(stat_label, desc, val_h, val_a, fmt_str)
		_adv_rows_vbox.add_child(card)


func _create_stat_bar_row(label_text: String, val_h: float, val_a: float, fmt_str: String) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)

	var header_hbox := HBoxContainer.new()
	var h_val_lbl := Label.new()
	h_val_lbl.text = fmt_str % val_h
	h_val_lbl.custom_minimum_size = Vector2(80.0, 0.0)
	h_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	h_val_lbl.add_theme_color_override("font_color", ACCENT_COLOR if val_h >= val_a else Color(0.8, 0.8, 0.8))
	header_hbox.add_child(h_val_lbl)

	var title_lbl := Label.new()
	title_lbl.text = label_text
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	header_hbox.add_child(title_lbl)

	var a_val_lbl := Label.new()
	a_val_lbl.text = fmt_str % val_a
	a_val_lbl.custom_minimum_size = Vector2(80.0, 0.0)
	a_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	a_val_lbl.add_theme_color_override("font_color", ACCENT_COLOR if val_a >= val_h else Color(0.8, 0.8, 0.8))
	header_hbox.add_child(a_val_lbl)

	vbox.add_child(header_hbox)

	# Split progress bar
	var bar_container := HBoxContainer.new()
	bar_container.add_theme_constant_override("separation", 4)
	bar_container.custom_minimum_size = Vector2(0.0, 6.0)

	var total: float = maxf(val_h + val_a, 0.001)
	var ratio_h: float = clampf(val_h / total, 0.05, 0.95)

	var bar_h := ProgressBar.new()
	bar_h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_h.size_flags_stretch_ratio = ratio_h
	bar_h.show_percentage = false
	var style_h := StyleBoxFlat.new()
	style_h.bg_color = ACCENT_COLOR if val_h >= val_a else Color(0.2, 0.5, 0.3)
	style_h.corner_radius_top_left = 3
	style_h.corner_radius_bottom_left = 3
	bar_h.add_theme_stylebox_override("fill", style_h)
	bar_container.add_child(bar_h)

	var bar_a := ProgressBar.new()
	bar_a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_a.size_flags_stretch_ratio = 1.0 - ratio_h
	bar_a.show_percentage = false
	var style_a := StyleBoxFlat.new()
	style_a.bg_color = ACCENT_COLOR if val_a > val_h else Color(0.3, 0.3, 0.4)
	style_a.corner_radius_top_right = 3
	style_a.corner_radius_bottom_right = 3
	bar_a.add_theme_stylebox_override("fill", style_a)
	bar_container.add_child(bar_a)

	vbox.add_child(bar_container)

	return vbox


func _create_advanced_metric_card(title: String, desc: String, val_h: float, val_a: float, fmt_str: String) -> PanelContainer:
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.09, 0.90)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# Top row: Home Value | Metric Name | Away Value
	var header := HBoxContainer.new()

	var lbl_h := Label.new()
	lbl_h.text = fmt_str % val_h
	lbl_h.custom_minimum_size = Vector2(80.0, 0.0)
	lbl_h.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	lbl_h.add_theme_font_size_override("font_size", 16)
	lbl_h.add_theme_color_override("font_color", ACCENT_COLOR if val_h >= val_a else Color(0.8, 0.8, 0.8))
	header.add_child(lbl_h)

	var lbl_title := Label.new()
	lbl_title.text = title
	lbl_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_title.add_theme_font_size_override("font_size", 15)
	lbl_title.add_theme_color_override("font_color", Color.WHITE)
	header.add_child(lbl_title)

	var lbl_a := Label.new()
	lbl_a.text = fmt_str % val_a
	lbl_a.custom_minimum_size = Vector2(80.0, 0.0)
	lbl_a.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_a.add_theme_font_size_override("font_size", 16)
	lbl_a.add_theme_color_override("font_color", ACCENT_COLOR if val_a >= val_h else Color(0.8, 0.8, 0.8))
	header.add_child(lbl_a)

	vbox.add_child(header)

	# Subtitle description
	var lbl_desc := Label.new()
	lbl_desc.text = desc
	lbl_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_desc.add_theme_font_size_override("font_size", 11)
	lbl_desc.add_theme_color_override("font_color", Color(0.65, 0.70, 0.65))
	vbox.add_child(lbl_desc)

	return card


func _populate_ratings_matrix() -> void:
	_fill_ratings_column(_home_matrix_vbox, 0, _team_a_name)
	_fill_ratings_column(_away_matrix_vbox, 1, _team_b_name)


func _fill_ratings_column(vbox: VBoxContainer, team_idx: int, team_name: String) -> void:
	for child: Node in vbox.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "%s  (Squad Performance)" % team_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", ACCENT_COLOR if team_idx == 0 else Color(0.9, 0.9, 0.9))
	vbox.add_child(title)

	# Headers
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)

	header.add_child(_make_col_header("#", 20, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_make_col_header("Name", 80, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_make_col_header("Pos", 28, HORIZONTAL_ALIGNMENT_LEFT))
	header.add_child(_make_col_header("Rtg", 32, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_col_header("xG", 34, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_col_header("xA", 34, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_col_header("ΔxT", 34, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_col_header("Pack", 32, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_col_header("Tck", 30, HORIZONTAL_ALIGNMENT_RIGHT))
	header.add_child(_make_col_header("VAEP", 36, HORIZONTAL_ALIGNMENT_RIGHT))

	vbox.add_child(header)

	var rows: Array[Array] = []
	for key: int in _cached_ratings:
		if key / 1000 != team_idx:
			continue
		var squad_index: int = key % 1000
		var p: PlayerData = DataLoader.get_player(team_idx, squad_index)
		if p == null:
			continue
		var events: PlayerRatingCalculator.PlayerMatchEvents = MatchStatsTracker.get_player_events(key)
		rows.append([p, _cached_ratings[key], events])

	rows.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[1]) > float(b[1])
	)

	for r in rows:
		var row_container: HBoxContainer = _build_player_row(r[0] as PlayerData, float(r[1]), r[2] as PlayerRatingCalculator.PlayerMatchEvents)
		vbox.add_child(row_container)


func _make_col_header(text: String, min_w: int, align: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(float(min_w), 0.0)
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.65, 0.7, 0.65))
	return lbl


func _build_player_row(p: PlayerData, rating: float, ev: PlayerRatingCalculator.PlayerMatchEvents) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var num_lbl := Label.new()
	num_lbl.text = str(p.shirt_number)
	num_lbl.custom_minimum_size = Vector2(20.0, 0.0)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	num_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(num_lbl)

	var g_str: String = " ⚽%d" % ev.goals if ev.goals > 0 else ""
	var a_str: String = " 🎯%d" % ev.assists if ev.assists > 0 else ""
	var card_str: String = " 🟨" if ev.yellow_cards > 0 else (" 🟥" if ev.red_cards > 0 else "")
	var name_btn: Button = CareerTheme.player_link(p, 80)
	name_btn.text = "%s%s%s%s" % [_surname(p.player_name), g_str, a_str, card_str]
	name_btn.add_theme_font_size_override("font_size", 13)
	row.add_child(name_btn)

	var pos_lbl := Label.new()
	pos_lbl.text = p.position_role
	pos_lbl.custom_minimum_size = Vector2(28.0, 0.0)
	pos_lbl.add_theme_font_size_override("font_size", 12)
	pos_lbl.add_theme_color_override("font_color", Color(0.7, 0.8, 0.7))
	row.add_child(pos_lbl)

	var rtg_lbl := Label.new()
	rtg_lbl.text = "%.1f" % rating
	rtg_lbl.custom_minimum_size = Vector2(32.0, 0.0)
	rtg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rtg_lbl.add_theme_font_size_override("font_size", 13)
	if rating >= 8.0:
		rtg_lbl.add_theme_color_override("font_color", GOLD_COLOR)
	elif rating >= 7.0:
		rtg_lbl.add_theme_color_override("font_color", GOOD_RATING_COLOR)
	elif rating < 6.0:
		rtg_lbl.add_theme_color_override("font_color", LOW_RATING_COLOR)
	row.add_child(rtg_lbl)

	var xg_lbl := _make_data_cell("%.2f" % ev.xg, 34)
	var xa_lbl := _make_data_cell("%.2f" % ev.xa, 34)
	var xt_lbl := _make_data_cell("%.2f" % ev.xt_delta, 34)
	var pack_lbl := _make_data_cell(str(ev.packing_count), 32)
	var tck_lbl := _make_data_cell(str(ev.tackles_won + ev.interceptions), 30)
	var vaep_lbl := _make_data_cell("%.2f" % ev.vaep, 36)

	for c: Label in [xg_lbl, xa_lbl, xt_lbl, pack_lbl, tck_lbl, vaep_lbl]:
		row.add_child(c)

	return row


func _make_data_cell(text: String, min_w: int) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(float(min_w), 0.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 12)
	return lbl


func _surname(full_name: String) -> String:
	var parts: PackedStringArray = full_name.split(" ", false)
	if parts.is_empty():
		return full_name
	return parts[parts.size() - 1]


func _on_ratings_back_to_menu_pressed() -> void:
	stats_dismissed.emit()
	if is_overlay_mode:
		queue_free()
		return
	if custom_return_scene != "":
		get_tree().change_scene_to_file(custom_return_scene)
	else:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)
