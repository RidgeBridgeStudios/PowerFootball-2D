##
## MatchStatsTracker (Autoload singleton)
##
## Per-match counting and advanced Moneyball analytics for full-time review
## and career mode persistence: possession, shots, passes, fouls, cards,
## corners, offsides, Expected Goals (xG), Post-Shot xG (PSxG), Expected Threat (xT),
## Expected Assists (xA), Passes Per Defensive Action (PPDA), Field Tilt %,
## Packing Rate, Impect, Progressive Actions (Passes & Carries), VAEP, and
## Goalkeeper Goals Prevented.
##
## End-of-match player ratings and career accumulations track per-player
## granularity in a Dictionary[int, PlayerMatchEvents].
##
## Depends on: GameEvents, GameManager, MatchWorldModel, DataLoader,
##             HeavyPlayerController, PlayerRatingCalculator, UtilityMath,
##             PlayerData.
## Exposes: record_shot(), record_pass_attempt(), record_pass_completed(),
##          record_carry_completed(), record_defensive_action(), record_foul(),
##          record_corner(), record_offside(), record_goal(), record_assist(),
##          record_own_goal(), get_player_events(), compute_all_ratings(),
##          get_stats(), get_advanced_stats(), reset(), init_players(),
##          is_pass_toward_teammate(), stop_possession_sampling(),
##          team_momentum.
##

extends Node

## Physics ticks between possession samples (0.5s at 60Hz).
const POSSESSION_SAMPLE_INTERVAL: int = 30
## charge_ratio above which a recorded shot counts as "on target" — the only
## signal data available at the ball_struck call sites is power, not aim.
const SHOT_ON_TARGET_THRESHOLD: float = 0.5
## Half-angle cosine (~35 degrees) for the "pass found a teammate" cone check.
const PASS_CONE_COS: float = 0.82
## Passes farther than this are treated as unlikely to reach anyone, whatever
## the aim.
const PASS_MAX_RANGE: float = 500.0

## --- Macro momentum accumulator (anti-snowball) ------------------------------
## Team Momentum (POWERFOOTBALL_MASTER_VISION.md Part V / the architecture
## plan) — a continuously-decaying, discretely-impulsed scalar per team,
## quadratically self-dampened so no single event chain produces a runaway
## blowout. Publishes via GameEvents.team_momentum_updated; MatchWorldModel
## caches it, MoodSystem reads it as an ambient composure drift, PitchScene
## reacts to a sharp swing with a touchline shout.
const MOMENTUM_DECAY_LAMBDA: float = 0.015
## Minimum change worth publishing — applies to both discrete impulses and
## continuous decay catch-up, same idea as ManagerDirector's urgency epsilon.
const MOMENTUM_PUBLISH_EPSILON: float = 0.01

## Discrete event impulse weights. Positive = confidence-building for the team
## that generated the event, negative = confidence-damaging. SHOT_ON_TARGET,
## GOAL_CONCEDED and TURNOVER_ERROR are the task-spec values; TACKLE_WON and
## PASS_SEQUENCE are extrapolated at the same relative scale (see
## AGENTS_ERRATA.md).
const MOMENTUM_SHOT_ON_TARGET: float = 0.15
const MOMENTUM_TACKLE_WON: float = 0.10
const MOMENTUM_PASS_SEQUENCE: float = 0.05
const MOMENTUM_GOAL_CONCEDED: float = -0.45
const MOMENTUM_TURNOVER_ERROR: float = -0.20

## Consecutive completed passes, in the opponent's attacking half, needed to
## register a PASS_SEQUENCE momentum tick — see _record_pass_sequence().
const PASS_SEQUENCE_LENGTH: int = 5

## --- Traditional Team Stats --------------------------------------------------
var shots_total: Array[int] = [0, 0]
var shots_on_target: Array[int] = [0, 0]
var passes_attempted: Array[int] = [0, 0]
var passes_completed: Array[int] = [0, 0]
var fouls: Array[int] = [0, 0]
var yellow_cards: Array[int] = [0, 0]
var red_cards: Array[int] = [0, 0]
var corners: Array[int] = [0, 0]
var offsides: Array[int] = [0, 0]

