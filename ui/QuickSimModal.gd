##
## QuickSimModal
##
## Interactive Quick Match Simulation dialog and Matchday Broadcast.
## Phase 1: Pre-match press conference, tactical matchup insights, unit strength,
##          and game plan mentality selection.
## Phase 2: Championship Manager 01/02 style play-by-play text commentary ticker
##          with live clock, speed control (1x/2x/5x), pause, half-time tactical break,
##          and instant skip.
## Phase 3: Post-match full-time scoreline, outcome headline, scorers timeline,
##          and full MatchStatsUI navigation.
##
## Depends on: QuickSimEngine, TeamData, ManagerData, RefereeData, GameManager,
##             MatchStatsTracker, MatchStatsUI, CareerManager, PressOffice.
## Exposes: setup_match(home_team, away_team, home_mgr, away_mgr, ref, h_lineup, a_lineup, neutral),
##          open(), match_completed signal, modal_closed signal.
##

class_name QuickSimModal
extends CanvasLayer

signal match_completed(result: QuickSimEngine.QuickSimResult)
signal modal_closed

const MatchStatsScene: PackedScene = preload("res://ui/MatchStatsUI.tscn")
const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)

var _home_team: TeamData = null
var _away_team: TeamData = null
var _home_manager: ManagerData = null
var _away_manager: ManagerData = null
var _referee: RefereeData = null
var _home_lineup: Array[int] = []
var _away_lineup: Array[int] = []
var _is_neutral: bool = false

var _probabilities: QuickSimEngine.MatchProbabilities = null
var _sim_result: QuickSimEngine.QuickSimResult = null

# Playback state
var _in_match: bool = false
var _is_paused: bool = false
var _speed_mult: float = 1.0
var _tick_timer: float = 0.0
var _current_minute: int = 0
var _live_home_score: int = 0
var _live_away_score: int = 0
var _event_index: int = 0
var _mentality_choice: int = 1 # 0 = Cautious, 1 = Balanced, 2 = Attacking

@onready var _pre_sim_box: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox
@onready var _match_box: VBoxContainer = $Root/Panel/VBoxContainer/MatchBox
@onready var _post_sim_box: VBoxContainer = $Root/Panel/VBoxContainer/PostSimBox

@onready var _match_title_label: Label = $Root/Panel/VBoxContainer/Header/MatchTitleLabel

# Pre-sim widgets
@onready var _press_question_label: Label = $Root/Panel/VBoxContainer/PreSimBox/PressBox/PressQuestionLabel
@onready var _press_btn_1: Button = $Root/Panel/VBoxContainer/PreSimBox/PressBox/PressButtonsRow/PressBtn1
@onready var _press_btn_2: Button = $Root/Panel/VBoxContainer/PreSimBox/PressBox/PressButtonsRow/PressBtn2
@onready var _press_btn_3: Button = $Root/Panel/VBoxContainer/PreSimBox/PressBox/PressButtonsRow/PressBtn3
@onready var _press_quote_label: Label = $Root/Panel/VBoxContainer/PreSimBox/PressBox/PressQuoteLabel

@onready var _home_win_prob_label: Label = $Root/Panel/VBoxContainer/PreSimBox/ProbRow/HomeWinLabel
@onready var _draw_prob_label: Label = $Root/Panel/VBoxContainer/PreSimBox/ProbRow/DrawLabel
@onready var _away_win_prob_label: Label = $Root/Panel/VBoxContainer/PreSimBox/ProbRow/AwayWinLabel
@onready var _xg_label: Label = $Root/Panel/VBoxContainer/PreSimBox/MetricsGrid/XGValueLabel
@onready var _cs_label: Label = $Root/Panel/VBoxContainer/PreSimBox/MetricsGrid/CSValueLabel
@onready var _over_btts_label: Label = $Root/Panel/VBoxContainer/PreSimBox/MetricsGrid/OverBTTSValueLabel
@onready var _scorelines_vbox: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox/Columns/ScorelinesColumn/ScorelinesList
@onready var _units_vbox: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox/Columns/UnitsColumn/UnitsList
@onready var _insights_vbox: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox/InsightsBox/InsightsList

