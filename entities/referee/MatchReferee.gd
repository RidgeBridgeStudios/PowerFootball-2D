##
## MatchReferee
## The live referee brain for one match. Intercepts GameEvents.foul_committed,
## evaluates whether to award the foul using RefereeData personality and match
## context, then either calls set_piece_coordinator.handle_foul() or plays on.
## Tracks per-match stats and writes them back to RefereeData via RefereeLoader
## at FULL_TIME.
## "Match temperature" rises with goal differential, elapsed time in STREAK
## moods across both squads, and total fouls already awarded this match. A
## high-temperature match shifts composure-weak referees toward leniency (they
## let the game flow) or toward strictness (they lose the plot) depending on
## their incoherence score.
## Depends on: GameEvents, GameManager, RefereeData, SetPieceCoordinator.
## Exposes: bind(), current_data, get_match_temperature()
##

class_name MatchReferee
extends Node

## Severity at or above which a foul earns a yellow card outright.
const YELLOW_BASE_THRESHOLD: float = 0.65
## Severity at or above which a foul earns a straight red (bypasses yellow).
const RED_BASE_THRESHOLD: float = 0.88

var current_data: RefereeData = null
var _coordinator: SetPieceCoordinator = null
var _matchup_key: String = ""

## Yellow/red cards shown this match (for stats). Distinct from each
## PlayerData's own per-player counts.
var _yellow_cards_this_match: int = 0
var _red_cards_this_match: int = 0

## Rises over the match. Contributes to threshold drift for composure-weak refs.
var _match_temperature: float = 0.0
## Fouls awarded this match (for stats and temperature).
var _fouls_this_match: int = 0
var _penalties_this_match: int = 0
## Which team the unprofessional referee secretly favours. Decided at bind().
## -1 = neutral (when unprofessionalism < 0.15).
var _favoured_team: int = -1
## Per-match running foul threshold, starts at the base derived from strictness
## and drifts during the match based on consistency + temperature.
var _current_foul_threshold: float = 0.5
## True once FULL_TIME stats have been logged (guard against double-write).
var _stats_logged: bool = false


func bind(data: RefereeData, coordinator: SetPieceCoordinator, team_a_name: String, team_b_name: String) -> void:
	current_data = data
	_coordinator = coordinator
	_matchup_key = RefereeData.make_matchup_key(team_a_name, team_b_name)

	_match_temperature = 0.0
	_fouls_this_match = 0
	_penalties_this_match = 0
	_stats_logged = false
	_favoured_team = -1
	_yellow_cards_this_match = 0
	_red_cards_this_match = 0
	_reset_player_card_counts()

	if current_data == null:
		return

	_current_foul_threshold = _base_threshold()
	if current_data.unprofessionalism >= 0.15:
		_favoured_team = randi() % 2

	if not GameEvents.foul_committed.is_connected(_on_foul_committed):
		GameEvents.foul_committed.connect(_on_foul_committed)
	if not GameEvents.goal_scored.is_connected(_on_goal_scored):
		GameEvents.goal_scored.connect(_on_goal_scored)
	if not GameEvents.match_phase_changed.is_connected(_on_match_phase_changed):
		GameEvents.match_phase_changed.connect(_on_match_phase_changed)


func get_match_temperature() -> float:
	return clampf(_match_temperature, 0.0, 1.0)


## Zeroes every registered player's per-match card counts. Reads the roster via
## MatchWorldModel (never the scene tree) since it only runs once at bind time,
## not on a hot path.
func _reset_player_card_counts() -> void:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return
	for node: HeavyPlayerController in world.player_nodes:
		if node == null or not is_instance_valid(node):
			continue
		var pdata: PlayerData = node.get_meta(&"player_data", null) as PlayerData
		if pdata != null:
			pdata.yellow_cards_this_match = 0
			pdata.red_cards_this_match = 0


func _base_threshold() -> float:
	# Invert strictness: strict = low threshold = easy to award a foul.
	return lerpf(0.80, 0.25, current_data.strictness)


func _update_temperature() -> void:
	var goal_diff_factor: float = absf(float(GameManager.score[0] - GameManager.score[1])) * 0.08
	var time_factor: float = GameManager.get_match_time_ratio()
	var foul_factor: float = _fouls_this_match * 0.03
	_match_temperature = clampf(goal_diff_factor + time_factor * 0.4 + foul_factor, 0.0, 1.0)