## --- Advanced / Moneyball Team Stats -----------------------------------------
var xg: Array[float] = [0.0, 0.0]
var psxg: Array[float] = [0.0, 0.0]
var goals_prevented: Array[float] = [0.0, 0.0]
var xt_delta: Array[float] = [0.0, 0.0]
var packing_total: Array[int] = [0, 0]
var impect_total: Array[int] = [0, 0]
var progressive_passes: Array[int] = [0, 0]
var progressive_carries: Array[int] = [0, 0]
var vaep_total: Array[float] = [0.0, 0.0]

## Zone & touch counters
var final_third_touches: Array[int] = [0, 0]
var defensive_actions_opp_half: Array[int] = [0, 0]
var opp_passes_def_half: Array[int] = [0, 0]

var _possession_samples: Array[int] = [0, 0]
var _total_possession_samples: int = 0
var _physics_tick_count: int = 0
var _sampling_active: bool = true

var team_momentum: Array[float] = [0.0, 0.0]
## Last value actually broadcast via GameEvents.team_momentum_updated per
## team — decay only re-publishes once it has drifted past
## MOMENTUM_PUBLISH_EPSILON from this, so continuous decay does not spam the
## signal bus at 60Hz. See _maybe_publish_momentum().
var _last_published_momentum: Array[float] = [0.0, 0.0]
## Consecutive completed passes per team since the last incomplete pass —
## see record_pass_attempt() / _record_pass_sequence().
var _consecutive_passes: Array[int] = [0, 0]

## Per-player match events, keyed by `team * 1000 + squad_index`. Populated by
## init_players() at bind time and lazily extended by _on_substitution_made()
## for anyone who comes on later — every entry is allocated once and mutated
## in place for the rest of the match.
var _player_events: Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents] = {}
## Last player on each team (index 0/1) whose pass attempt completed —
## the naive "who gets the assist" proxy on the next goal for that team.
var _last_passer_by_team: Array[HeavyPlayerController] = [null, null]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	GameEvents.ball_struck.connect(_on_ball_struck)
	GameEvents.foul_committed.connect(_on_foul_committed)
	GameEvents.offside_called.connect(_on_offside_called)
	GameEvents.corner_kick_started.connect(_on_corner_kick_started)
	GameEvents.yellow_card_shown.connect(_on_yellow_card_shown)
	GameEvents.red_card_shown.connect(_on_red_card_shown)
	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.substitution_made.connect(_on_substitution_made)
	GameEvents.tackle_won.connect(_on_tackle_won)
	GameEvents.anticipatory_turnover_predicted.connect(_on_turnover_predicted)
	GameEvents.pass_completed.connect(_on_pass_completed)
	GameEvents.carry_completed.connect(_on_carry_completed)
	GameEvents.defensive_action_logged.connect(_on_defensive_action_logged)


func _physics_process(delta: float) -> void:
	if not _sampling_active:
		return

	_update_momentum_decay(delta)

	_physics_tick_count += 1
	if _physics_tick_count % POSSESSION_SAMPLE_INTERVAL != 0:
		return
	if not GameManager.is_in_play() or GameManager.get_meta(&"practice_mode", false):
		return

	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return

	var possessor_index: int = world.possessor_index
	if possessor_index == MatchWorldModel.NO_INDEX:
		return

	var team: int = world.player_teams[possessor_index]
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return

	_possession_samples[team] += 1
	_total_possession_samples += 1

	# Sample final-third territorial presence for Field Tilt
	var p_pos: Vector2 = world.player_positions[possessor_index]
	if _is_in_opponent_final_third(team, p_pos):
		final_third_touches[team] += 1



func _get_attack_sign(team: int) -> float:
	return 1.0 if team == 0 else -1.0


