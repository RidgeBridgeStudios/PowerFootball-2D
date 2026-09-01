##
## OffsideDetector
##
## Listens on GameEvents.ball_struck. At the moment a kick/shot is released,
## snapshots MatchWorldModel and determines whether the intended recipient is
## in an offside position. If so, emits GameEvents.offside_called and hands
## the restart to GameManager / SetPieceCoordinator.
##
## Offside is checked exactly once per ball_struck event, only while
## GameManager.current_phase == MatchPhase.IN_PLAY — never on a per-frame tick
## and never during a set piece (throw-ins, goal kicks, corners are exempt by
## construction, since none of them fire ball_struck during IN_PLAY).
##
## Depends on: GameEvents, GameManager, MatchWorldModel, PitchBoundary,
##             HeavyPlayerController, SetPieceCoordinator.
## Exposes: bind(boundary, coordinator)
##

class_name OffsideDetector
extends Node

## How far ahead of the strike the ball's projected landing spot is read, when
## guessing who the intended recipient is.
const OFFSIDE_LOOKAHEAD_SECONDS: float = 0.6

var _boundary: PitchBoundary = null
var _coordinator: SetPieceCoordinator = null


func bind(boundary: PitchBoundary, coordinator: SetPieceCoordinator) -> void:
	_boundary = boundary
	_coordinator = coordinator
	if not GameEvents.ball_struck.is_connected(_on_ball_struck):
		GameEvents.ball_struck.connect(_on_ball_struck)


func _on_ball_struck(striker: Node, _speed: float, _charge_ratio: float, _is_shot: bool = false) -> void:
	if GameManager.current_phase != GameManager.MatchPhase.IN_PLAY:
		return
	if _boundary == null or _coordinator == null:
		return
	# IFAB Law 11: Shots on goal are directed at goal, not passes to teammates.
	if _is_shot:
		return

	var striker_player := striker as HeavyPlayerController
	if striker_player == null:
		return

	var attacking_team: int = striker_player.team
	var defending_team: int = 1 - attacking_team

	var recipient: HeavyPlayerController = _find_intended_recipient(striker_player, attacking_team)
	if recipient == null:
		return

	var offside_line_x: float = _compute_offside_line(defending_team)

	if _is_offside(recipient, offside_line_x, attacking_team):
		var offside_pos: Vector2 = recipient.global_position
		GameEvents.offside_called.emit(recipient, defending_team, offside_pos)
		GameManager.start_free_kick(defending_team, offside_pos, false)
		_coordinator.handle_indirect_offside(defending_team, offside_pos)


## Nearest attacking player (excluding the striker) in the passing lane / trajectory
## cone of the ball's projected landing spot. Returns null when no valid target exists.
func _find_intended_recipient(striker: HeavyPlayerController, attacking_team: int) -> HeavyPlayerController:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return null

	var ball_vel: Vector2 = world.ball_velocity
	if ball_vel.length_squared() < 2500.0:  # < 50 px/s
		return null

	var attack_direction: float = 1.0 if attacking_team == 0 else -1.0
	# Backward passes cannot result in an offside receiver ahead of the ball.
	if ball_vel.x * attack_direction <= 0.0:
		return null

	var pass_dir: Vector2 = ball_vel.normalized()
	var projected: Vector2 = world.ball_position + ball_vel * OFFSIDE_LOOKAHEAD_SECONDS

	var best: HeavyPlayerController = null
	var best_dist: float = 180.0  # Max distance to intended landing zone
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var node: HeavyPlayerController = world.player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if world.player_teams[i] != attacking_team:
			continue
		if node == striker:
			continue

		var to_candidate: Vector2 = world.player_positions[i] - world.ball_position
		if to_candidate.length_squared() < 1.0:
			continue
		var forward_dot: float = pass_dir.dot(to_candidate.normalized())
		if forward_dot < 0.5:
			continue  # Not in the direction of the pass

		var dist: float = world.player_positions[i].distance_to(projected)
		if dist < best_dist:
			best_dist = dist
			best = node

	return best


## X position of the second-to-last defender (the offside line). Falls back to
## the goal line itself when fewer than 2 defenders are registered.
func _compute_offside_line(defending_team: int) -> float:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or _boundary == null:
		return 0.0

	# Derives goal direction from the defending team's goal position, supporting half-time end swapping.
	var goal_x: float = _boundary.get_goal_centre(defending_team).x
	var goal_direction: float = -1.0 if goal_x < _boundary.get_centre_spot().x else 1.0

	var deepest_score: float = -INF
	var second_deepest_score: float = -INF
	var second_deepest_x: float = goal_x

	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var node: HeavyPlayerController = world.player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if world.player_teams[i] != defending_team:
			continue

		var px: float = world.player_positions[i].x
		var score: float = px * goal_direction

		if score > deepest_score:
			second_deepest_score = deepest_score
			if second_deepest_score > -INF:
				second_deepest_x = world.player_positions[i].x
			deepest_score = score
		elif score > second_deepest_score:
			second_deepest_score = score
			second_deepest_x = px

	if second_deepest_score == -INF:
		return goal_x

	return second_deepest_x


## True only when the recipient is past the halfway line, ahead of the ball,
## and ahead of the offside line — all three, in the attacking team's
## direction of travel.
func _is_offside(player: HeavyPlayerController, offside_line_x: float, attacking_team: int) -> bool:
	if _boundary == null:
		return false
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false

	# Attacking direction toward the opponent's goal.
	var opp_goal_x: float = _boundary.get_goal_centre(1 - attacking_team).x
	var centre_x: float = _boundary.get_centre_spot().x
	var attack_direction: float = 1.0 if opp_goal_x > centre_x else -1.0
	var player_x: float = player.global_position.x

	var past_halfway: bool = (player_x - centre_x) * attack_direction > 0.0
	var ahead_of_ball: bool = (player_x - world.ball_position.x) * attack_direction > 0.0
	var ahead_of_offside_line: bool = (player_x - offside_line_x) * attack_direction > 0.0

	return past_halfway and ahead_of_ball and ahead_of_offside_line