@onready var _mentality_defensive: Button = $Root/Panel/VBoxContainer/PreSimBox/MentalityRow/MentalityDefensive
@onready var _mentality_balanced: Button = $Root/Panel/VBoxContainer/PreSimBox/MentalityRow/MentalityBalanced
@onready var _mentality_attacking: Button = $Root/Panel/VBoxContainer/PreSimBox/MentalityRow/MentalityAttacking

@onready var _btn_simulate: Button = $Root/Panel/VBoxContainer/PreSimBox/ButtonRow/SimulateButton
@onready var _btn_cancel: Button = $Root/Panel/VBoxContainer/PreSimBox/ButtonRow/CancelButton

# Match broadcast widgets
@onready var _live_score_label: Label = $Root/Panel/VBoxContainer/MatchBox/ScoreBanner/LiveScoreLabel
@onready var _clock_label: Label = $Root/Panel/VBoxContainer/MatchBox/ScoreBanner/ClockRow/ClockLabel
@onready var _progress_bar: ProgressBar = $Root/Panel/VBoxContainer/MatchBox/ScoreBanner/ClockRow/MatchProgressBar
@onready var _latest_action_label: Label = $Root/Panel/VBoxContainer/MatchBox/LatestActionLabel
@onready var _commentary_scroll: ScrollContainer = $Root/Panel/VBoxContainer/MatchBox/CommentaryScroll
@onready var _commentary_list: VBoxContainer = $Root/Panel/VBoxContainer/MatchBox/CommentaryScroll/CommentaryList
@onready var _half_time_box: HBoxContainer = $Root/Panel/VBoxContainer/MatchBox/HalfTimeBox
@onready var _btn_resume_2nd_half: Button = $Root/Panel/VBoxContainer/MatchBox/HalfTimeBox/Resume2ndHalfButton

@onready var _btn_pause: Button = $Root/Panel/VBoxContainer/MatchBox/MatchControls/PauseButton
@onready var _btn_speed_1: Button = $Root/Panel/VBoxContainer/MatchBox/MatchControls/Speed1Button
@onready var _btn_speed_2: Button = $Root/Panel/VBoxContainer/MatchBox/MatchControls/Speed2Button
@onready var _btn_speed_5: Button = $Root/Panel/VBoxContainer/MatchBox/MatchControls/Speed5Button
@onready var _btn_skip: Button = $Root/Panel/VBoxContainer/MatchBox/MatchControls/SkipButton

# Post-sim widgets
@onready var _final_score_label: Label = $Root/Panel/VBoxContainer/PostSimBox/ScoreBanner/FinalScoreLabel
@onready var _result_headline_label: Label = $Root/Panel/VBoxContainer/PostSimBox/ScoreBanner/HeadlineLabel
@onready var _events_list: VBoxContainer = $Root/Panel/VBoxContainer/PostSimBox/EventsScroll/EventsList
@onready var _btn_view_stats: Button = $Root/Panel/VBoxContainer/PostSimBox/ButtonRow/ViewStatsButton
@onready var _btn_done: Button = $Root/Panel/VBoxContainer/PostSimBox/ButtonRow/DoneButton


func _ready() -> void:
	visible = false
	_btn_simulate.pressed.connect(_on_simulate_pressed)
	_btn_cancel.pressed.connect(_on_cancel_pressed)
	_btn_view_stats.pressed.connect(_on_view_stats_pressed)
	_btn_done.pressed.connect(_on_done_pressed)

	_press_btn_1.pressed.connect(func() -> void: _on_press_choice(0))
	_press_btn_2.pressed.connect(func() -> void: _on_press_choice(1))
	_press_btn_3.pressed.connect(func() -> void: _on_press_choice(2))

	_mentality_defensive.pressed.connect(func() -> void: _set_mentality(0))
	_mentality_balanced.pressed.connect(func() -> void: _set_mentality(1))
	_mentality_attacking.pressed.connect(func() -> void: _set_mentality(2))

	_btn_pause.pressed.connect(_on_pause_toggle)
	_btn_speed_1.pressed.connect(func() -> void: _set_speed(1.0))
	_btn_speed_2.pressed.connect(func() -> void: _set_speed(2.0))
	_btn_speed_5.pressed.connect(func() -> void: _set_speed(5.0))
	_btn_skip.pressed.connect(_on_skip_pressed)
	_btn_resume_2nd_half.pressed.connect(_on_resume_2nd_half)