func _get_opp_goal_centre(team: int) -> Vector2:
	var world: MatchWorldModel = MatchWorldModel.instance
	var half_pitch_x: float = 800.0
	if world != null:
		half_pitch_x = world.get_pitch_size().x * 0.5
	var sign_val: float = _get_attack_sign(team)
	return Vector2(sign_val * half_pitch_x, 0.0)


func _get_opp_goal_posts(team: int) -> Array[Vector2]:
	var centre: Vector2 = _get_opp_goal_centre(team)
	var half_mouth: float = 100.0
	return [Vector2(centre.x, centre.y - half_mouth), Vector2(centre.x, centre.y + half_mouth)]


func _is_in_opponent_final_third(team: int, pos: Vector2) -> bool:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false
	var pitch_size: Vector2 = world.get_pitch_size()
	var attack_sign: float = _get_attack_sign(team)
	return (pos.x * attack_sign) > (pitch_size.x / 6.0)


func _is_in_attacking_60_zone(team: int, pos: Vector2) -> bool:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false
	var pitch_size: Vector2 = world.get_pitch_size()
	var attack_sign: float = _get_attack_sign(team)
	return (pos.x * attack_sign) > (-0.1 * pitch_size.x)


func _is_in_defensive_60_zone(team: int, pos: Vector2) -> bool:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false
	var pitch_size: Vector2 = world.get_pitch_size()
	var attack_sign: float = _get_attack_sign(team)
	return (pos.x * attack_sign) < (0.1 * pitch_size.x)


func _is_in_penalty_area_zone(pos: Vector2, defending_team: int) -> bool:
	var goal_centre: Vector2 = _get_opp_goal_centre(1 - defending_team)
	var local: Vector2 = pos - goal_centre
	var inward_dir: float = -1.0 if (defending_team == 1) else 1.0
	var depth: float = local.x * inward_dir
	return depth >= 0.0 and depth <= 200.0 and absf(local.y) <= 190.0


func record_shot(player: HeavyPlayerController, on_target: bool, speed: float = 520.0, is_header: bool = false) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	shots_total[team] += 1
	var events: PlayerRatingCalculator.PlayerMatchEvents = _get_or_create_events(player)

	var world: MatchWorldModel = MatchWorldModel.instance
	var goal_centre: Vector2 = _get_opp_goal_centre(team)
	var posts: Array[Vector2] = _get_opp_goal_posts(team)

	var opp_positions: PackedVector2Array = PackedVector2Array()
	var gk_pos: Vector2 = goal_centre
	var opp_team: int = 1 - team

	if world != null:
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			if world.player_teams[i] == opp_team and world.is_slot_live(i):
				opp_positions.append(world.player_positions[i])
				var opp_node: HeavyPlayerController = world.player_nodes[i]
				if opp_node != null and is_instance_valid(opp_node) and opp_node.is_in_group(&"goalkeepers"):
					gk_pos = world.player_positions[i]

	var base_z: float = UtilityMath.calculate_xg_logit(
		player.global_position, goal_centre, posts[0], posts[1], opp_positions, is_header
	)
	var xg_val: float = 1.0 / (1.0 + exp(-clampf(base_z, -40.0, 40.0)))
	var psxg_val: float = UtilityMath.calculate_psxg(base_z, speed, gk_pos, goal_centre, on_target)

	xg[team] += xg_val
	events.xg += xg_val

	if on_target:
		shots_on_target[team] += 1
		events.shots_on_target += 1
		psxg[team] += psxg_val
		events.psxg += psxg_val
	else:
		events.shots_off_target += 1

	# Attribute xA to previous passer on this team if within active sequence
	var assist_player: HeavyPlayerController = _last_passer_by_team[team]
	if assist_player != null and is_instance_valid(assist_player) and assist_player != player:
		_get_or_create_events(assist_player).xa += xg_val

	var vaep_val: float = UtilityMath.calculate_vaep_value(&"shot", 0.0, 0.0, on_target, false, xg_val, psxg_val)
	events.vaep += vaep_val
	vaep_total[team] += vaep_val

	GameEvents.shot_taken.emit(player, player.global_position, xg_val, psxg_val, on_target)


