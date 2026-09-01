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
##   - get_clock_string(), get_score_string(), get_match_tick()
##   - MatchStage enum, STAGE_1/2/3_FRACTION — macro pacing stage boundaries,
##     broadcast via GameEvents.match_stage_changed and cached on
##     MatchWorldModel.current_match_stage
##

extends Node

enum MatchPhase {
	PREGAME, FIRST_HALF, KICKOFF, IN_PLAY, GOAL_SCORED, HALF_TIME,
	SECOND_HALF, FULL_TIME, EXTRA_TIME,
	GOAL_KICK, CORNER_KICK, THROW_IN, FREE_KICK, PENALTY_KICK,
	PENALTY_SHOOTOUT,
}

## The five non-kickoff dead-ball phases SetPieceCoordinator drives via
## handle_out_of_bounds / handle_foul. KICKOFF has its own ceremony coordinated
## via SetPieceCoordinator.start_kickoff() and PitchScene._start_kickoff_flow().
const SET_PIECE_PHASES: Array[MatchPhase] = [
	MatchPhase.GOAL_KICK, MatchPhase.CORNER_KICK, MatchPhase.THROW_IN,
	MatchPhase.FREE_KICK, MatchPhase.PENALTY_KICK,
]

const TEAM_A: int = 0
const TEAM_B: int = 1

## Seconds the goal celebration holds before play restarts.
const GOAL_CELEBRATION_TIME: float = 2.5

## Simulated 90-minute match duration (5400s) split into two 45-minute halves (2700s).
const SIMULATED_HALF_DURATION: float = 45.0 * 60.0   # 2700.0s
const SIMULATED_MATCH_DURATION: float = 90.0 * 60.0  # 5400.0s
const BASE_HALF_DURATION_REAL_SEC: float = 150.0

## Macro temporal pacing stages (POWERFOOTBALL_MASTER_VISION.md Part V /
## docs architecture plan "Temporal Match Stages"). Boundaries are expressed
## as fractions of SIMULATED_MATCH_DURATION (15/60/75 out of 90 minutes).
enum MatchStage { SIZING_UP = 0, EQUILIBRIUM = 1, TRANSITIONS = 2, GAME_CRUNCH = 3 }
const STAGE_1_FRACTION: float = 15.0 / 90.0
const STAGE_2_FRACTION: float = 60.0 / 90.0
const STAGE_3_FRACTION: float = 75.0 / 90.0

var current_phase: MatchPhase = MatchPhase.PREGAME
## Last MatchStage broadcast via GameEvents.match_stage_changed — tracked here
## (not read back from MatchWorldModel's cache) so this stays the single
## source of truth for match-lifecycle transitions per CORE_INVARIANTS.md.
var _last_match_stage: MatchStage = MatchStage.SIZING_UP
## [team_a, team_b]
var score: Array[int] = [0, 0]
## Seconds elapsed in the match.
var match_time: float = 0.0
## Real seconds per 45-minute half (default: 150.0s for a 5-minute full match).
var half_duration_real_sec: float = 150.0
## Full-time whistle in real seconds (synchronized to 2.0 * half_duration_real_sec).
var match_duration: float = 300.0
## Simulated match clock in in-game seconds (0.0 to 5400.0).
var simulated_match_time: float = 0.0
## Active half of the match (1 = First Half, 2 = Second Half, 3+ = Extra Time).
var current_half: int = 1
## Team that kicked off the match in the first half.
var match_opening_kickoff_team: int = TEAM_A
## The team that scored most recently — the pitch uses it to set up the restart.
var last_scoring_team: int = -1
## Guards GameEvents.half_time_reached so it only fires once per match.
var _half_time_fired: bool = false
## Monotonically incrementing counter stepped every frame. Used by PlayerBrain
## to vary per-player noise seeds between decision ticks.
var _match_tick: int = 0

## Stoppage time calculation & announcements
var _accumulated_stoppage_sec: float = 60.0
var stoppage_minutes_half_1: int = 0
var stoppage_minutes_half_2: int = 0
var _stoppage_announced: bool = false

## --- Set pieces --------------------------------------------------------------

## Which team is taking the current set piece. -1 = none.
var set_piece_team: int = -1
## World position the ball should be placed for the current set piece.
var set_piece_position: Vector2 = Vector2.ZERO
## Whether the current free kick is direct (can score directly) or indirect.
var free_kick_is_direct: bool = true

## --- Penalty shootout --------------------------------------------------------

