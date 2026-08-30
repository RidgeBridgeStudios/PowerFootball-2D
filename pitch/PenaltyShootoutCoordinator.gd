##
## PenaltyShootoutCoordinator
##
## Owns the penalty shootout that decides a match still level after full time.
## It alternates penalties between the two teams, reusing SetPieceCoordinator's
## existing penalty setup (spot placement, taker assignment, defensive
## positioning, confirmation, PenaltyKickState itself) for every single kick
## rather than reimplementing any of it — this script only tracks the
## shootout's own score, decides who kicks next, positions the defending
## goalkeeper on the line, and works out whether each kick was scored or
## missed.
##
## A kick is "resolved" by racing three signals: GameEvents.goal_scored
## (scored), GameEvents.ball_out_of_bounds (missed — wide, or saved behind),
## or a timeout (missed — saved and settled without leaving the pitch).
## Whichever happens first wins; _awaiting_resolution is already false by the
## time the other two arrive, so they are ignored.
##
## Depends on: GameManager, GameEvents (autoloads), SetPieceCoordinator,
##             PitchBoundary, Pseudo3DBall, HeavyPlayerController, PlayerState,
##             PitchScene (for the shared goalkeeper line-offset constant).
## Exposes: bind(set_piece_coordinator, ball, boundary),
##          start(team_a_players, team_b_players), shootout_score, kicks_taken
##

class_name PenaltyShootoutCoordinator
extends Node

## Kicks per team the standard rule guarantees before a scoreline can already
## be mathematically certain — see _check_early_termination().
const MAX_REGULAR_KICKS: int = 5
## Seconds to wait after a kick is struck before giving up on seeing a goal
## and calling it a miss (a save that settles without crossing any boundary).
const RESOLUTION_TIMEOUT: float = 3.5

@onready var _resolution_timer: Timer = $ResolutionTimer

var _set_piece_coordinator: SetPieceCoordinator
var _ball: Pseudo3DBall
var _boundary: PitchBoundary

## team -> Array[HeavyPlayerController], handed in by start() rather than
## re-derived from the scene tree on every kick.
var _rosters: Dictionary = {}
var _taker_queue_indices: Array[int] = [0, 0]

## [team_a, team_b] — deliberately separate from GameManager.score, which the
## shootout must never write to.
var shootout_score: Array[int] = [0, 0]
## Kicks taken so far per team. kicks_taken[team] doubles as the dot index for
## the next GameEvents.shootout_kick_result emitted for that team.
var kicks_taken: Array[int] = [0, 0]

var _active: bool = false
var _next_team: int = GameManager.TEAM_A
var _current_attacking_team: int = -1
var _kick_in_progress: bool = false
var _awaiting_resolution: bool = false


func _ready() -> void:
	_resolution_timer.one_shot = true
	_resolution_timer.timeout.connect(_on_resolution_timeout)


func bind(set_piece_coordinator: SetPieceCoordinator, ball: Pseudo3DBall, boundary: PitchBoundary) -> void:
	_set_piece_coordinator = set_piece_coordinator
	_ball = ball
	_boundary = boundary


## Called once by PitchScene when full time ends level. Team rosters are
## handed in (rather than walked from the scene tree here) the same way
## SetPieceCoordinator.bind() receives its player container instead of
## re-scanning for it.
func start(team_a_players: Array[HeavyPlayerController], team_b_players: Array[HeavyPlayerController]) -> void:
	if _set_piece_coordinator == null or _ball == null or _boundary == null:
		push_error("PenaltyShootoutCoordinator.start() called before bind().")
		return

	_rosters = {
		GameManager.TEAM_A: team_a_players,
		GameManager.TEAM_B: team_b_players,
	}
	shootout_score = [0, 0]
	kicks_taken = [0, 0]
	_taker_queue_indices = [0, 0]
	_next_team = GameManager.TEAM_A
	_active = true

	if not GameEvents.goal_scored.is_connected(_on_goal_scored):
		GameEvents.goal_scored.connect(_on_goal_scored)
	if not GameEvents.ball_out_of_bounds.is_connected(_on_ball_out_of_bounds):
		GameEvents.ball_out_of_bounds.connect(_on_ball_out_of_bounds)
	if not GameEvents.set_piece_taken.is_connected(_on_set_piece_taken):
		GameEvents.set_piece_taken.connect(_on_set_piece_taken)

	GameManager.start_shootout()
	_advance_to_next_kick()


func _advance_to_next_kick() -> void:
	if not _active:
		return

	var attacking_team: int = _next_team
	var defending_team: int = 1 - attacking_team
	_current_attacking_team = attacking_team
	_kick_in_progress = true
	_awaiting_resolution = false
	_resolution_timer.stop()

	var shooter: HeavyPlayerController = _get_next_shooter(attacking_team)
	if shooter != null:
		_set_piece_coordinator.start_penalty_with_taker(attacking_team, defending_team, shooter)
	else:
		_set_piece_coordinator.start_penalty_for_practice(attacking_team, defending_team)
	_position_goalkeeper(defending_team)


