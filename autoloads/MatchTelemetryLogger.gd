##
## MatchTelemetryLogger (Autoload singleton)
##
## Centralized match telemetry, diagnostics, and structured event logging.
## Tracks real-time simulation events, periodic match pulse snapshots (every 15
## simulated minutes), comprehensive full-time analytical Moneyball summaries,
## 22-player ratings/performance tables, and simulation invariant health checks.
##
## Outputs to both Godot stdout and persistent disk log files (e.g. user://match_telemetry.log
## and user://match_telemetry.json).
##
## Depends on: GameEvents, GameManager, MatchStatsTracker, MatchWorldModel, DataLoader.
## Exposes: log_event(), dump_periodic_snapshot(), dump_fulltime_report(),
##          set_verbosity(), get_verbosity(), flush(), Verbosity enum.
##
## NOTE: class_name is intentionally omitted because this script is registered
## as an autoload singleton. Access via MatchTelemetryLogger global.
##

extends Node

enum Verbosity {
	OFF = 0,
	ESSENTIAL = 1,  ## Lifecycle, goals, cards, 15-min periodic snapshots, full-time analytics dump
	TACTICAL = 2,   ## Essential + tactical shifts, press triggers, momentum swings, substitutions, mood shifts
	VERBOSE = 3,    ## Tactical + all shots, set pieces, referee threshold drift, pass/carry details
}

static var instance: MatchTelemetryLogger = null

## Logging configuration
var verbosity: Verbosity = Verbosity.TACTICAL
var log_to_stdout: bool = true
var log_to_file: bool = true
var log_file_path: String = "user://match_telemetry.log"
var json_summary_path: String = "user://match_telemetry.json"

## File handle & log buffer
var _log_file: FileAccess = null
var _buffered_lines: Array[String] = []

## Periodic snapshot tracking (15', 30', 45', 60', 75', 90')
const SNAPSHOT_INTERVAL_SEC: float = 15.0 * 60.0  # 900 simulated seconds (15 in-game minutes)
var _last_snapshot_minute: int = 0
var _match_started: bool = false
var _fulltime_logged: bool = false

## Health diagnostics counters
var _health_nan_inf_count: int = 0
var _health_boundary_escapes: int = 0
var _health_stalls_detected: int = 0

## Chronological events memory for JSON summary export
var _recorded_events: Array[Dictionary] = []


func _enter_tree() -> void:
	instance = self


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_parse_cli_and_meta()
	_open_log_file()
	_connect_signals()


func _exit_tree() -> void:
	_flush_buffer()
	if _log_file != null:
		_log_file.close()
		_log_file = null
	if instance == self:
		instance = null


func _physics_process(_delta: float) -> void:
	if not _match_started or _fulltime_logged:
		return

	if not GameManager.is_in_play():
		return

	# Periodic 15-minute simulation pulse snapshots
	var sim_min: int = int(GameManager.simulated_match_time / 60.0)
	if sim_min > 0 and sim_min % 15 == 0 and sim_min != _last_snapshot_minute:
		_last_snapshot_minute = sim_min
		dump_periodic_snapshot(sim_min)


## --- CLI and Meta Configuration ---------------------------------------------

func _parse_cli_and_meta() -> void:
	var cmd_args: PackedStringArray = OS.get_cmdline_args()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var all_args: Array[String] = []
	for a: String in cmd_args:
		all_args.append(a)
	for a: String in user_args:
		all_args.append(a)

	for arg: String in all_args:
		if arg.begins_with("--output-log=") or arg.begins_with("--telemetry-log="):
			log_file_path = arg.split("=")[1]
			log_to_file = true
		elif arg.begins_with("--output-json=") or arg.begins_with("--telemetry-json="):
			json_summary_path = arg.split("=")[1]
		elif arg.begins_with("--telemetry-level="):
			var lvl: int = arg.split("=")[1].to_int()
			verbosity = clampi(lvl, Verbosity.OFF, Verbosity.VERBOSE) as Verbosity
		elif arg == "--verbose-telemetry":
			verbosity = Verbosity.VERBOSE
		elif arg == "--no-telemetry-file":
			log_to_file = false

	if GameManager.has_meta(&"telemetry_log_path"):
		log_file_path = String(GameManager.get_meta(&"telemetry_log_path"))
	if GameManager.has_meta(&"telemetry_level"):
		verbosity = clampi(int(GameManager.get_meta(&"telemetry_level")), 0, 3) as Verbosity


func _open_log_file() -> void:
	if not log_to_file or log_file_path.is_empty():
		return

	_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _log_file == null:
		push_warning("MatchTelemetryLogger: Could not open log file for writing at '%s'" % log_file_path)
		return

	var header: String = "================================================================================\n"
	header += "           POWERFOOTBALL-2D SIMULATION TELEMETRY & MATCH LOG                     \n"
	header += " Log Path: %s\n" % log_file_path
	header += " Timestamp: %s\n" % Time.get_datetime_string_from_system()
	header += " Verbosity: %s (%d)\n" % [_verbosity_name(verbosity), int(verbosity)]
	header += "================================================================================\n\n"
	_log_file.store_string(header)
	_log_file.flush()