## True for the entire shootout (including the live-ball moments inside each
## individual kick, where current_phase cycles through PENALTY_KICK/IN_PLAY
## just like any other penalty) — see start_shootout()/end_shootout(). Distinct
## from current_phase == PENALTY_SHOOTOUT, which only holds between kicks.
var shootout_active: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameEvents.powerful_shot_landed.connect(_on_powerful_shot)
	GameEvents.goal_scored.connect(_on_goal_stoppage)
	GameEvents.substitution_made.connect(_on_sub_stoppage)
	GameEvents.yellow_card_shown.connect(_on_card_stoppage)
	GameEvents.red_card_shown.connect(_on_card_stoppage)
	GameEvents.foul_committed.connect(_on_foul_stoppage)


func _on_goal_stoppage(_team: int, _scorer: Node = null) -> void:
	_accumulated_stoppage_sec += 45.0


func _on_sub_stoppage(_team: int, _out_idx: int, _in_idx: int) -> void:
	_accumulated_stoppage_sec += 30.0


func _on_card_stoppage(_player: Node, _team: int, _extra: Variant = null) -> void:
	_accumulated_stoppage_sec += 25.0


func _on_foul_stoppage(_fouler: Node, _victim: Node, _pos: Vector2) -> void:
	_accumulated_stoppage_sec += 10.0


## Hit-stop: briefly slow the clock on a high-charge shot so the strike reads.
func _on_powerful_shot(_shooter: HeavyPlayerController, _speed: float, _ratio: float) -> void:
	Engine.time_scale = 0.15
	await get_tree().create_timer(0.055 * Engine.time_scale).timeout
	Engine.time_scale = 1.0


## Calculates the time dilation factor mapping real elapsed seconds to in-game seconds.
func get_time_scale() -> float:
	return SIMULATED_HALF_DURATION / maxf(half_duration_real_sec, 1.0)


## Normalized match progress in range [0.0, 1.0] across the 90 simulated minutes.
func get_match_time_ratio() -> float:
	return clampf(simulated_match_time / SIMULATED_MATCH_DURATION, 0.0, 1.0)


func get_announced_stoppage_minutes() -> int:
	return stoppage_minutes_half_1 if current_half == 1 else stoppage_minutes_half_2


func is_in_stoppage_time() -> bool:
	return (current_half == 1 and simulated_match_time >= SIMULATED_HALF_DURATION) or (current_half >= 2 and simulated_match_time >= SIMULATED_MATCH_DURATION)


func set_half_duration(real_sec: float) -> void:
	half_duration_real_sec = maxf(real_sec, 10.0)
	match_duration = half_duration_real_sec * 2.0


func _process(delta: float) -> void:
	_match_tick += 1

	if current_phase != MatchPhase.IN_PLAY:
		return
	if get_meta(&"practice_mode", false):
		return  # Practice Arena: FSMs run, but the clock never ticks and half/full time never fire.
	if shootout_active:
		return  # Penalty shootout: FSMs run for each kick, but the full-time clock never resumes.

	match_time += delta
	simulated_match_time += delta * get_time_scale()
	_update_match_stage()

	if current_half == 1:
		if simulated_match_time >= SIMULATED_HALF_DURATION and not _stoppage_announced:
			_stoppage_announced = true
			stoppage_minutes_half_1 = clampi(int(ceil(_accumulated_stoppage_sec / 60.0)), 1, 6)
			GameEvents.stoppage_time_announced.emit(stoppage_minutes_half_1, 1)

		var target_h1_end: float = SIMULATED_HALF_DURATION + float(stoppage_minutes_half_1 * 60)
		if not _half_time_fired and simulated_match_time >= target_h1_end:
			simulated_match_time = target_h1_end
			_half_time_fired = true
			set_phase(MatchPhase.HALF_TIME)   # Pauses the clock — IN_PLAY guard now exits
			GameEvents.half_time_started.emit()
			GameEvents.half_time_reached.emit()
	elif current_half >= 2:
		if simulated_match_time >= SIMULATED_MATCH_DURATION and not _stoppage_announced:
			_stoppage_announced = true
			stoppage_minutes_half_2 = clampi(int(ceil(_accumulated_stoppage_sec / 60.0)), 1, 9)
			GameEvents.stoppage_time_announced.emit(stoppage_minutes_half_2, 2)

		var target_h2_end: float = SIMULATED_MATCH_DURATION + float(stoppage_minutes_half_2 * 60)
		if simulated_match_time >= target_h2_end:
			simulated_match_time = target_h2_end
			_end_match()