func _get_next_shooter(team: int) -> HeavyPlayerController:
	var roster: Array = _rosters.get(team, [])
	if roster.is_empty():
		return null
	var idx: int = _taker_queue_indices[team] % roster.size()
	_taker_queue_indices[team] += 1
	var shooter: HeavyPlayerController = roster[idx] as HeavyPlayerController
	if shooter == null or not is_instance_valid(shooter):
		for node: Variant in roster:
			var p := node as HeavyPlayerController
			if p != null and is_instance_valid(p):
				return p
	return shooter


## Places the defending goalkeeper on their line, offset inward the same way
## Practice Arena does (see PitchScene.PRACTICE_KEEPER_LINE_OFFSET), and
## re-affirms SET_PIECE_FREEZE. _set_piece_coordinator.start_penalty_for_practice()
## already froze every player in place a moment ago, but "in place" may not be
## the goal line if the previous kick's dive or save left the keeper elsewhere.
func _position_goalkeeper(defending_team: int) -> void:
	var keeper: HeavyPlayerController = _find_goalkeeper(defending_team)
	if keeper == null:
		return

	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var direction: float = -1.0 if defending_team == GameManager.TEAM_A else 1.0
	var spot: Vector2 = goal_centre - Vector2(direction * PitchScene.PRACTICE_KEEPER_LINE_OFFSET, 0.0)

	keeper.global_position = spot
	keeper.velocity = Vector2.ZERO
	keeper.movement_intent = Vector2.ZERO
	keeper.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)


func _find_goalkeeper(team: int) -> HeavyPlayerController:
	var roster: Array = _rosters.get(team, [])
	for node: Variant in roster:
		var p := node as HeavyPlayerController
		if p == null or not is_instance_valid(p):
			continue
		if p.brain != null and p.brain.is_goalkeeper:
			return p
	return null


func _on_set_piece_taken(_taker: Node) -> void:
	if not _active or not _kick_in_progress:
		return
	_kick_in_progress = false
	_awaiting_resolution = true
	_resolution_timer.start(RESOLUTION_TIMEOUT)


func _on_goal_scored(team: int) -> void:
	if not _active or not _awaiting_resolution:
		return
	if team != _current_attacking_team:
		return
	_resolution_timer.stop()
	_resolve_kick(true)


func _on_ball_out_of_bounds(_side: String) -> void:
	if not _active or not _awaiting_resolution:
		return
	_resolution_timer.stop()
	_resolve_kick(false)


func _on_resolution_timeout() -> void:
	if not _active or not _awaiting_resolution:
		return
	_resolve_kick(false)


func _resolve_kick(scored: bool) -> void:
	_awaiting_resolution = false

	var team: int = _current_attacking_team
	if scored:
		shootout_score[team] += 1
	var kick_index: int = kicks_taken[team]
	kicks_taken[team] += 1
	GameEvents.shootout_kick_result.emit(team, kick_index, scored)

	if _check_early_termination():
		return

	_next_team = 1 - team
	_advance_to_next_kick()


## True (and the shootout has ended) once one team cannot be caught
## even if the other scores every remaining regulation kick (IFAB Law 10.3) —
## or, past regulation, the instant a sudden-death round finishes with the two
## sides no longer level (evaluated after pairs of kicks where n_a == n_b).
func _check_early_termination() -> bool:
	var team_a: int = GameManager.TEAM_A
	var team_b: int = GameManager.TEAM_B
	var n_a: int = kicks_taken[team_a]
	var n_b: int = kicks_taken[team_b]
	var score_a: int = shootout_score[team_a]
	var score_b: int = shootout_score[team_b]

	# Phase 1: Regular 5 kicks (asymmetric remaining kicks evaluation)
	if n_a <= MAX_REGULAR_KICKS and n_b <= MAX_REGULAR_KICKS:
		var rem_a: int = MAX_REGULAR_KICKS - n_a
		var rem_b: int = MAX_REGULAR_KICKS - n_b

		if score_a + rem_a < score_b:
			_end_shootout(team_b)
			return true
		if score_b + rem_b < score_a:
			_end_shootout(team_a)
			return true

		# Both reached 5 kicks and score is decisive
		if n_a == MAX_REGULAR_KICKS and n_b == MAX_REGULAR_KICKS:
			if score_a != score_b:
				_end_shootout(team_a if score_a > score_b else team_b)
				return true

	# Phase 2: Sudden Death (must resolve strictly in complete pairs n_a == n_b)
	if n_a > MAX_REGULAR_KICKS and n_b > MAX_REGULAR_KICKS and n_a == n_b:
		if score_a != score_b:
			_end_shootout(team_a if score_a > score_b else team_b)
			return true

	return false


func _end_shootout(winner: int) -> void:
	_active = false
	_resolution_timer.stop()

	if GameEvents.goal_scored.is_connected(_on_goal_scored):
		GameEvents.goal_scored.disconnect(_on_goal_scored)
	if GameEvents.ball_out_of_bounds.is_connected(_on_ball_out_of_bounds):
		GameEvents.ball_out_of_bounds.disconnect(_on_ball_out_of_bounds)
	if GameEvents.set_piece_taken.is_connected(_on_set_piece_taken):
		GameEvents.set_piece_taken.disconnect(_on_set_piece_taken)

	GameManager.end_shootout(winner)