func _verbosity_name(v: Verbosity) -> String:
	match v:
		Verbosity.OFF: return "OFF"
		Verbosity.ESSENTIAL: return "ESSENTIAL"
		Verbosity.TACTICAL: return "TACTICAL"
		Verbosity.VERBOSE: return "VERBOSE"
		_: return "UNKNOWN"


## --- Signal Connections ------------------------------------------------------

func _connect_signals() -> void:
	# Lifecycle events
	GameEvents.kickoff_started.connect(_on_kickoff_started)
	GameEvents.kickoff_confirmed.connect(_on_kickoff_confirmed)
	GameEvents.half_time_started.connect(_on_half_time_started)
	GameEvents.half_time_ended.connect(_on_half_time_ended)
	GameEvents.match_ended.connect(_on_match_ended)
	GameEvents.stoppage_time_announced.connect(_on_stoppage_time_announced)
	GameEvents.match_phase_changed.connect(_on_match_phase_changed)
	GameEvents.match_stage_changed.connect(_on_match_stage_changed)
	GameEvents.simulation_speed_changed.connect(_on_simulation_speed_changed)

	# Match play events
	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.shot_taken.connect(_on_shot_taken)
	GameEvents.powerful_shot_landed.connect(_on_powerful_shot_landed)
	GameEvents.pass_completed.connect(_on_pass_completed)
	GameEvents.carry_completed.connect(_on_carry_completed)
	GameEvents.defensive_action_logged.connect(_on_defensive_action_logged)
	GameEvents.tackle_won.connect(_on_tackle_won)
	GameEvents.anticipatory_turnover_predicted.connect(_on_turnover_predicted)

	# Referee & Discipline
	GameEvents.foul_committed.connect(_on_foul_committed)
	GameEvents.referee_awarded_foul.connect(_on_referee_awarded_foul)
	GameEvents.referee_played_on.connect(_on_referee_played_on)
	GameEvents.yellow_card_shown.connect(_on_yellow_card_shown)
	GameEvents.red_card_shown.connect(_on_red_card_shown)
	GameEvents.offside_called.connect(_on_offside_called)

	# Set pieces
	GameEvents.goal_kick_started.connect(_on_goal_kick_started)
	GameEvents.corner_kick_started.connect(_on_corner_kick_started)
	GameEvents.throw_in_started.connect(_on_throw_in_started)
	GameEvents.free_kick_started.connect(_on_free_kick_started)
	GameEvents.penalty_started.connect(_on_penalty_started)
	GameEvents.shootout_kick_result.connect(_on_shootout_kick_result)

	# Macro Tactics & Psychology
	GameEvents.manager_formation_changed.connect(_on_manager_formation_changed)
	GameEvents.team_urgency_updated.connect(_on_team_urgency_updated)
	GameEvents.team_momentum_updated.connect(_on_team_momentum_updated)
	GameEvents.emergency_tactics_triggered.connect(_on_emergency_tactics_triggered)
	GameEvents.press_trigger_changed.connect(_on_press_trigger_changed)
	GameEvents.substitution_made.connect(_on_substitution_made)
	GameEvents.player_mood_changed.connect(_on_player_mood_changed)
	GameEvents.stamina_depleted.connect(_on_stamina_depleted)


## --- Primary Logging Methods -------------------------------------------------

func log_event(category: String, message: String, required_verbosity: Verbosity = Verbosity.ESSENTIAL) -> void:
	if verbosity < required_verbosity or verbosity == Verbosity.OFF:
		return

	var clock_str: String = GameManager.get_clock_string() if GameManager != null else "00:00"
	var half_idx: int = GameManager.current_half if GameManager != null else 1
	var formatted_line: String = "[%s | H%d] [%s] %s" % [clock_str, half_idx, category, message]

	if log_to_stdout:
		print(formatted_line)

	if log_to_file:
		_buffered_lines.append(formatted_line)
		if _buffered_lines.size() >= 10:
			_flush_buffer()

	_recorded_events.append({
		"time": clock_str,
		"sim_time_sec": GameManager.simulated_match_time if GameManager != null else 0.0,
		"half": half_idx,
		"category": category,
		"message": message,
	})


func _flush_buffer() -> void:
	if _log_file == null or _buffered_lines.is_empty():
		return

	for line: String in _buffered_lines:
		_log_file.store_line(line)
	_buffered_lines.clear()
	_log_file.flush()


## --- Periodic Simulation Snapshots -------------------------------------------

