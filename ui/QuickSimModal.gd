##
## QuickSimModal
##
## Interactive Quick Match Simulation dialog.
## First phase: Calculates and displays complete pre-match outcome probabilities,
## expected goals (xG), clean sheet projections, top scorelines, unit strengths,
## and tactical/personnel insights.
## Second phase: Reveals the simulated match outcome, event timeline (goals,
## assists, cards), and offers immediate navigation to the 4-page full MatchStatsUI.
##
## Depends on: QuickSimEngine, TeamData, ManagerData, RefereeData, GameManager,
##             MatchStatsTracker, MatchStatsUI.
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

@onready var _pre_sim_box: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox
@onready var _post_sim_box: VBoxContainer = $Root/Panel/VBoxContainer/PostSimBox

@onready var _match_title_label: Label = $Root/Panel/VBoxContainer/Header/MatchTitleLabel

# Pre-sim widgets
@onready var _home_win_prob_label: Label = $Root/Panel/VBoxContainer/PreSimBox/ProbRow/HomeWinLabel
@onready var _draw_prob_label: Label = $Root/Panel/VBoxContainer/PreSimBox/ProbRow/DrawLabel
@onready var _away_win_prob_label: Label = $Root/Panel/VBoxContainer/PreSimBox/ProbRow/AwayWinLabel
@onready var _xg_label: Label = $Root/Panel/VBoxContainer/PreSimBox/MetricsGrid/XGValueLabel
@onready var _cs_label: Label = $Root/Panel/VBoxContainer/PreSimBox/MetricsGrid/CSValueLabel
@onready var _over_btts_label: Label = $Root/Panel/VBoxContainer/PreSimBox/MetricsGrid/OverBTTSValueLabel
@onready var _scorelines_vbox: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox/Columns/ScorelinesColumn/ScorelinesList
@onready var _units_vbox: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox/Columns/UnitsColumn/UnitsList
@onready var _insights_vbox: VBoxContainer = $Root/Panel/VBoxContainer/PreSimBox/InsightsBox/InsightsList

@onready var _btn_simulate: Button = $Root/Panel/VBoxContainer/PreSimBox/ButtonRow/SimulateButton
@onready var _btn_cancel: Button = $Root/Panel/VBoxContainer/PreSimBox/ButtonRow/CancelButton

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

	_probabilities = QuickSimEngine.calculate_probabilities(
		_home_team, _away_team, _home_manager, _away_manager, _referee,
		_home_lineup, _away_lineup, _is_neutral
	)

	_populate_pre_sim_ui()


func open() -> void:
	visible = true
	_pre_sim_box.visible = true
	_post_sim_box.visible = false
	_btn_simulate.grab_focus()


func _populate_pre_sim_ui() -> void:
	if _probabilities == null or _home_team == null or _away_team == null:
		return

	_match_title_label.text = "%s  vs  %s" % [_home_team.team_name, _away_team.team_name]

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
		var k: String = u[0]
		var name_str: String = u[1]
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


func _on_simulate_pressed() -> void:
	_sim_result = QuickSimEngine.simulate_match(
		_home_team, _away_team, _home_manager, _away_manager, _referee,
		_home_lineup, _away_lineup, _is_neutral
	)

	# Apply results to MatchStatsTracker and update career persistence
	QuickSimEngine.apply_to_match_stats_tracker(
		_sim_result, _home_team, _away_team, _referee, _home_manager, _away_manager
	)

	_populate_post_sim_ui()
	_pre_sim_box.visible = false
	_post_sim_box.visible = true
	_btn_view_stats.grab_focus()

	match_completed.emit(_sim_result)


func _populate_post_sim_ui() -> void:
	if _sim_result == null or _home_team == null or _away_team == null:
		return

	_final_score_label.text = "%s   %d - %d   %s" % [
		_home_team.team_name, _sim_result.home_score, _sim_result.away_score, _away_team.team_name
	]

	if _sim_result.home_score > _sim_result.away_score:
		_result_headline_label.text = "%s victory at full time!" % _home_team.team_name
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
			var item := Label.new()
			var icon: String = "⚽" if ev.event_type == "goal" else ("🟨" if ev.event_type == "yellow_card" else "🟥")
			item.text = "%s %d'  %s" % [icon, ev.minute, ev.description]
			_events_list.add_child(item)


func _on_view_stats_pressed() -> void:
	var stats_ui: MatchStatsUI = MatchStatsScene.instantiate() as MatchStatsUI
	stats_ui.is_overlay_mode = true
	add_child(stats_ui)
	stats_ui.populate(_home_team.team_name, _away_team.team_name)
	stats_ui.stats_dismissed.connect(func():
		# Return focus to View Stats button
		if is_instance_valid(_btn_view_stats):
			_btn_view_stats.grab_focus()
	)


func _on_done_pressed() -> void:
	visible = false
	modal_closed.emit()


func _on_cancel_pressed() -> void:
	visible = false
	modal_closed.emit()