func _process(delta: float) -> void:
	if not _in_match or _is_paused:
		return
	_tick_timer += delta * _speed_mult
	if _tick_timer >= 0.12:
		_tick_timer = 0.0
		_step_minute()


## Initializes the modal with match participants and immediately calculates probabilities.
func setup_match(
	home_team: TeamData,
	away_team: TeamData,
	home_mgr: ManagerData,
	away_mgr: ManagerData,
	ref: RefereeData,
	home_lineup: Array[int] = [],
	away_lineup: Array[int] = [],
	neutral: bool = false
) -> void:
	_home_team = home_team
	_away_team = away_team
	_home_manager = home_mgr
	_away_manager = away_mgr
	_referee = ref
	_home_lineup = home_lineup
	_away_lineup = away_lineup
	_is_neutral = neutral

	_in_match = false
	_is_paused = false
	_current_minute = 0
	_live_home_score = 0
	_live_away_score = 0
	_event_index = 0
	_sim_result = null

	_probabilities = QuickSimEngine.calculate_probabilities(
		_home_team, _away_team, _home_manager, _away_manager, _referee,
		_home_lineup, _away_lineup, _is_neutral
	)

	_populate_pre_sim_ui()


func open() -> void:
	visible = true
	_pre_sim_box.visible = true
	_match_box.visible = false
	_post_sim_box.visible = false
	_set_mentality(1)
	_btn_simulate.grab_focus()