func dump_periodic_snapshot(minute: int) -> void:
	if verbosity < Verbosity.ESSENTIAL or verbosity == Verbosity.OFF:
		return

	var team_a_name: String = _get_team_name(0)
	var team_b_name: String = _get_team_name(1)

	var score_a: int = GameManager.score[0]
	var score_b: int = GameManager.score[1]
	var phase_name: String = _get_phase_name(GameManager.current_phase)
	var stage_name: String = _get_stage_name(GameManager._last_match_stage)

	var stats_a: Dictionary = MatchStatsTracker.get_stats(0)
	var stats_b: Dictionary = MatchStatsTracker.get_stats(1)
	var adv_a: Dictionary = MatchStatsTracker.get_advanced_stats(0)
	var adv_b: Dictionary = MatchStatsTracker.get_advanced_stats(1)

	var mom_a: float = MatchStatsTracker.team_momentum[0]
	var mom_b: float = MatchStatsTracker.team_momentum[1]
	var urg_a: float = MatchWorldModel.instance.team_urgency[0] if MatchWorldModel.instance != null else 0.0
	var urg_b: float = MatchWorldModel.instance.team_urgency[1] if MatchWorldModel.instance != null else 0.0

	var com_a: float = MatchWorldModel.instance.team_com_x[0] if MatchWorldModel.instance != null else 0.0
	var com_b: float = MatchWorldModel.instance.team_com_x[1] if MatchWorldModel.instance != null else 0.0

	var out: String = "\n" + "=".repeat(80) + "\n"
	out += "[%02d:00 | H%d] [PERIODIC SNAPSHOT - %d']\n" % [minute, GameManager.current_half, minute]
	out += " Score:           %s %d - %d %s | Phase: %s | Stage: %s\n" % [team_a_name, score_a, score_b, team_b_name, phase_name, stage_name]
	out += " Expected Goals:  %s %.2f - %.2f %s | Shots (On Target): [%d(%d) vs %d(%d)]\n" % [
		team_a_name, adv_a.get("xg", 0.0), adv_b.get("xg", 0.0), team_b_name,
		stats_a.get("shots", 0), stats_a.get("shots_on_target", 0),
		stats_b.get("shots", 0), stats_b.get("shots_on_target", 0)
	]
	out += " Possession:      %s %.1f%% - %.1f%% %s | Field Tilt: %.1f%% - %.1f%%\n" % [
		team_a_name, stats_a.get("possession_pct", 50.0), stats_b.get("possession_pct", 50.0), team_b_name,
		adv_a.get("field_tilt_pct", 50.0), adv_b.get("field_tilt_pct", 50.0)
	]
	out += " Pass Completion: %s %.1f%% (%d/%d) - %.1f%% (%d/%d) %s\n" % [
		team_a_name, stats_a.get("pass_completion_pct", 0.0), MatchStatsTracker.passes_completed[0], stats_a.get("passes_attempted", 0),
		stats_b.get("pass_completion_pct", 0.0), MatchStatsTracker.passes_completed[1], stats_b.get("passes_attempted", 0), team_b_name
	]
	out += " PPDA:            %s %.1f - %.1f %s | VAEP: %s %+.2f - %+.2f %s\n" % [
		team_a_name, adv_a.get("ppda", 0.0), adv_b.get("ppda", 0.0), team_b_name,
		team_a_name, adv_a.get("vaep_total", 0.0), adv_b.get("vaep_total", 0.0), team_b_name
	]
	out += " Momentum:        %s %+.2f | %s %+.2f\n" % [team_a_name, mom_a, team_b_name, mom_b]
	out += " Urgency:         %s %+.2f | %s %+.2f\n" % [team_a_name, urg_a, team_b_name, urg_b]
	out += " Center of Mass:  %s COM X: %.1f | %s COM X: %.1f\n" % [team_a_name, com_a, team_b_name, com_b]
	out += "=".repeat(80) + "\n"

	if log_to_stdout:
		print(out)
	if log_to_file:
		_buffered_lines.append(out)
		_flush_buffer()


## --- Full-Time Comprehensive Analytical Report -------------------------------