func record_pass_attempt(player: HeavyPlayerController, completed: bool) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	passes_attempted[team] += 1
	var events: PlayerRatingCalculator.PlayerMatchEvents = _get_or_create_events(player)

	if completed:
		passes_completed[team] += 1
		_last_passer_by_team[team] = player
		events.passes_completed += 1
		_record_pass_sequence(team, player)
	else:
		events.passes_failed += 1
		_consecutive_passes[team] = 0
		var world: MatchWorldModel = MatchWorldModel.instance
		var pitch_size: Vector2 = Vector2(1600.0, 900.0)
		if world != null:
			pitch_size = world.get_pitch_size()
		var attack_sign: float = _get_attack_sign(team)
		var orig_xt: float = UtilityMath.get_xt_value(player.global_position, pitch_size, attack_sign)
		var vaep_val: float = UtilityMath.calculate_vaep_value(&"pass", orig_xt, 0.0, false, false)
		events.vaep += vaep_val
		vaep_total[team] += vaep_val


func record_pass_completed(passer: HeavyPlayerController, receiver: Node, orig_pos: Vector2, dest_pos: Vector2) -> void:
	var team: int = passer.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return

	var world: MatchWorldModel = MatchWorldModel.instance
	var pitch_size: Vector2 = Vector2(1600.0, 900.0)
	var opp_team: int = 1 - team
	var opp_def_line: float = 0.0
	var opp_positions: PackedVector2Array = PackedVector2Array()

	if world != null:
		pitch_size = world.get_pitch_size()
		opp_def_line = world.defensive_line_x[opp_team]
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			if world.player_teams[i] == opp_team and world.is_slot_live(i):
				opp_positions.append(world.player_positions[i])

	var attack_sign: float = _get_attack_sign(team)
	var orig_xt: float = UtilityMath.get_xt_value(orig_pos, pitch_size, attack_sign)
	var dest_xt: float = UtilityMath.get_xt_value(dest_pos, pitch_size, attack_sign)
	var delta_xt: float = dest_xt - orig_xt

	var pack_dict: Dictionary = UtilityMath.calculate_packing(orig_pos, dest_pos, opp_positions, attack_sign, opp_def_line)
	var packed_cnt: int = pack_dict["packing"]
	var impect_cnt: int = pack_dict["impect"]

	var opp_goal_centre: Vector2 = _get_opp_goal_centre(team)
	var in_pen_start: bool = _is_in_penalty_area_zone(orig_pos, opp_team)
	var in_pen_end: bool = _is_in_penalty_area_zone(dest_pos, opp_team)
	var is_prog: bool = UtilityMath.is_progressive_action(orig_pos, dest_pos, opp_goal_centre, in_pen_start, in_pen_end)

	var p_events: PlayerRatingCalculator.PlayerMatchEvents = _get_or_create_events(passer)
	p_events.xt_delta += delta_xt
	p_events.packing_count += packed_cnt
	p_events.impect_count += impect_cnt
	if is_prog:
		p_events.progressive_passes += 1
		progressive_passes[team] += 1

	xt_delta[team] += delta_xt
	packing_total[team] += packed_cnt
	impect_total[team] += impect_cnt

	var vaep_val: float = UtilityMath.calculate_vaep_value(&"pass", orig_xt, dest_xt, true, is_prog)
	p_events.vaep += vaep_val
	vaep_total[team] += vaep_val

	# Zone tracking for PPDA: pass inside passer's defensive 60% counts toward opponent's PPDA numerator
	if _is_in_defensive_60_zone(team, orig_pos):
		opp_passes_def_half[opp_team] += 1

	# Zone tracking for Field Tilt
	if _is_in_opponent_final_third(team, dest_pos):
		final_third_touches[team] += 1

	GameEvents.pass_completed.emit(passer, receiver, orig_pos, dest_pos, packed_cnt, delta_xt)