func _drift_threshold() -> void:
	var drift_range: float = lerpf(0.0, 0.20, 1.0 - current_data.consistency)
	var drift: float = randf_range(-drift_range, drift_range)
	# Composure-weak refs get pushed further by high temperature.
	var temperature_push: float = _match_temperature * (1.0 - current_data.composure) * 0.15
	# Incoherent refs may drift in either direction randomly under heat.
	if current_data.incoherence > 0.5 and _match_temperature > 0.6:
		drift += randf_range(-0.10, 0.10) * current_data.incoherence
	_current_foul_threshold = clampf(_current_foul_threshold + drift + temperature_push, 0.10, 0.90)


func _on_foul_committed(fouler: Node, victim: Node, foul_pos: Vector2) -> void:
	if current_data == null or _coordinator == null:
		# Not properly bound — fall through to the old, always-award behaviour
		# rather than silently eating every foul for the rest of the match.
		if _coordinator != null:
			_coordinator.handle_foul(fouler as HeavyPlayerController, victim as HeavyPlayerController, foul_pos)
		return
	if GameManager.current_phase != GameManager.MatchPhase.IN_PLAY:
		return

	var fouler_player := fouler as HeavyPlayerController
	var victim_player := victim as HeavyPlayerController

	# Base: tackles always start at moderate severity.
	var severity: float = 0.50

	# Heavier attackers trampling lighter defenders raises severity.
	if fouler_player != null and victim_player != null:
		var mass_ratio: float = fouler_player.player_mass / maxf(victim_player.player_mass, 1.0)
		severity += (mass_ratio - 1.0) * 0.12

	# A fouling player in STREAK mood is more aggressive — raises severity.
	var fouler_mood: MoodSystem = fouler_player.get_mood() if fouler_player != null else null
	if fouler_mood != null and fouler_mood.current_tier == MoodSystem.Tier.STREAK:
		severity += 0.08

	severity = clampf(severity, 0.0, 1.0)

	var bias: float = 0.0
	if _favoured_team >= 0 and current_data.unprofessionalism > 0.0:
		# If the fouler is on the favoured team, raise the threshold slightly
		# (harder to get awarded). If the victim is on the favoured team,
		# lower the threshold (easier to get awarded).
		var favour_sign: float = 0.0
		if fouler_player != null and fouler_player.team == _favoured_team:
			favour_sign = 1.0
		elif victim_player != null and victim_player.team == _favoured_team:
			favour_sign = -1.0
		bias = favour_sign * current_data.unprofessionalism * 0.25

	var effective_threshold: float = clampf(_current_foul_threshold + bias, 0.10, 0.90)
	var roll_noise: float = randf_range(-0.08, 0.08)
	var award_foul: bool = (severity + roll_noise) >= effective_threshold

	# Incoherence override: an incoherent referee can randomly reverse their
	# decision under high match temperature.
	if current_data.incoherence > 0.4 and _match_temperature > 0.5:
		var flip_chance: float = current_data.incoherence * _match_temperature * 0.30
		if randf() < flip_chance:
			award_foul = not award_foul

	if award_foul:
		_coordinator.handle_foul(fouler_player, victim_player, foul_pos)
		_fouls_this_match += 1
		if GameManager.current_phase == GameManager.MatchPhase.PENALTY_KICK:
			_penalties_this_match += 1
		_update_temperature()
		_drift_threshold()
		GameEvents.referee_awarded_foul.emit(self, fouler, victim, foul_pos)
		_evaluate_card(fouler_player, severity)
	else:
		GameEvents.referee_played_on.emit(self, fouler, victim, foul_pos)