func dump_fulltime_report(winner: int) -> void:
	if _fulltime_logged or verbosity == Verbosity.OFF:
		return
	_fulltime_logged = true

	var team_a_name: String = _get_team_name(0)
	var team_b_name: String = _get_team_name(1)
	var score_a: int = GameManager.score[0]
	var score_b: int = GameManager.score[1]

	var stats_a: Dictionary = MatchStatsTracker.get_stats(0)
	var stats_b: Dictionary = MatchStatsTracker.get_stats(1)
	var adv_a: Dictionary = MatchStatsTracker.get_advanced_stats(0)
	var adv_b: Dictionary = MatchStatsTracker.get_advanced_stats(1)

	var ratings: Dictionary[int, float] = MatchStatsTracker.compute_all_ratings()

	var winner_str: String = "DRAW"
	if winner == 0:
		winner_str = "%s WINS" % team_a_name
	elif winner == 1:
		winner_str = "%s WINS" % team_b_name

	var rpt: String = "\n\n"
	rpt += "################################################################################\n"
	rpt += "                POWERFOOTBALL-2D FULL-TIME MATCH ANALYTICS REPORT               \n"
	rpt += "################################################################################\n"
	rpt += " Final Score:   %s %d - %d %s (%s)\n" % [team_a_name, score_a, score_b, team_b_name, winner_str]
	rpt += " Simulated:     90:00 (Sim Time: %.1fs | Real Elapsed: %.1fs)\n" % [GameManager.simulated_match_time, GameManager.match_time]
	rpt += " Stoppage Time: H1: +%d min | H2: +%d min\n" % [GameManager.stoppage_minutes_half_1, GameManager.stoppage_minutes_half_2]
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += "                          MATCH TRADITIONAL BOX SCORE                           \n"
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += " %-30s | %18s | %18s\n" % ["METRIC", team_a_name, team_b_name]
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += " %-30s | %18d | %18d\n" % ["Goals", score_a, score_b]
	rpt += " %-30s | %17.1f%% | %17.1f%%\n" % ["Possession %", stats_a.get("possession_pct", 50.0), stats_b.get("possession_pct", 50.0)]
	rpt += " %-30s | %18d | %18d\n" % ["Total Shots", stats_a.get("shots", 0), stats_b.get("shots", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Shots on Target", stats_a.get("shots_on_target", 0), stats_b.get("shots_on_target", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Passes Attempted", stats_a.get("passes_attempted", 0), stats_b.get("passes_attempted", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Passes Completed", MatchStatsTracker.passes_completed[0], MatchStatsTracker.passes_completed[1]]
	rpt += " %-30s | %17.1f%% | %17.1f%%\n" % ["Pass Completion %", stats_a.get("pass_completion_pct", 0.0), stats_b.get("pass_completion_pct", 0.0)]
	rpt += " %-30s | %18d | %18d\n" % ["Fouls Committed", stats_a.get("fouls", 0), stats_b.get("fouls", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Yellow Cards", stats_a.get("yellow_cards", 0), stats_b.get("yellow_cards", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Red Cards", stats_a.get("red_cards", 0), stats_b.get("red_cards", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Corners", stats_a.get("corners", 0), stats_b.get("corners", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Offsides", stats_a.get("offsides", 0), stats_b.get("offsides", 0)]
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += "                     ADVANCED MONEYBALL ANALYTICS TABLE                         \n"
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += " %-30s | %18s | %18s\n" % ["METRIC", team_a_name, team_b_name]
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += " %-30s | %18.2f | %18.2f\n" % ["Expected Goals (xG)", adv_a.get("xg", 0.0), adv_b.get("xg", 0.0)]
	rpt += " %-30s | %18.2f | %18.2f\n" % ["Post-Shot xG (PSxG)", adv_a.get("psxg", 0.0), adv_b.get("psxg", 0.0)]
	rpt += " %-30s | %18.2f | %18.2f\n" % ["GK Goals Prevented", adv_a.get("goals_prevented", 0.0), adv_b.get("goals_prevented", 0.0)]
	rpt += " %-30s | %18.3f | %18.3f\n" % ["Expected Threat (xT Delta)", adv_a.get("xt_delta", 0.0), adv_b.get("xt_delta", 0.0)]
	rpt += " %-30s | %17.1f%% | %17.1f%%\n" % ["Field Tilt % (Final 3rd)", adv_a.get("field_tilt_pct", 50.0), adv_b.get("field_tilt_pct", 50.0)]
	rpt += " %-30s | %18.2f | %18.2f\n" % ["PPDA (Pressing Intensity)", adv_a.get("ppda", 0.0), adv_b.get("ppda", 0.0)]
	rpt += " %-30s | %18d | %18d\n" % ["Packing Rate (Players)", adv_a.get("packing_total", 0), adv_b.get("packing_total", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Impect (Defenders Bypassed)", adv_a.get("impect_total", 0), adv_b.get("impect_total", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Progressive Passes", adv_a.get("progressive_passes", 0), adv_b.get("progressive_passes", 0)]
	rpt += " %-30s | %18d | %18d\n" % ["Progressive Carries", adv_a.get("progressive_carries", 0), adv_b.get("progressive_carries", 0)]
	rpt += " %-30s | %18.2f | %18.2f\n" % ["VAEP Total Value", adv_a.get("vaep_total", 0.0), adv_b.get("vaep_total", 0.0)]
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += "                    INDIVIDUAL PLAYER RATINGS & PERFORMANCE                     \n"
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += " #  | POS | NAME                 | TEAM | G | A | SH(OT) |  xG  |  xA  | PASS(C/A) | TCK | INT | RATING\n"
	rpt += "----+-----+----------------------+------+---+---+--------+------+------+-----------+-----+-----+-------\n"

	var player_rows: Array[Dictionary] = []
	for team_idx: int in range(2):
		var t_name: String = "HOME" if team_idx == 0 else "AWAY"
		for squad_idx: int in range(11):
			var pdata: PlayerData = DataLoader.get_player(team_idx, squad_idx)
			var key: int = team_idx * 1000 + squad_idx
			var pevents: PlayerRatingCalculator.PlayerMatchEvents = MatchStatsTracker.get_player_events(key)
			var rating_val: float = ratings.get(key, 6.0)

			var pname: String = pdata.player_name if pdata != null else ("Player %d" % squad_idx)
			var pos: String = pdata.position_role if pdata != null else "SUB"

			var row_str: String = " %-2d | %-3s | %-20s | %-4s | %d | %d |  %d(%d)  | %4.2f | %4.2f | %4d/%-4d | %3d | %3d |  %4.1f\n" % [
				squad_idx + 1, pos, pname.left(20), t_name,
				pevents.goals, pevents.assists,
				pevents.shots_on_target + pevents.shots_off_target, pevents.shots_on_target,
				pevents.xg, pevents.xa,
				pevents.passes_completed, pevents.passes_completed + pevents.passes_failed,
				pevents.tackles_won, pevents.interceptions,
				rating_val
			]
			rpt += row_str

			player_rows.append({
				"team": team_idx,
				"squad_index": squad_idx,
				"name": pname,
				"position": pos,
				"goals": pevents.goals,
				"assists": pevents.assists,
				"shots": pevents.shots_on_target + pevents.shots_off_target,
				"shots_on_target": pevents.shots_on_target,
				"xg": pevents.xg,
				"xa": pevents.xa,
				"passes_completed": pevents.passes_completed,
				"passes_attempted": pevents.passes_completed + pevents.passes_failed,
				"tackles_won": pevents.tackles_won,
				"interceptions": pevents.interceptions,
				"rating": rating_val
			})

	rpt += "--------------------------------------------------------------------------------\n"
	rpt += "                      SIMULATION INVARIANT HEALTH REPORT                        \n"
	rpt += "--------------------------------------------------------------------------------\n"
	rpt += " NaN / Inf Float Violations: %d\n" % _health_nan_inf_count
	rpt += " Boundary Escape Anomalies:  %d\n" % _health_boundary_escapes
	rpt += " Loose Ball Stall Episodes:  %d\n" % _health_stalls_detected
	rpt += " Invariant Assertion Status: %s\n" % ("PASS" if (_health_nan_inf_count == 0 and _health_boundary_escapes == 0) else "FAIL")
	rpt += "################################################################################\n\n"

	if log_to_stdout:
		print(rpt)
	if log_to_file:
		_buffered_lines.append(rpt)
		_flush_buffer()

	_export_json_summary(team_a_name, team_b_name, score_a, score_b, winner_str, stats_a, stats_b, adv_a, adv_b, player_rows)


func _export_json_summary(
	team_a_name: String, team_b_name: String,
	score_a: int, score_b: int, winner_str: String,
	stats_a: Dictionary, stats_b: Dictionary,
	adv_a: Dictionary, adv_b: Dictionary,
	player_rows: Array[Dictionary]
) -> void:
	if json_summary_path.is_empty():
		return

	var summary_data: Dictionary = {
		"metadata": {
			"timestamp": Time.get_datetime_string_from_system(),
			"duration_simulated_sec": GameManager.simulated_match_time,
			"real_elapsed_sec": GameManager.match_time,
			"status": "pass" if (_health_nan_inf_count == 0 and _health_boundary_escapes == 0) else "fail"
		},
		"match_result": {
			"team_a": team_a_name,
			"team_b": team_b_name,
			"score": [score_a, score_b],
			"winner": winner_str
		},
		"traditional_stats": {
			"home": stats_a,
			"away": stats_b
		},
		"advanced_stats": {
			"home": adv_a,
			"away": adv_b
		},
		"player_stats": player_rows,
		"events_timeline": _recorded_events,
		"health_diagnostics": {
			"nan_inf_count": _health_nan_inf_count,
			"boundary_escapes": _health_boundary_escapes,
			"stall_episodes": _health_stalls_detected
		}
	}

	var json_str: String = JSON.stringify(summary_data, "\t")
	var jfile: FileAccess = FileAccess.open(json_summary_path, FileAccess.WRITE)
	if jfile != null:
		jfile.store_string(json_str)
		jfile.close()
		log_event("TELEMETRY", "Saved full JSON match summary -> %s" % json_summary_path, Verbosity.ESSENTIAL)


## --- Signal Handlers ---------------------------------------------------------

func _on_kickoff_started() -> void:
	_match_started = true
	log_event("MATCH", "Kickoff flow started for Half %d | Match Clock: %s" % [
		GameManager.current_half, GameManager.get_clock_string()
	], Verbosity.ESSENTIAL)


func _on_kickoff_confirmed(team: int) -> void:
	var team_name: String = _get_team_name(team)
	log_event("MATCH", "Kickoff confirmed! Possession awarded to %s" % team_name, Verbosity.ESSENTIAL)


func _on_half_time_started() -> void:
	log_event("MATCH", "Half Time whistle blown! Score: %s %d - %d %s" % [
		_get_team_name(0), GameManager.score[0], GameManager.score[1], _get_team_name(1)
	], Verbosity.ESSENTIAL)


func _on_half_time_ended() -> void:
	log_event("MATCH", "Second Half commencing! Ends swapped.", Verbosity.ESSENTIAL)


func _on_match_ended(winner: int) -> void:
	log_event("MATCH", "Full Time whistle blown! Winner: %s" % (
		"DRAW" if winner < 0 else _get_team_name(winner)
	), Verbosity.ESSENTIAL)
	dump_fulltime_report(winner)


func _on_stoppage_time_announced(added_minutes: int, half: int) -> void:
	log_event("MATCH", "Stoppage Time Announced: +%d minute(s) added to Half %d" % [added_minutes, half], Verbosity.ESSENTIAL)


func _on_match_phase_changed(phase: int) -> void:
	log_event("PHASE", "Match phase transitioned to %s (%d)" % [_get_phase_name(phase), phase], Verbosity.VERBOSE)


func _on_match_stage_changed(stage: int) -> void:
	log_event("TACTIC", "Macro Match Stage shifted to %s (%d)" % [_get_stage_name(stage), stage], Verbosity.TACTICAL)


func _on_simulation_speed_changed(speed: float) -> void:
	log_event("SIM", "Simulation playback speed changed to %.1fx" % speed, Verbosity.ESSENTIAL)


func _on_goal_scored(team: int, scorer: Node) -> void:
	var team_name: String = _get_team_name(team)
	var scorer_name: String = "Unknown"
	var squad_idx: int = -1
	var is_og: bool = false

	var controller := scorer as HeavyPlayerController
	if controller != null and is_instance_valid(controller):
		var pdata: PlayerData = controller.get_meta(&"player_data", null) as PlayerData
		if pdata != null:
			scorer_name = pdata.player_name
		else:
			scorer_name = controller.name
		squad_idx = controller.squad_index
		if controller.team != team:
			is_og = true

	var og_str: String = " (OWN GOAL)" if is_og else ""
	log_event("GOAL", "GOAL FOR %s! Scored by %s (#%d)%s | Scoreline: %s %d - %d %s" % [
		team_name, scorer_name, squad_idx + 1, og_str,
		_get_team_name(0), GameManager.score[0], GameManager.score[1], _get_team_name(1)
	], Verbosity.ESSENTIAL)


func _on_shot_taken(shooter: Node, pos: Vector2, xg_val: float, psxg_val: float, is_on_target: bool) -> void:
	var s_name: String = "Unknown"
	var team_name: String = "Unknown"
	var controller := shooter as HeavyPlayerController
	if controller != null and is_instance_valid(controller):
		team_name = _get_team_name(controller.team)
		var pdata: PlayerData = controller.get_meta(&"player_data", null) as PlayerData
		s_name = pdata.player_name if pdata != null else controller.name

	var target_str: String = "ON TARGET" if is_on_target else "OFF TARGET"
	log_event("SHOT", "Shot by %s (%s) from (%.0f, %.0f) -> %s [xG: %.2f, PSxG: %.2f]" % [
		s_name, team_name, pos.x, pos.y, target_str, xg_val, psxg_val
	], Verbosity.VERBOSE if not is_on_target else Verbosity.TACTICAL)


func _on_powerful_shot_landed(shooter: HeavyPlayerController, speed: float, ratio: float) -> void:
	var s_name: String = shooter.name if is_instance_valid(shooter) else "Player"
	log_event("SHOT", "POWERFUL STRIKE by %s! Speed: %.1f px/s, Charge: %.0f%% (Hit-stop activated)" % [
		s_name, speed, ratio * 100.0
	], Verbosity.VERBOSE)


func _on_pass_completed(passer: Node, receiver: Node, _orig: Vector2, _dest: Vector2, packed: int, xt: float) -> void:
	var p_name: String = passer.name if is_instance_valid(passer) else "Passer"
	var r_name: String = receiver.name if is_instance_valid(receiver) else "Receiver"
	log_event("PASS", "Pass completed: %s -> %s (Packed: %d, xT Delta: %+.3f)" % [
		p_name, r_name, packed, xt
	], Verbosity.VERBOSE)


func _on_carry_completed(player: Node, _start: Vector2, _end: Vector2, prog: bool, xt: float) -> void:
	if prog:
		var p_name: String = player.name if is_instance_valid(player) else "Carrier"
		log_event("CARRY", "Progressive Carry completed by %s (xT Delta: %+.3f)" % [p_name, xt], Verbosity.VERBOSE)


func _on_defensive_action_logged(player: Node, action_type: StringName, pos: Vector2) -> void:
	var p_name: String = player.name if is_instance_valid(player) else "Defender"
	log_event("DEFENSE", "Defensive action logged: %s by %s at (%.0f, %.0f)" % [
		action_type, p_name, pos.x, pos.y
	], Verbosity.VERBOSE)


func _on_tackle_won(winner: Node, loser: Node) -> void:
	var w_name: String = winner.name if is_instance_valid(winner) else "Player"
	var l_name: String = loser.name if is_instance_valid(loser) else "Opponent"
	log_event("TACKLE", "Tackle won by %s against %s" % [w_name, l_name], Verbosity.TACTICAL)


func _on_turnover_predicted(intercepting_team: int) -> void:
	log_event("TURNOVER", "Anticipatory turnover predicted in favor of %s" % _get_team_name(intercepting_team), Verbosity.VERBOSE)


func _on_foul_committed(fouler: Node, victim: Node, pos: Vector2) -> void:
	var f_name: String = fouler.name if is_instance_valid(fouler) else "Fouler"
	var v_name: String = victim.name if is_instance_valid(victim) else "Victim"
	log_event("FOUL", "Foul committed: %s on %s at (%.0f, %.0f)" % [f_name, v_name, pos.x, pos.y], Verbosity.VERBOSE)


func _on_referee_awarded_foul(_ref: Node, fouler: Node, victim: Node, pos: Vector2) -> void:
	var f_name: String = fouler.name if is_instance_valid(fouler) else "Fouler"
	var v_name: String = victim.name if is_instance_valid(victim) else "Victim"
	log_event("REFEREE", "Referee AWARDS FOUL: %s on %s at (%.0f, %.0f)" % [f_name, v_name, pos.x, pos.y], Verbosity.TACTICAL)


func _on_referee_played_on(_ref: Node, fouler: Node, victim: Node, _pos: Vector2) -> void:
	var f_name: String = fouler.name if is_instance_valid(fouler) else "Fouler"
	var v_name: String = victim.name if is_instance_valid(victim) else "Victim"
	log_event("REFEREE", "Referee plays ADVANTAGE / PLAY ON after %s challenged %s" % [f_name, v_name], Verbosity.VERBOSE)


func _on_yellow_card_shown(player: Node, team: int) -> void:
	var p_name: String = player.name if is_instance_valid(player) else "Player"
	log_event("CARD", "YELLOW CARD shown to %s (%s)!" % [p_name, _get_team_name(team)], Verbosity.ESSENTIAL)


func _on_red_card_shown(player: Node, team: int, is_second_yellow: bool) -> void:
	var p_name: String = player.name if is_instance_valid(player) else "Player"
	var type_str: String = "SECOND YELLOW -> RED" if is_second_yellow else "STRAIGHT RED"
	log_event("CARD", "%s CARD shown to %s (%s)! Player sent off!" % [type_str, p_name, _get_team_name(team)], Verbosity.ESSENTIAL)


func _on_offside_called(offside_player: Node, defending_team: int, pos: Vector2) -> void:
	var p_name: String = offside_player.name if is_instance_valid(offside_player) else "Attacker"
	log_event("OFFSIDE", "Offside called against %s vs %s defensive line at (%.0f, %.0f)" % [
		p_name, _get_team_name(defending_team), pos.x, pos.y
	], Verbosity.TACTICAL)


func _on_goal_kick_started(team: int, _pos: Vector2) -> void:
	log_event("SETPIECE", "Goal Kick awarded to %s" % _get_team_name(team), Verbosity.VERBOSE)


func _on_corner_kick_started(team: int, _pos: Vector2) -> void:
	log_event("SETPIECE", "Corner Kick awarded to %s" % _get_team_name(team), Verbosity.TACTICAL)


func _on_throw_in_started(team: int, _pos: Vector2) -> void:
	log_event("SETPIECE", "Throw-in awarded to %s" % _get_team_name(team), Verbosity.VERBOSE)


func _on_free_kick_started(team: int, _pos: Vector2, is_direct: bool) -> void:
	var type_str: String = "Direct Free Kick" if is_direct else "Indirect Free Kick"
	log_event("SETPIECE", "%s awarded to %s" % [type_str, _get_team_name(team)], Verbosity.TACTICAL)


func _on_penalty_started(team: int, _pos: Vector2) -> void:
	log_event("SETPIECE", "PENALTY KICK AWARDED TO %s!" % _get_team_name(team), Verbosity.ESSENTIAL)


func _on_shootout_kick_result(team: int, kick_idx: int, scored: bool) -> void:
	var res_str: String = "SCORED" if scored else "MISSED/SAVED"
	log_event("SHOOTOUT", "Shootout Kick #%d for %s: %s" % [kick_idx + 1, _get_team_name(team), res_str], Verbosity.ESSENTIAL)


func _on_manager_formation_changed(team: int, new_formation: String) -> void:
	log_event("TACTIC", "TACTICAL SHIFT: %s switches formation to %s" % [_get_team_name(team), new_formation], Verbosity.TACTICAL)


func _on_team_urgency_updated(team: int, urgency: float) -> void:
	log_event("TACTIC", "%s Match Urgency adjusted: %+.2f" % [_get_team_name(team), urgency], Verbosity.VERBOSE)


func _on_team_momentum_updated(team: int, momentum: float) -> void:
	log_event("MOMENTUM", "%s Momentum updated: %+.2f" % [_get_team_name(team), momentum], Verbosity.VERBOSE)


func _on_emergency_tactics_triggered(team: int, tactic_type: StringName) -> void:
	log_event("TACTIC", "EMERGENCY TACTICS TRIGGERED for %s: %s!" % [_get_team_name(team), tactic_type], Verbosity.ESSENTIAL)


func _on_press_trigger_changed(active: bool, trigger_type: int, carrier: Node, _pos: Vector2) -> void:
	if active:
		var c_name: String = carrier.name if is_instance_valid(carrier) else "Carrier"
		log_event("PRESS", "Press trigger ARMED: %s on %s" % [_get_press_trigger_name(trigger_type), c_name], Verbosity.TACTICAL)


func _on_substitution_made(team: int, out_idx: int, in_idx: int) -> void:
	var p_out: PlayerData = DataLoader.get_player(team, out_idx)
	var p_in: PlayerData = DataLoader.get_player(team, in_idx)
	var name_out: String = p_out.player_name if p_out != null else ("#%d" % (out_idx + 1))
	var name_in: String = p_in.player_name if p_in != null else ("#%d" % (in_idx + 1))
	log_event("SUB", "SUBSTITUTION for %s: %s OUT <-> %s IN" % [_get_team_name(team), name_out, name_in], Verbosity.TACTICAL)


func _on_player_mood_changed(player: Node, tier: int) -> void:
	var p_name: String = player.name if is_instance_valid(player) else "Player"
	var tier_name: String = "NORMAL"
	if tier == 0:
		tier_name = "SLUMP (Performance Drops)"
	elif tier == 2:
		tier_name = "STREAK (On Fire / High Confidence)"
	log_event("MOOD", "Mood tier changed for %s -> %s" % [p_name, tier_name], Verbosity.TACTICAL)


func _on_stamina_depleted(player: Node) -> void:
	var p_name: String = player.name if is_instance_valid(player) else "Player"
	log_event("STAMINA", "Stamina fully depleted for %s (Sprinting disabled / Pace reduced)" % p_name, Verbosity.TACTICAL)


## --- Health & Invariant Tracking ---------------------------------------------

func report_health_anomaly(anomaly_type: String, detail: String) -> void:
	match anomaly_type:
		"nan_inf":
			_health_nan_inf_count += 1
		"boundary_escape":
			_health_boundary_escapes += 1
		"stall":
			_health_stalls_detected += 1

	log_event("HEALTH", "ANOMALY [%s]: %s" % [anomaly_type.to_upper(), detail], Verbosity.ESSENTIAL)


## --- String Resolvers --------------------------------------------------------

func _get_team_name(team: int) -> String:
	if DataLoader.league != null:
		var tdata: TeamData = DataLoader.get_team(team)
		if tdata != null and not tdata.team_name.is_empty():
			return tdata.team_name
	return "Team A" if team == 0 else "Team B"


func _get_phase_name(phase: int) -> String:
	match phase:
		GameManager.MatchPhase.PREGAME: return "PREGAME"
		GameManager.MatchPhase.FIRST_HALF: return "FIRST_HALF"
		GameManager.MatchPhase.KICKOFF: return "KICKOFF"
		GameManager.MatchPhase.IN_PLAY: return "IN_PLAY"
		GameManager.MatchPhase.GOAL_SCORED: return "GOAL_SCORED"
		GameManager.MatchPhase.HALF_TIME: return "HALF_TIME"
		GameManager.MatchPhase.SECOND_HALF: return "SECOND_HALF"
		GameManager.MatchPhase.FULL_TIME: return "FULL_TIME"
		GameManager.MatchPhase.EXTRA_TIME: return "EXTRA_TIME"
		GameManager.MatchPhase.GOAL_KICK: return "GOAL_KICK"
		GameManager.MatchPhase.CORNER_KICK: return "CORNER_KICK"
		GameManager.MatchPhase.THROW_IN: return "THROW_IN"
		GameManager.MatchPhase.FREE_KICK: return "FREE_KICK"
		GameManager.MatchPhase.PENALTY_KICK: return "PENALTY_KICK"
		GameManager.MatchPhase.PENALTY_SHOOTOUT: return "PENALTY_SHOOTOUT"
		_: return "UNKNOWN"


func _get_stage_name(stage: int) -> String:
	match stage:
		0: return "SIZING_UP (0-15')"
		1: return "EQUILIBRIUM (15-60')"
		2: return "TRANSITIONS (60-75')"
		3: return "GAME_CRUNCH (75-90')"
		_: return "UNKNOWN"


func _get_press_trigger_name(t: int) -> String:
	match t:
		1: return "BACKWARD_PASS"
		2: return "SQUARE_PASS"
		3: return "TOUCHLINE_ISOLATION"
		4: return "HEAVY_TOUCH"
		5: return "FACING_OWN_GOAL"
		6: return "PROLONGED_POSSESSION"
		_: return "NONE"