func record_carry_completed(player: HeavyPlayerController, start_pos: Vector2, end_pos: Vector2) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return

	var world: MatchWorldModel = MatchWorldModel.instance
	var pitch_size: Vector2 = Vector2(1600.0, 900.0)
	if world != null:
		pitch_size = world.get_pitch_size()

	var attack_sign: float = _get_attack_sign(team)
	var orig_xt: float = UtilityMath.get_xt_value(start_pos, pitch_size, attack_sign)
	var dest_xt: float = UtilityMath.get_xt_value(end_pos, pitch_size, attack_sign)
	var delta_xt: float = dest_xt - orig_xt

	var opp_team: int = 1 - team
	var opp_goal_centre: Vector2 = _get_opp_goal_centre(team)
	var in_pen_start: bool = _is_in_penalty_area_zone(start_pos, opp_team)
	var in_pen_end: bool = _is_in_penalty_area_zone(end_pos, opp_team)
	var is_prog: bool = UtilityMath.is_progressive_action(start_pos, end_pos, opp_goal_centre, in_pen_start, in_pen_end)

	var p_events: PlayerRatingCalculator.PlayerMatchEvents = _get_or_create_events(player)
	p_events.xt_delta += delta_xt
	if is_prog:
		p_events.progressive_carries += 1
		progressive_carries[team] += 1

	xt_delta[team] += delta_xt

	var vaep_val: float = UtilityMath.calculate_vaep_value(&"carry", orig_xt, dest_xt, true, is_prog)
	p_events.vaep += vaep_val
	vaep_total[team] += vaep_val

	if _is_in_opponent_final_third(team, end_pos):
		final_third_touches[team] += 1

	GameEvents.carry_completed.emit(player, start_pos, end_pos, is_prog, delta_xt)


func record_defensive_action(player: HeavyPlayerController, action_type: StringName, pos: Vector2) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return

	var p_events: PlayerRatingCalculator.PlayerMatchEvents = _get_or_create_events(player)

	if _is_in_attacking_60_zone(team, pos):
		defensive_actions_opp_half[team] += 1

	match action_type:
		&"tackle":
			p_events.tackles_won += 1
		&"interception":
			p_events.interceptions += 1

	var world: MatchWorldModel = MatchWorldModel.instance
	var pitch_size: Vector2 = Vector2(1600.0, 900.0)
	if world != null:
		pitch_size = world.get_pitch_size()

	var attack_sign: float = _get_attack_sign(team)
	var act_xt: float = UtilityMath.get_xt_value(pos, pitch_size, attack_sign)
	var vaep_val: float = UtilityMath.calculate_vaep_value(action_type, act_xt, act_xt, true, false)
	p_events.vaep += vaep_val
	vaep_total[team] += vaep_val

	GameEvents.defensive_action_logged.emit(player, action_type, pos)


## --- Macro momentum accumulator ----------------------------------------------

func _update_momentum_decay(delta: float) -> void:
	if not GameManager.is_in_play():
		return
	var decay_factor: float = exp(-MOMENTUM_DECAY_LAMBDA * delta)
	for t: int in range(2):
		var decayed: float = team_momentum[t] * decay_factor
		team_momentum[t] = decayed
		_maybe_publish_momentum(t)


func _apply_momentum_impulse(team: int, raw_impulse: float) -> void:
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	var current_m: float = team_momentum[team]
	var effective_impulse: float = raw_impulse * (1.0 - (current_m * current_m))
	team_momentum[team] = clampf(current_m + effective_impulse, -1.0, 1.0)
	_maybe_publish_momentum(team, true)


func _maybe_publish_momentum(team: int, force: bool = false) -> void:
	if force or absf(team_momentum[team] - _last_published_momentum[team]) > MOMENTUM_PUBLISH_EPSILON:
		_last_published_momentum[team] = team_momentum[team]
		GameEvents.team_momentum_updated.emit(team, team_momentum[team])