func _populate_pre_sim_ui() -> void:
	if _probabilities == null or _home_team == null or _away_team == null:
		return

	_match_title_label.text = "%s  vs  %s" % [_home_team.team_name, _away_team.team_name]

	var header_box: VBoxContainer = _match_title_label.get_parent() as VBoxContainer
	if header_box != null:
		var old_links: Node = header_box.get_node_or_null("EntityLinksRow")
		if old_links != null:
			old_links.queue_free()
		var links_row := HBoxContainer.new()
		links_row.name = "EntityLinksRow"
		links_row.alignment = BoxContainer.ALIGNMENT_CENTER
		links_row.add_theme_constant_override("separation", 16)
		links_row.add_child(CareerTheme.team_link(_home_team))
		links_row.add_child(CareerTheme.label("vs", Color(0.7, 0.7, 0.7)))
		links_row.add_child(CareerTheme.team_link(_away_team))
		if _referee != null:
			links_row.add_child(CareerTheme.label("·  Official:", Color(0.6, 0.6, 0.6)))
			links_row.add_child(CareerTheme.referee_link(_referee))
		header_box.add_child(links_row)

	# Press conference prompt
	var opp_name: String = _away_team.team_name
	if CareerManager.career != null and _away_team.team_name == CareerManager.user_team().team_name:
		opp_name = _home_team.team_name
	_press_question_label.text = "Press Room: 'Coach, how are you approaching today's crucial fixture against %s?'" % opp_name
	_press_quote_label.text = "Select an approach to address the journalists."

	# Probabilities row
	_home_win_prob_label.text = "%s Win\n%.1f%%" % [_home_team.team_name, _probabilities.home_win_pct]
	_draw_prob_label.text = "Draw\n%.1f%%" % _probabilities.draw_pct
	_away_win_prob_label.text = "%s Win\n%.1f%%" % [_away_team.team_name, _probabilities.away_win_pct]

	# Metrics
	_xg_label.text = "xG: %.2f - %.2f" % [_probabilities.home_xg, _probabilities.away_xg]
	_cs_label.text = "Clean Sheet: %.1f%% - %.1f%%" % [_probabilities.home_clean_sheet_pct, _probabilities.away_clean_sheet_pct]
	_over_btts_label.text = "Over 2.5: %.1f%%  |  BTTS: %.1f%%" % [_probabilities.over_2_5_pct, _probabilities.btts_pct]

	# Scorelines
	for child: Node in _scorelines_vbox.get_children():
		child.queue_free()
	for sc: Dictionary in _probabilities.scoreline_probs:
		var sc_lbl := Label.new()
		sc_lbl.text = "  %s  (%.1f%%)" % [String(sc["score"]), float(sc["prob_pct"])]
		_scorelines_vbox.add_child(sc_lbl)

	# Unit ratings
	for child: Node in _units_vbox.get_children():
		child.queue_free()

	var h_units: Dictionary = _probabilities.home_unit_ratings
	var a_units: Dictionary = _probabilities.away_unit_ratings
	var unit_keys: Array[Array] = [
		["overall", "Overall"],
		["att", "Attack"],
		["mid", "Midfield"],
		["def", "Defence"],
		["gk", "Goalkeeper"],
	]
	for u: Array in unit_keys:
		var k: String = String(u[0])
		var name_str: String = String(u[1])
		var unit_lbl := Label.new()
		unit_lbl.text = "%s:  %.0f  vs  %.0f" % [name_str, float(h_units.get(k, 0.0)), float(a_units.get(k, 0.0))]
		_units_vbox.add_child(unit_lbl)

	# Insights
	for child: Node in _insights_vbox.get_children():
		child.queue_free()
	for ins: String in _probabilities.tactical_insights:
		var ins_lbl := Label.new()
		ins_lbl.text = "• %s" % ins
		ins_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_insights_vbox.add_child(ins_lbl)


func _on_press_choice(choice: int) -> void:
	match choice:
		0:
			_press_quote_label.text = "Manager: \"We're going out to win. We believe in our qualities and will take the game to them.\""
			_press_quote_label.add_theme_color_override(&"font_color", Color(0.24, 0.86, 0.41))
		1:
			_press_quote_label.text = "Manager: \"Discipline and structure will decide this match. We must stay compact and focused.\""
			_press_quote_label.add_theme_color_override(&"font_color", Color(0.4, 0.8, 0.9))
		2:
			_press_quote_label.text = "Manager: \"We'll do our talking on the pitch. No excuses, no distractions.\""
			_press_quote_label.add_theme_color_override(&"font_color", Color(0.9, 0.8, 0.3))


func _set_mentality(m: int) -> void:
	_mentality_choice = m
	_mentality_defensive.modulate = ACCENT_COLOR if m == 0 else Color.WHITE
	_mentality_balanced.modulate = ACCENT_COLOR if m == 1 else Color.WHITE
	_mentality_attacking.modulate = ACCENT_COLOR if m == 2 else Color.WHITE