## Second-order decision on top of an already-awarded foul: does this severity
## also earn a card? Thresholds drift with referee personality and match heat,
## same as the award-a-foul decision above.
func _evaluate_card(fouler_player: HeavyPlayerController, severity: float) -> void:
	if fouler_player == null or not is_instance_valid(fouler_player) or current_data == null:
		return

	var player_data: PlayerData = fouler_player.get_meta(&"player_data", null) as PlayerData
	if player_data == null:
		return

	var effective_severity: float = severity
	if current_data.incoherence > 0.5:
		effective_severity = clampf(effective_severity + randf_range(-0.12, 0.12), 0.0, 1.0)

	var yellow_threshold: float = YELLOW_BASE_THRESHOLD
	var red_threshold: float = RED_BASE_THRESHOLD
	var second_yellow_threshold: float = 0.45

	if current_data.strictness > 0.7:
		yellow_threshold -= 0.10
		red_threshold -= 0.10
		second_yellow_threshold -= 0.10
	if current_data.composure < 0.3 and _match_temperature > 0.6:
		yellow_threshold -= 0.08
		red_threshold -= 0.08
		second_yellow_threshold -= 0.08
	if _favoured_team >= 0 and fouler_player.team == _favoured_team:
		var favour_raise: float = current_data.unprofessionalism * 0.15
		yellow_threshold += favour_raise
		red_threshold += favour_raise
		second_yellow_threshold += favour_raise

	yellow_threshold = clampf(yellow_threshold, 0.0, 1.0)
	red_threshold = clampf(red_threshold, 0.0, 1.0)
	second_yellow_threshold = clampf(second_yellow_threshold, 0.0, 1.0)

	# Straight red bypasses the yellow check entirely.
	if effective_severity >= red_threshold:
		_award_red(fouler_player, player_data, false)
		return

	var already_booked: bool = player_data.yellow_cards_this_match >= 1
	var earns_yellow: bool = effective_severity >= yellow_threshold
	if not earns_yellow and already_booked and effective_severity >= second_yellow_threshold:
		earns_yellow = true
	if not earns_yellow:
		return

	player_data.yellow_cards_this_match += 1
	_yellow_cards_this_match += 1
	GameEvents.yellow_card_shown.emit(fouler_player, fouler_player.team)

	# Second bookable offence — immediate conversion to red.
	if player_data.yellow_cards_this_match >= 2:
		_award_red(fouler_player, player_data, true)


func _award_red(fouler_player: HeavyPlayerController, player_data: PlayerData, is_second_yellow: bool) -> void:
	player_data.red_cards_this_match += 1
	_red_cards_this_match += 1
	current_data.red_cards_issued += 1
	GameEvents.red_card_shown.emit(fouler_player, fouler_player.team, is_second_yellow)
	_send_off(fouler_player)


## Removes the sent-off player from play without freeing them: hides the node,
## disables its processing, marks the underlying PlayerData unavailable for the
## next match, and drops the slot from MatchWorldModel so teammate counts stay
## accurate. A sent-off goalkeeper additionally asks PitchScene for an
## emergency substitution.
func _send_off(player: HeavyPlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return

	player.hide()
	player.process_mode = Node.PROCESS_MODE_DISABLED

	var player_data: PlayerData = player.get_meta(&"player_data", null) as PlayerData
	if player_data != null:
		player_data.is_unavailable = true

	if MatchWorldModel.instance != null:
		MatchWorldModel.instance.mark_player_unavailable(player)

	if player_data != null and player_data.position_role == "GK":
		GameEvents.goalkeeper_sent_off.emit(player.team)


func _on_goal_scored(_team: int, _scorer: Node = null) -> void:
	_update_temperature()
	_drift_threshold()


func _on_match_phase_changed(phase: int) -> void:
	if phase == GameManager.MatchPhase.FULL_TIME and not _stats_logged:
		_log_stats()


func _log_stats() -> void:
	if current_data == null or _stats_logged:
		return
	_stats_logged = true

	current_data.matches_officiated += 1
	current_data.fouls_awarded += _fouls_this_match
	current_data.penalties_awarded += _penalties_this_match

	var matchup: Dictionary = current_data.get_or_create_matchup(_matchup_key)
	matchup["matches"] = matchup.get("matches", 0) + 1
	matchup["fouls_awarded"] = matchup.get("fouls_awarded", 0) + _fouls_this_match
	matchup["penalties_awarded"] = matchup.get("penalties_awarded", 0) + _penalties_this_match
	matchup["yellow_cards"] = matchup.get("yellow_cards", 0) + _yellow_cards_this_match
	matchup["red_cards"] = matchup.get("red_cards", 0) + _red_cards_this_match

	RefereeLoader.save_referees()