func _on_tackle_won(winner: Node, _loser: Node) -> void:
	var w := winner as HeavyPlayerController
	if w != null and is_instance_valid(w):
		_apply_momentum_impulse(w.team, MOMENTUM_TACKLE_WON)
		record_defensive_action(w, &"tackle", w.global_position)


func _on_turnover_predicted(intercepting_team: int) -> void:
	_apply_momentum_impulse(1 - intercepting_team, MOMENTUM_TURNOVER_ERROR)


func _on_pass_completed(_passer: Node, _receiver: Node, _orig: Vector2, _dest: Vector2, _packed: int, _xt: float) -> void:
	pass


func _on_carry_completed(_player: Node, _start: Vector2, _end: Vector2, _prog: bool, _xt: float) -> void:
	pass


func _on_defensive_action_logged(_player: Node, _action: StringName, _pos: Vector2) -> void:
	pass


func _record_pass_sequence(team: int, player: HeavyPlayerController) -> void:
	if not _is_in_opponent_half(team, player.global_position):
		_consecutive_passes[team] = 0
		return
	_consecutive_passes[team] += 1
	if _consecutive_passes[team] >= PASS_SEQUENCE_LENGTH:
		_consecutive_passes[team] = 0
		_apply_momentum_impulse(team, MOMENTUM_PASS_SEQUENCE)


func _is_in_opponent_half(team: int, pos: Vector2) -> bool:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false
	var centre_x: float = world.get_pitch_centre_x()
	return pos.x > centre_x if team == 0 else pos.x < centre_x


func record_foul(player: HeavyPlayerController) -> void:
	var team: int = player.team
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	fouls[team] += 1
	_get_or_create_events(player).fouls += 1
	record_defensive_action(player, &"foul", player.global_position)


