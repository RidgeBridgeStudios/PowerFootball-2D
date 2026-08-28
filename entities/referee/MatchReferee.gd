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

var current_data: RefereeData = null
var _coordinator: SetPieceCoordinator = null
var _matchup_key: String = ""

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


func _base_threshold() -> float:
	# Invert strictness: strict = low threshold = easy to award a foul.
	return lerpf(0.80, 0.25, current_data.strictness)


func _update_temperature() -> void:
	var goal_diff_factor: float = absf(float(GameManager.score[0] - GameManager.score[1])) * 0.08
	var time_factor: float = GameManager.match_time / GameManager.match_duration
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
	var roll: float = randf()
	var award_foul: bool = severity > effective_threshold or roll < (severity / (effective_threshold + 0.01))

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
	else:
		GameEvents.referee_played_on.emit(self, fouler, victim, foul_pos)


func _on_goal_scored(_team: int) -> void:
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

	RefereeLoader.save_referees()
