##
## GameManager (Autoload singleton)
##
## Owns match state: the phase machine, the score, and the clock. It is the only
## thing that decides when a match starts, pauses at a goal, or ends — everyone
## else finds out through GameEvents.
##
## Depends on: GameEvents (autoload, declared before this one in project.godot).
## Exposes:
##   - start_match(), register_goal(team), set_phase(phase), restart_play()
##   - start_set_piece(phase, team, position), start_free_kick(), start_penalty()
##   - current_phase, score, match_time, match_duration
##   - set_piece_team, set_piece_position, free_kick_is_direct, is_set_piece_active()
##   - get_clock_string(), get_score_string()
##

extends Node

enum MatchPhase {
	PREGAME, KICKOFF, IN_PLAY, GOAL_SCORED, HALF_TIME, FULL_TIME,
	GOAL_KICK, CORNER_KICK, THROW_IN, FREE_KICK, PENALTY_KICK,
}

## The five dead-ball phases SetPieceCoordinator drives. KICKOFF is deliberately
## excluded — it still runs through the older, simpler reset_for_kickoff() path
## (see PitchScene.reset_for_kickoff for the TODO on unifying the two).
const SET_PIECE_PHASES: Array[MatchPhase] = [
	MatchPhase.GOAL_KICK, MatchPhase.CORNER_KICK, MatchPhase.THROW_IN,
	MatchPhase.FREE_KICK, MatchPhase.PENALTY_KICK,
]

const TEAM_A: int = 0
const TEAM_B: int = 1

## Seconds the goal celebration holds before play restarts.
const GOAL_CELEBRATION_TIME: float = 2.5

var current_phase: MatchPhase = MatchPhase.PREGAME
## [team_a, team_b]
var score: Array[int] = [0, 0]
## Seconds elapsed in the match.
var match_time: float = 0.0
## Full-time whistle, in seconds. 300.0 = a 5 minute match.
var match_duration: float = 300.0
## The team that scored most recently — the pitch uses it to set up the restart.
var last_scoring_team: int = -1
## Guards GameEvents.half_time_reached so it only fires once per match.
var _half_time_fired: bool = false

## --- Set pieces --------------------------------------------------------------

## Which team is taking the current set piece. -1 = none.
var set_piece_team: int = -1
## World position the ball should be placed for the current set piece.
var set_piece_position: Vector2 = Vector2.ZERO
## Whether the current free kick is direct (can score directly) or indirect.
var free_kick_is_direct: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if current_phase != MatchPhase.IN_PLAY:
		return
	if get_meta(&"practice_mode", false):
		return  # Practice Arena: FSMs run, but the clock never ticks and half/full time never fire.

	match_time += delta
	if not _half_time_fired and match_time >= match_duration * 0.5:
		_half_time_fired = true
		GameEvents.half_time_reached.emit()
	if match_time >= match_duration:
		match_time = match_duration
		_end_match()


func start_match() -> void:
	match_time = 0.0
	score = [0, 0]
	last_scoring_team = -1
	_half_time_fired = false
	set_phase(MatchPhase.KICKOFF)
	GameEvents.kickoff_started.emit()


func register_goal(team: int) -> void:
	if current_phase != MatchPhase.IN_PLAY:
		return

	score[team] += 1
	last_scoring_team = team
	set_phase(MatchPhase.GOAL_SCORED)
	GameEvents.goal_scored.emit(team)


## Puts the ball back in play after a goal, a restart or half time. The pitch
## calls this once it has repositioned everyone.
func restart_play() -> void:
	set_phase(MatchPhase.IN_PLAY)


func kickoff() -> void:
	set_phase(MatchPhase.KICKOFF)
	GameEvents.kickoff_started.emit()


func set_phase(phase: MatchPhase) -> void:
	if current_phase == phase:
		return
	current_phase = phase
	GameEvents.match_phase_changed.emit(phase)


func is_in_play() -> bool:
	return current_phase == MatchPhase.IN_PLAY


## Stores where and for whom the dead ball is being taken, switches phase, and
## announces it on GameEvents. SetPieceCoordinator calls this (directly, or via
## the start_free_kick/start_penalty wrappers below) once it has worked out the
## restart type and placement; it does not place the ball or move players
## itself — that stays the coordinator's job.
func start_set_piece(phase: MatchPhase, team: int, position: Vector2) -> void:
	set_piece_team = team
	set_piece_position = position
	set_phase(phase)

	match phase:
		MatchPhase.GOAL_KICK:
			GameEvents.goal_kick_started.emit(team, position)
		MatchPhase.CORNER_KICK:
			GameEvents.corner_kick_started.emit(team, position)
		MatchPhase.THROW_IN:
			GameEvents.throw_in_started.emit(team, position)
		MatchPhase.FREE_KICK:
			GameEvents.free_kick_started.emit(team, position, free_kick_is_direct)
		MatchPhase.PENALTY_KICK:
			GameEvents.penalty_started.emit(team, position)


func start_free_kick(team: int, position: Vector2, direct: bool) -> void:
	free_kick_is_direct = direct
	start_set_piece(MatchPhase.FREE_KICK, team, position)


## NOTE: deviates from the brief's `start_penalty(team)` — GameManager has no
## knowledge of pitch geometry (deliberately: it owns match state, not the
## scene), so it cannot derive the spot itself. SetPieceCoordinator computes
## the spot from PitchBoundary.get_goal_centre() and passes it through here,
## the same way it already does for goal kicks and corners.
func start_penalty(team: int, position: Vector2) -> void:
	start_set_piece(MatchPhase.PENALTY_KICK, team, position)


func is_set_piece_active() -> bool:
	return SET_PIECE_PHASES.has(current_phase)


## "MM:SS", counting up from 0:00.
func get_clock_string() -> String:
	var total: int = int(match_time)
	return "%d:%02d" % [total / 60, total % 60]


func get_score_string() -> String:
	return "%d - %d" % [score[TEAM_A], score[TEAM_B]]


func get_leading_team() -> int:
	if score[TEAM_A] > score[TEAM_B]:
		return TEAM_A
	if score[TEAM_B] > score[TEAM_A]:
		return TEAM_B
	return -1


func _end_match() -> void:
	set_phase(MatchPhase.FULL_TIME)
	GameEvents.match_ended.emit(get_leading_team())

	# TODO: half time. GameEvents.half_time_reached now fires at the midpoint
	# (see _process), but MatchPhase.HALF_TIME itself is still unused — nothing
	# pauses play or swaps ends yet.