func record_goal(player: HeavyPlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return
	var events: PlayerRatingCalculator.PlayerMatchEvents = _get_or_create_events(player)
	events.goals += 1
	if events.shots_on_target > 0:
		events.shots_on_target -= 1


func record_assist(player: HeavyPlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return
	_get_or_create_events(player).assists += 1


func record_own_goal(player: HeavyPlayerController) -> void:
	if player == null or not is_instance_valid(player):
		return
	_get_or_create_events(player).own_goals += 1


func get_player_events(player_id: int) -> PlayerRatingCalculator.PlayerMatchEvents:
	if not _player_events.has(player_id):
		_player_events[player_id] = PlayerRatingCalculator.PlayerMatchEvents.new()
	return _player_events[player_id]


func get_all_player_events() -> Dictionary[int, PlayerRatingCalculator.PlayerMatchEvents]:
	return _player_events


func compute_all_ratings() -> Dictionary[int, float]:
	var ratings: Dictionary[int, float] = {}

	var live_keys: Dictionary[int, bool] = {}
	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null:
		for node: HeavyPlayerController in world.player_nodes:
			if node == null or not is_instance_valid(node):
				continue
			live_keys[_player_key(node)] = true

	for key: int in _player_events:
		var team: int = key / 1000
		var squad_index: int = key % 1000
		var player_data: PlayerData = DataLoader.get_player(team, squad_index)
		if player_data == null:
			continue

		var events: PlayerRatingCalculator.PlayerMatchEvents = _player_events[key]
		events.kept_clean_sheet = _resolve_clean_sheet(player_data, team, key, live_keys)

		if player_data.position_role == "GK":
			var opponent_team: int = 1 - team
			var conceded: int = GameManager.score[opponent_team]
			events.goals_prevented = events.psxg - float(conceded)

		var rating: float = PlayerRatingCalculator.calculate(player_data, events)
		ratings[key] = rating
		player_data.last_match_rating = rating
		player_data.accumulate_match_stats(events)

	return ratings


func _resolve_clean_sheet(player_data: PlayerData, team: int, key: int, live_keys: Dictionary[int, bool]) -> bool:
	if player_data.position_role != "GK":
		return false
	if not live_keys.is_empty() and not live_keys.has(key):
		return false
	var opponent_team: int = 1 - team
	return GameManager.score[opponent_team] == 0


func _get_or_create_events(player: HeavyPlayerController) -> PlayerRatingCalculator.PlayerMatchEvents:
	var key: int = _player_key(player)
	if not _player_events.has(key):
		_player_events[key] = PlayerRatingCalculator.PlayerMatchEvents.new()
	return _player_events[key]


func _player_key(player: HeavyPlayerController) -> int:
	return player.team * 1000 + player.squad_index


func init_players() -> void:
	_player_events.clear()
	_last_passer_by_team = [null, null]

	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return
	for node: HeavyPlayerController in world.player_nodes:
		if node == null or not is_instance_valid(node):
			continue
		_get_or_create_events(node)


func record_corner(team_index: int) -> void:
	if team_index != GameManager.TEAM_A and team_index != GameManager.TEAM_B:
		return
	corners[team_index] += 1


func record_offside(team_index: int) -> void:
	if team_index != GameManager.TEAM_A and team_index != GameManager.TEAM_B:
		return
	offsides[team_index] += 1


func is_pass_toward_teammate(player: HeavyPlayerController, aim: Vector2) -> bool:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or player.world_index < 0:
		return false

	var aim_dir: Vector2 = aim.normalized()
	if aim_dir == Vector2.ZERO:
		return false

	for teammate_index: int in world.get_teammates_of(player.world_index):
		var to_teammate: Vector2 = world.player_positions[teammate_index] - player.global_position
		var dist: float = to_teammate.length()
		if dist <= 0.0 or dist > PASS_MAX_RANGE:
			continue
		if aim_dir.dot(to_teammate / dist) >= PASS_CONE_COS:
			return true

	return false


func get_stats(team_index: int) -> Dictionary:
	var attempted: int = passes_attempted[team_index]
	var completion_pct: float = 0.0
	if attempted > 0:
		completion_pct = float(passes_completed[team_index]) / float(attempted) * 100.0

	var possession_pct: float = 50.0
	if _total_possession_samples > 0:
		possession_pct = float(_possession_samples[team_index]) / float(_total_possession_samples) * 100.0

	return {
		"possession_pct": possession_pct,
		"shots": shots_total[team_index],
		"shots_on_target": shots_on_target[team_index],
		"passes_attempted": attempted,
		"pass_completion_pct": completion_pct,
		"fouls": fouls[team_index],
		"yellow_cards": yellow_cards[team_index],
		"red_cards": red_cards[team_index],
		"corners": corners[team_index],
		"offsides": offsides[team_index],
	}


func get_advanced_stats(team_index: int) -> Dictionary:
	var total_ft_touches: int = final_third_touches[0] + final_third_touches[1]
	var field_tilt: float = 50.0
	if total_ft_touches > 0:
		field_tilt = float(final_third_touches[team_index]) / float(total_ft_touches) * 100.0

	var opp_passes_in_def_zone: int = opp_passes_def_half[team_index]
	var def_actions_in_att_zone: int = defensive_actions_opp_half[team_index]
	var ppda_val: float = 0.0
	if def_actions_in_att_zone > 0:
		ppda_val = float(opp_passes_in_def_zone) / float(def_actions_in_att_zone)

	var opp_team: int = 1 - team_index
	var goals_conceded: int = GameManager.score[opp_team]
	var gk_prevented: float = psxg[opp_team] - float(goals_conceded)

	return {
		"xg": xg[team_index],
		"psxg": psxg[team_index],
		"goals_prevented": gk_prevented,
		"xt_delta": xt_delta[team_index],
		"field_tilt_pct": field_tilt,
		"ppda": ppda_val,
		"packing_total": packing_total[team_index],
		"impect_total": impect_total[team_index],
		"progressive_passes": progressive_passes[team_index],
		"progressive_carries": progressive_carries[team_index],
		"vaep_total": vaep_total[team_index],
	}


func stop_possession_sampling() -> void:
	_sampling_active = false


func reset() -> void:
	shots_total = [0, 0]
	shots_on_target = [0, 0]
	passes_attempted = [0, 0]
	passes_completed = [0, 0]
	fouls = [0, 0]
	yellow_cards = [0, 0]
	red_cards = [0, 0]
	corners = [0, 0]
	offsides = [0, 0]
	xg = [0.0, 0.0]
	psxg = [0.0, 0.0]
	goals_prevented = [0.0, 0.0]
	xt_delta = [0.0, 0.0]
	packing_total = [0, 0]
	impect_total = [0, 0]
	progressive_passes = [0, 0]
	progressive_carries = [0, 0]
	vaep_total = [0.0, 0.0]
	final_third_touches = [0, 0]
	defensive_actions_opp_half = [0, 0]
	opp_passes_def_half = [0, 0]
	_possession_samples = [0, 0]
	_total_possession_samples = 0
	_physics_tick_count = 0
	_sampling_active = true
	_player_events.clear()
	_last_passer_by_team = [null, null]
	team_momentum = [0.0, 0.0]
	_last_published_momentum = [0.0, 0.0]
	_consecutive_passes = [0, 0]


func _on_ball_struck(player: Node, speed: float, charge_ratio: float, is_shot: bool) -> void:
	if not is_shot:
		return
	var shooter := player as HeavyPlayerController
	if shooter == null:
		return
	var on_target: bool = charge_ratio > SHOT_ON_TARGET_THRESHOLD
	record_shot(shooter, on_target, speed)
	if on_target:
		_apply_momentum_impulse(shooter.team, MOMENTUM_SHOT_ON_TARGET)


func _on_foul_committed(fouler: Node, _victim: Node, _position: Vector2) -> void:
	var fouling_player := fouler as HeavyPlayerController
	if fouling_player != null:
		record_foul(fouling_player)


func _on_offside_called(_offside_player: Node, defending_team: int, _position: Vector2) -> void:
	record_offside(1 - defending_team)


func _on_corner_kick_started(team: int, _position: Vector2) -> void:
	record_corner(team)


func _on_yellow_card_shown(player: Node, team: int) -> void:
	if team == GameManager.TEAM_A or team == GameManager.TEAM_B:
		yellow_cards[team] += 1
	var carded_player := player as HeavyPlayerController
	if carded_player != null and is_instance_valid(carded_player):
		_get_or_create_events(carded_player).yellow_cards += 1


func _on_red_card_shown(player: Node, team: int, _is_second_yellow: bool) -> void:
	if team == GameManager.TEAM_A or team == GameManager.TEAM_B:
		red_cards[team] += 1
	var carded_player := player as HeavyPlayerController
	if carded_player != null and is_instance_valid(carded_player):
		_get_or_create_events(carded_player).red_cards += 1


func _on_goal_scored(team: int, scorer: Node) -> void:
	if GameManager.shootout_active:
		return

	_apply_momentum_impulse(1 - team, MOMENTUM_GOAL_CONCEDED)

	var scoring_player := scorer as HeavyPlayerController
	if scoring_player == null or not is_instance_valid(scoring_player):
		return

	if scoring_player.team == team:
		record_goal(scoring_player)
		var assist_player: HeavyPlayerController = _last_passer_by_team[team]
		if assist_player != null and is_instance_valid(assist_player) and assist_player != scoring_player:
			record_assist(assist_player)
	else:
		record_own_goal(scoring_player)


func _on_substitution_made(team: int, _player_out_idx: int, player_in_idx: int) -> void:
	if team != GameManager.TEAM_A and team != GameManager.TEAM_B:
		return
	var key: int = team * 1000 + player_in_idx
	if not _player_events.has(key):
		_player_events[key] = PlayerRatingCalculator.PlayerMatchEvents.new()
