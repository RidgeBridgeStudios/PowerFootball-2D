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


## Nearest attacking player (excluding the striker) to the ball's projected
## landing spot. Returns null when no such player is registered.
func _find_intended_recipient(striker: HeavyPlayerController, attacking_team: int) -> HeavyPlayerController:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return null

	var projected: Vector2 = world.ball_position + world.ball_velocity * OFFSIDE_LOOKAHEAD_SECONDS

	var best: HeavyPlayerController = null
	var best_dist: float = INF
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var node: HeavyPlayerController = world.player_nodes[i]
		if node == null or not is_instance_valid(node):
			continue
		if world.player_teams[i] != attacking_team:
			continue
		if node == striker:
			continue
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

	# Same sign convention as PitchBoundary.get_goal_centre(): team 0 defends
	# the negative-X goal, team 1 the positive-X goal.
	var goal_direction: float = -1.0 if defending_team == 0 else 1.0

	var deepest_score: float = -INF
	var second_deepest_score: float = -INF
	var second_deepest_x: float = _boundary.get_goal_centre(defending_team).x

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
		return _boundary.get_goal_centre(defending_team).x

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

	# Attacking team 0 advances toward +X (team 1's goal); team 1 toward -X.
	var attack_direction: float = 1.0 if attacking_team == 0 else -1.0
	var centre_x: float = _boundary.get_centre_spot().x
	var player_x: float = player.global_position.x

	var past_halfway: bool = (player_x - centre_x) * attack_direction > 0.0
	var ahead_of_ball: bool = (player_x - world.ball_position.x) * attack_direction > 0.0
	var ahead_of_offside_line: bool = (player_x - offside_line_x) * attack_direction > 0.0

	return past_halfway and ahead_of_ball and ahead_of_offside_line