func _on_simulate_pressed() -> void:
	# 1. Apply user mentality tweak to manager settings
	if _home_manager != null and CareerManager.career != null and _home_team.team_name == CareerManager.user_team().team_name:
		if _mentality_choice == 0:
			_home_manager.tempo = clampf(_home_manager.tempo - 0.1, 0.1, 0.9)
			_home_manager.defensive_line = clampf(_home_manager.defensive_line - 0.15, 0.1, 0.9)
		elif _mentality_choice == 2:
			_home_manager.tempo = clampf(_home_manager.tempo + 0.15, 0.1, 0.9)
			_home_manager.defensive_line = clampf(_home_manager.defensive_line + 0.1, 0.1, 0.9)

	# 2. Simulate match outcome
	_sim_result = QuickSimEngine.simulate_match(
		_home_team, _away_team, _home_manager, _away_manager, _referee,
		_home_lineup, _away_lineup, _is_neutral
	)

	# 3. Publish results to MatchStatsTracker
	QuickSimEngine.apply_to_match_stats_tracker(
		_sim_result, _home_team, _away_team, _referee, _home_manager, _away_manager
	)

	# 4. Start Live Play-by-Play Commentary View
	_pre_sim_box.visible = false
	_match_box.visible = true
	_post_sim_box.visible = false
	_half_time_box.visible = false

	_live_home_score = 0
	_live_away_score = 0
	_current_minute = 0
	_event_index = 0
	_is_paused = false
	_in_match = true
	_tick_timer = 0.0
	_speed_mult = 1.0

	_live_score_label.text = "%s   0 - 0   %s" % [_home_team.team_name, _away_team.team_name]
	_clock_label.text = "1'"
	_progress_bar.value = 1.0
	_btn_pause.text = "Pause"

	for child: Node in _commentary_list.get_children():
		child.queue_free()

	_step_minute()


func _step_minute() -> void:
	_current_minute += 1
	_clock_label.text = "%d'" % _current_minute
	_progress_bar.value = float(_current_minute)

	# Stream commentary events scheduled for this minute
	while _sim_result != null and _event_index < _sim_result.events.size():
		var ev: QuickSimEngine.MatchEventRecord = _sim_result.events[_event_index]
		if ev.minute <= _current_minute:
			_append_commentary_event(ev)
			_event_index += 1
		else:
			break

	if _current_minute == 45:
		_is_paused = true
		_half_time_box.visible = true
		_btn_pause.text = "Resume"
		_latest_action_label.text = "⏸️ Half-Time: %s %d - %d %s" % [
			_home_team.team_name, _live_home_score, _live_away_score, _away_team.team_name
		]
	elif _current_minute >= 90:
		_finish_match()


