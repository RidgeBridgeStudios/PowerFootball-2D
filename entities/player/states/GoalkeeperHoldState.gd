##
## GoalkeeperHoldState
##
## The state entered when a goalkeeper catches and holds the ball with their hands
## inside their own penalty area. Secures the ball at chest height (z = 10.0),
## makes it immune to tackles/steals, and tactically modulates the hold duration
## to slow down the match tempo before calmly distributing via throws or punts.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, MatchWorldModel,
##              GameManager, GameEvents, MatchStatsTracker.
## Exposes: the PlayerState interface plus was_diving_save and was_shot flags.
##

class_name GoalkeeperHoldState
extends PlayerState

## Base duration the goalkeeper holds the ball before distributing (CPU).
const BASE_HOLD_DURATION_MIN: float = 1.8
const BASE_HOLD_DURATION_MAX: float = 2.8

## Maximum allowed hold time for user-controlled keeper before forced distribution (IFAB Law 12).
const MAX_USER_HOLD_TIME: float = 6.0

## Speed multiplier for repositioning while holding the ball (slow walk).
const SLOW_WALK_SPEED_RATIO: float = 0.25

## Lockout applied to goalkeeper after releasing the ball to prevent instant re-catch.
const DISTRIBUTE_LOCKOUT: float = 0.60

## Set by caller (GoalkeeperDiveState or shot handler) before transition.
var was_diving_save: bool = false
var was_shot: bool = false

var _hold_timer: float = 0.0
var _hold_duration: float = 2.2
var _held_ball: Pseudo3DBall = null
var _has_distributed: bool = false


func enter(player: HeavyPlayerController) -> void:
	_hold_timer = 0.0
	_has_distributed = false
	player.is_sprinting = false

	# Resolve live ball from world model or player sensors
	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null and world.ball_node != null and is_instance_valid(world.ball_node):
		_held_ball = world.ball_node
	else:
		_held_ball = player.get_ball_in_foot_range()

	# Secure ball in keeper's hands
	if _held_ball != null and is_instance_valid(_held_ball):
		_held_ball.velocity = Vector2.ZERO
		_held_ball.velocity_z = 0.0
		_held_ball.position_z = 10.0
		_held_ball.set_possessor(player)
		_held_ball.last_touched_by = player

	# Modulate hold duration based on match urgency and score state
	_hold_duration = randf_range(BASE_HOLD_DURATION_MIN, BASE_HOLD_DURATION_MAX)
	if world != null and player.team >= 0 and player.team < world.team_urgency.size():
		var urgency: float = world.team_urgency[player.team]
		if urgency < -0.1:
			# Protecting lead or calming tempo: hold longer to slow down play
			_hold_duration = randf_range(2.6, 3.4)
		elif urgency > 0.35:
			# Chasing game / urgent attack: release quickly on counter
			_hold_duration = randf_range(0.8, 1.3)

	var is_save: bool = was_diving_save or was_shot
	player.show_action_text("SAVE" if is_save else "CATCH")
	was_diving_save = false
	was_shot = false


func exit(player: HeavyPlayerController) -> void:
	if _held_ball != null and is_instance_valid(_held_ball) and _held_ball.possessor == player:
		if not _has_distributed:
			_held_ball.release_possession()
			_held_ball.position_z = 0.0
	_held_ball = null
	_has_distributed = false


func process(player: HeavyPlayerController, _delta: float) -> StringName:
	if GameManager.current_phase != GameManager.MatchPhase.IN_PLAY:
		return IDLE

	if _has_distributed:
		return IDLE

	if player.is_user_controlled:
		if just_wants(player, &"action_kick"):
			_distribute_punt(player)
			return IDLE
		if just_wants(player, &"action_tackle"):
			_distribute_throw(player)
			return IDLE
		if _hold_timer >= MAX_USER_HOLD_TIME:
			_distribute_punt(player)
			return IDLE
	else:
		if _hold_timer >= _hold_duration:
			_distribute_cpu(player)
			return IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	_hold_timer += delta

	# Keep the ball anchored in the goalkeeper's hands
	if _held_ball != null and is_instance_valid(_held_ball):
		_held_ball.velocity = Vector2.ZERO
		_held_ball.velocity_z = 0.0
		_held_ball.position_z = 10.0
		var carry_offset: Vector2 = player.facing_direction * 9.0
		_held_ball.global_position = player.global_position + carry_offset

	# Controlled slow walk inside the penalty area
	var intent: Vector2 = player.movement_intent
	if player.is_user_controlled:
		intent = InputHelper.get_movement_vector()
	player.apply_kinematic_weight(intent * SLOW_WALK_SPEED_RATIO, delta)