## Checked every IN_PLAY frame alongside the half-time check above — cheap
## fraction comparisons, no allocation. Only emits when the stage actually
## changes, mirroring set_phase()'s early-out.
func _update_match_stage() -> void:
	var ratio: float = get_match_time_ratio()
	var stage: MatchStage = MatchStage.GAME_CRUNCH
	if ratio < STAGE_1_FRACTION:
		stage = MatchStage.SIZING_UP
	elif ratio < STAGE_2_FRACTION:
		stage = MatchStage.EQUILIBRIUM
	elif ratio < STAGE_3_FRACTION:
		stage = MatchStage.TRANSITIONS

	if stage != _last_match_stage:
		_last_match_stage = stage
		GameEvents.match_stage_changed.emit(stage)


func start_match() -> void:
	match_time = 0.0
	simulated_match_time = 0.0
	current_half = 1
	match_duration = half_duration_real_sec * 2.0
	score = [0, 0]
	last_scoring_team = -1
	_half_time_fired = false
	shootout_active = false
	match_opening_kickoff_team = TEAM_A
	_accumulated_stoppage_sec = 60.0
	stoppage_minutes_half_1 = 0
	stoppage_minutes_half_2 = 0
	_stoppage_announced = false
	_last_match_stage = MatchStage.SIZING_UP
	set_phase(MatchPhase.KICKOFF)
	GameEvents.kickoff_started.emit()


func start_second_half() -> void:
	current_half = 2
	simulated_match_time = SIMULATED_HALF_DURATION
	_accumulated_stoppage_sec = 120.0
	_stoppage_announced = false
	set_phase(MatchPhase.KICKOFF)
	GameEvents.half_time_ended.emit()
	GameEvents.kickoff_started.emit()


func register_goal(team: int, scorer: Node = null) -> void:
	if current_phase != MatchPhase.IN_PLAY:
		return

	if shootout_active:
		# PenaltyShootoutCoordinator tracks its own shootout_score; the match
		# score, GOAL_SCORED phase and kickoff-restart ceremony must all stay
		# untouched here, or PitchScene's normal goal handling would hijack a
		# shootout kick into a full kickoff reset.
		GameEvents.goal_scored.emit(team, scorer)
		return

	score[team] += 1
	last_scoring_team = team
	set_phase(MatchPhase.GOAL_SCORED)
	GameEvents.goal_scored.emit(team, scorer)


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


func get_match_tick() -> int:
	return _match_tick


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


## "MM:SS" format across the simulated 90 minutes (00:00 to 45:00, 45:00 to 90:00).
## Stoppage time displays as 45:00 +X or 90:00 +X when exceeding regulation half time.
func get_clock_string() -> String:
	var total_sec: int = int(simulated_match_time)
	if current_half == 1 and total_sec >= int(SIMULATED_HALF_DURATION):
		var extra_half1: int = (total_sec - int(SIMULATED_HALF_DURATION) + 59) / 60
		var display_added1: int = maxi(stoppage_minutes_half_1, extra_half1)
		return "45:00 +%d" % display_added1
	elif current_half >= 2 and total_sec >= int(SIMULATED_MATCH_DURATION):
		var extra_half2: int = (total_sec - int(SIMULATED_MATCH_DURATION) + 59) / 60
		var display_added2: int = maxi(stoppage_minutes_half_2, extra_half2)
		return "90:00 +%d" % display_added2

	var minutes: int = total_sec / 60
	var seconds: int = total_sec % 60
	return "%02d:%02d" % [minutes, seconds]


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


## Called once by PenaltyShootoutCoordinator when full time ends level (see
## _end_match() above — get_leading_team() returns -1 on a draw, which is
## PitchScene._on_match_ended()'s cue to start a shootout instead of ending
## the match). Suspends the full-time clock without touching score or
## last_scoring_team, both of which stay owned by the regular 90 minutes.
func start_shootout() -> void:
	shootout_active = true
	set_phase(MatchPhase.PENALTY_SHOOTOUT)


## Called once by PenaltyShootoutCoordinator once a winner is decided. Re-fires
## match_ended exactly as a normal full-time whistle would, so PitchScene's
## existing full-time path (stats logging, etc.) runs once, at the real end of
## the match — winner here is always TEAM_A/TEAM_B, never a draw.
func end_shootout(winner: int) -> void:
	shootout_active = false
	set_phase(MatchPhase.FULL_TIME)
	GameEvents.match_ended.emit(winner)