func _append_commentary_event(ev: QuickSimEngine.MatchEventRecord) -> void:
	var item := Label.new()
	var icon: String = "⚡"
	var color: Color = Color(0.85, 0.85, 0.85)

	match ev.event_type:
		"goal":
			icon = "⚽ GOAL!"
			color = Color(0.24, 0.86, 0.41)
			if ev.team == GameManager.TEAM_A:
				_live_home_score += 1
			else:
				_live_away_score += 1
			_live_score_label.text = "%s   %d - %d   %s" % [
				_home_team.team_name, _live_home_score, _live_away_score, _away_team.team_name
			]
			_latest_action_label.text = "⚽ %s (%d - %d)" % [ev.description, _live_home_score, _live_away_score]
		"yellow_card":
			icon = "🟨 CARD"
			color = Color(0.9, 0.8, 0.2)
			_latest_action_label.text = "🟨 %s" % ev.description
		"red_card":
			icon = "🟥 RED CARD"
			color = Color(0.95, 0.3, 0.3)
			_latest_action_label.text = "🟥 %s" % ev.description
		"save":
			icon = "🧤 SAVE"
			color = Color(0.4, 0.8, 0.9)
			_latest_action_label.text = "🧤 %s" % ev.description
		"woodwork":
			icon = "💥 WOODWORK"
			color = Color(0.95, 0.6, 0.2)
			_latest_action_label.text = "💥 %s" % ev.description
		"miss":
			icon = "💨 CHANCE"
			color = Color(0.7, 0.7, 0.7)
			_latest_action_label.text = "💨 %s" % ev.description
		"halftime":
			icon = "⏸️ HALF TIME"
			color = Color(0.9, 0.8, 0.3)
		"secondhalf":
			icon = "▶️ 2ND HALF"
			color = Color(0.6, 0.9, 0.6)
		"fulltime":
			icon = "🏁 FULL TIME"
			color = Color(0.24, 0.86, 0.41)
		"kickoff":
			icon = "📢 KICK-OFF"
			color = Color(0.6, 0.8, 1.0)

	item.text = "[%2d']  %s  %s" % [ev.minute, icon, ev.description]
	item.add_theme_color_override(&"font_color", color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_commentary_list.add_child(item)

	call_deferred(&"_scroll_to_bottom")


func _scroll_to_bottom() -> void:
	if _commentary_scroll != null and is_instance_valid(_commentary_scroll):
		var v_bar: VScrollBar = _commentary_scroll.get_v_scroll_bar()
		if v_bar != null:
			v_bar.value = v_bar.max_value


func _on_pause_toggle() -> void:
	_is_paused = not _is_paused
	_btn_pause.text = "Resume" if _is_paused else "Pause"


func _set_speed(s: float) -> void:
	_speed_mult = s
	_btn_speed_1.modulate = ACCENT_COLOR if is_equal_approx(s, 1.0) else Color.WHITE
	_btn_speed_2.modulate = ACCENT_COLOR if is_equal_approx(s, 2.0) else Color.WHITE
	_btn_speed_5.modulate = ACCENT_COLOR if is_equal_approx(s, 5.0) else Color.WHITE


func _on_resume_2nd_half() -> void:
	_half_time_box.visible = false
	_is_paused = false
	_btn_pause.text = "Pause"


func _on_skip_pressed() -> void:
	if _sim_result == null:
		return
	while _event_index < _sim_result.events.size():
		var ev: QuickSimEngine.MatchEventRecord = _sim_result.events[_event_index]
		_append_commentary_event(ev)
		_event_index += 1
	_current_minute = 90
	_finish_match()


func _finish_match() -> void:
	_in_match = false
	_is_paused = true
	_match_box.visible = false
	_post_sim_box.visible = true
	_populate_post_sim_ui()
	_btn_view_stats.grab_focus()
	match_completed.emit(_sim_result)


func _populate_post_sim_ui() -> void:
	if _sim_result == null or _home_team == null or _away_team == null:
		return

	_final_score_label.text = "%s   %d - %d   %s" % [
		_home_team.team_name, _sim_result.home_score, _sim_result.away_score, _away_team.team_name
	]

	if _sim_result.home_score > _sim_result.away_score:
		_result_headline_label.text = "%s claim victory at full time!" % _home_team.team_name
	elif _sim_result.away_score > _sim_result.home_score:
		_result_headline_label.text = "%s claim away victory!" % _away_team.team_name
	else:
		_result_headline_label.text = "Full time stalemate — match drawn!"

	for child: Node in _events_list.get_children():
		child.queue_free()

	if _sim_result.events.is_empty():
		var no_ev := Label.new()
		no_ev.text = "No goals or cards recorded."
		_events_list.add_child(no_ev)
	else:
		for ev: QuickSimEngine.MatchEventRecord in _sim_result.events:
			if ev.event_type in ["goal", "yellow_card", "red_card"]:
				var item := HBoxContainer.new()
				item.add_theme_constant_override("separation", 6)
				var icon: String = "⚽" if ev.event_type == "goal" else ("🟨" if ev.event_type == "yellow_card" else "🟥")
				var min_lbl := Label.new()
				min_lbl.text = "%s %d'" % [icon, ev.minute]
				item.add_child(min_lbl)
				var desc_lbl := Label.new()
				if not ev.player_name.is_empty():
					item.add_child(CareerTheme.player_link(ev.player_name))
					desc_lbl.text = "· " + ev.description
				else:
					desc_lbl.text = ev.description
				item.add_child(desc_lbl)
				_events_list.add_child(item)


func _on_view_stats_pressed() -> void:
	var stats_ui: MatchStatsUI = MatchStatsScene.instantiate() as MatchStatsUI
	stats_ui.is_overlay_mode = true
	add_child(stats_ui)
	stats_ui.populate(_home_team.team_name, _away_team.team_name)
	stats_ui.stats_dismissed.connect(func():
		if is_instance_valid(_btn_view_stats):
			_btn_view_stats.grab_focus()
	)


func _on_done_pressed() -> void:
	visible = false
	modal_closed.emit()


func _on_cancel_pressed() -> void:
	visible = false
	modal_closed.emit()