func _distribute_cpu(player: HeavyPlayerController) -> void:
	if _held_ball == null or not is_instance_valid(_held_ball):
		_has_distributed = true
		return

	var world: MatchWorldModel = MatchWorldModel.instance
	var target_player: HeavyPlayerController = null
	var best_dist_sq: float = INF

	# Look for an open teammate in the defensive/midfield third with a clean passing lane
	if world != null:
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			var other: HeavyPlayerController = world.player_nodes[i]
			if not is_instance_valid(other) or other == player:
				continue
			if world.player_teams[i] != player.team:
				continue
			var d_sq: float = player.global_position.distance_squared_to(world.player_positions[i])
			if d_sq > 160000.0 or d_sq < 3600.0:  # Between 60px and 400px
				continue
			if world.is_passing_lane_open(player.global_position, world.player_positions[i], player.team):
				if d_sq < best_dist_sq:
					best_dist_sq = d_sq
					target_player = other

	if target_player != null:
		_distribute_to_teammate(player, target_player)
	else:
		_distribute_punt(player)


func _distribute_to_teammate(player: HeavyPlayerController, teammate: HeavyPlayerController) -> void:
	if _held_ball == null or not is_instance_valid(_held_ball):
		_has_distributed = true
		return

	var lead_pos: Vector2 = teammate.global_position + teammate.velocity * 0.25
	var throw_dir: Vector2 = (lead_pos - player.global_position).normalized()
	var throw_speed: float = 300.0
	player.ball_control_lockout = DISTRIBUTE_LOCKOUT
	_held_ball.global_position = player.global_position + throw_dir * 18.0
	_held_ball.position_z = 0.0
	_held_ball.apply_kick(throw_dir * throw_speed, 15.0, player)
	player.show_action_text("THROW")
	GameEvents.ball_struck.emit(player, throw_speed, 0.45, false)
	MatchStatsTracker.record_pass_attempt(player, true)
	_has_distributed = true
	_held_ball = null


func _distribute_throw(player: HeavyPlayerController) -> void:
	if _held_ball == null or not is_instance_valid(_held_ball):
		_has_distributed = true
		return

	var throw_dir: Vector2 = player.facing_direction
	var throw_speed: float = 320.0
	player.ball_control_lockout = DISTRIBUTE_LOCKOUT
	_held_ball.global_position = player.global_position + throw_dir * 18.0
	_held_ball.position_z = 0.0
	_held_ball.apply_kick(throw_dir * throw_speed, 10.0, player)
	player.show_action_text("THROW")
	GameEvents.ball_struck.emit(player, throw_speed, 0.45, false)
	MatchStatsTracker.record_pass_attempt(player, true)
	_has_distributed = true
	_held_ball = null


func _distribute_punt(player: HeavyPlayerController) -> void:
	if _held_ball == null or not is_instance_valid(_held_ball):
		_has_distributed = true
		return

	var attack_sign: float = 1.0 if player.team == GameManager.TEAM_A else -1.0
	if player.brain != null:
		attack_sign = player.brain._get_attack_sign()

	var spread: float = randf_range(-0.20, 0.20)
	var punt_dir: Vector2 = Vector2(attack_sign, spread).normalized()
	if player.is_user_controlled and InputHelper.get_movement_vector().length() > 0.1:
		punt_dir = InputHelper.get_movement_vector().normalized()

	var punt_speed: float = 520.0
	player.ball_control_lockout = DISTRIBUTE_LOCKOUT
	_held_ball.global_position = player.global_position + punt_dir * 18.0
	_held_ball.position_z = 0.0
	_held_ball.apply_kick(punt_dir * punt_speed, 150.0, player)
	player.show_action_text("PUNT")
	GameEvents.ball_struck.emit(player, punt_speed, 0.85, false)
	MatchStatsTracker.record_pass_attempt(player, false)
	_has_distributed = true
	_held_ball = null
