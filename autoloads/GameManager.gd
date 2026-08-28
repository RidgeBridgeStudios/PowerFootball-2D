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
##   - current_phase, score, match_time, match_duration
##   - get_clock_string(), get_score_string()
##

extends Node

enum MatchPhase { PREGAME, KICKOFF, IN_PLAY, GOAL_SCORED, HALF_TIME, FULL_TIME }

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if current_phase != MatchPhase.IN_PLAY:
		return

	match_time += delta
	if match_time >= match_duration:
		match_time = match_duration
		_end_match()


func start_match() -> void:
	match_time = 0.0
	score = [0, 0]
	last_scoring_team = -1
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

	# TODO: half time. The phase exists in the enum but nothing drives it yet —
	# split match_duration in two, swap ends, and emit HALF_TIME at the midpoint.
