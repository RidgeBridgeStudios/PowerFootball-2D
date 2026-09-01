##
## SetPieceCoordinator
##
## The single brain for every dead-ball restart except kickoff (see PitchScene
## for why kickoff still runs through its own, simpler path). PitchScene hands
## it out-of-bounds and foul events; it works out which restart applies, freezes
## every player but the taker, places the ball, positions the defending side at
## a legal distance, and waits for the taker to confirm before releasing play.
##
## Deliberately knows nothing about the scene tree beyond what bind() gives it,
## so it can be reasoned about (and later tested) independently of PitchScene's
## layout.
##
## For a human-controlled free kick or penalty, action_switch cycles the taker
## through the rest of the attacking side (nearest-to-spot first) while
## confirmation is still pending — see _cycle_taker(). PitchScene defers
## action_switch to us during those two phases so the input isn't consumed
## twice (see PitchScene._process()).
##
## Depends on: GameManager, GameEvents (autoloads), PitchBoundary, Pseudo3DBall,
##             HeavyPlayerController, PlayerState (state name constants).
## Exposes: bind(ball, boundary, players), handle_out_of_bounds(), handle_foul(),
##          get_taker()
##

class_name SetPieceCoordinator
extends Node

## Pixels from the goal line to the penalty spot.
@export var penalty_spot_offset: float = 320.0
## How far the corner ball sits in from the touchline/end-line intersection.
@export var corner_flag_inset: float = 16.0
## Minimum distance defenders are pushed back to for a free kick or penalty.
@export var wall_distance: float = 176.0
## Fallback delay before a set piece auto-activates if nobody confirms it —
## the only path a CPU taker uses, since it never presses action_kick itself.
@export var confirmation_timeout: float = 4.0
## Seconds a CPU taker "thinks" before a set piece auto-activates.
@export var cpu_confirmation_delay: float = 1.0

## Penalty box dimensions, matching Phase 4 of the brief: 320px deep, 400px
## either side of the goal's centre line.
const PENALTY_AREA_DEPTH: float = 320.0
const PENALTY_AREA_HALF_WIDTH: float = 400.0

## How far inside the touchline a throw-in ball is placed, so it does not sit
## on top of the boundary sensor that just fired.
const THROW_IN_INSET: float = 24.0

var _ball: Pseudo3DBall
var _boundary: PitchBoundary
var _players: Node2D

var _current_taker: HeavyPlayerController = null
var _previous_active_player: HeavyPlayerController = null
var _awaiting_confirmation: bool = false

## Attacking-team players eligible to take the current restart, nearest to the
## spot first (index 0 is who _assign_taker() originally picked). Parallel to
## _taker_origins: each candidate's position at freeze time, before anyone was
## moved onto the spot, so _cycle_taker() can hand a deselected taker back
## their own spot instead of leaving them stacked on the ball.
var _taker_candidates: Array[HeavyPlayerController] = []
var _taker_origins: Array[Vector2] = []
var _taker_index: int = 0
## True only when this restart belongs to the human's team, i.e. cycling is
## meaningful. A CPU taker is fixed to whoever _assign_taker() picked.
var _taker_is_human: bool = false

@onready var _confirmation_timer: Timer = $ConfirmationTimer


func _ready() -> void:
	_confirmation_timer.timeout.connect(_on_confirmation_timer_timeout)


func bind(ball: Pseudo3DBall, boundary: PitchBoundary, players: Node2D) -> void:
	_ball = ball
	_boundary = boundary
	_players = players


func _process(_delta: float) -> void:
	if not _awaiting_confirmation or _current_taker == null:
		return
	if _current_taker.is_user_controlled and Input.is_action_just_pressed(&"action_kick"):
		_confirmation_timer.stop()
		_activate_set_piece()
		return
	if can_switch_taker() and Input.is_action_just_pressed(&"action_switch"):
		_cycle_taker(1)


## Whether action_switch should cycle the taker right now. Free kicks and
## penalties only — the other three restarts have no CPU-facing reason to
## expose it, and the human's own taker is always index 0 in _taker_candidates.
func can_switch_taker() -> bool:
	if not _awaiting_confirmation or not _taker_is_human:
		return false
	if _taker_candidates.size() <= 1:
		return false
	return (
		GameManager.current_phase == GameManager.MatchPhase.FREE_KICK
		or GameManager.current_phase == GameManager.MatchPhase.PENALTY_KICK
	)


func get_taker() -> HeavyPlayerController:
	return _current_taker


## side: "touchline_top" / "touchline_bottom" / "end_line_goal_kick" / "end_line_corner"
## (see PitchBoundary._on_ball_crossed_boundary for how the side/attacker split
## is decided). last_toucher may be null if nobody touched the ball last.
func handle_out_of_bounds(side: String, exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	if _boundary == null or _ball == null or _players == null:
		push_warning("[SetPiece] handle_out_of_bounds side=%s ABORTED — unbound (_boundary=%s _ball=%s _players=%s)" % [
			side, _boundary != null, _ball != null, _players != null])
		return
	print("[SetPiece] handle_out_of_bounds side=%s exit_pos=%s last_toucher=%s (awaiting_confirmation=%s current_taker=%s)" % [
		side, exit_pos, last_toucher.name if last_toucher != null else "null",
		_awaiting_confirmation, _current_taker.name if _current_taker != null else "null"])

	match side:
		"touchline_top", "touchline_bottom":
			_start_throw_in(exit_pos, last_toucher)
		"end_line_goal_kick":
			_start_goal_kick(exit_pos, last_toucher)
		"end_line_corner":
			_start_corner_kick(exit_pos, last_toucher)


func handle_foul(fouler: HeavyPlayerController, victim: HeavyPlayerController, foul_pos: Vector2) -> void:
	if _boundary == null or fouler == null or victim == null:
		return

	var attacking_team: int = victim.team
	var defending_team: int = fouler.team

	if _is_in_penalty_area(foul_pos, defending_team):
		_start_penalty(attacking_team, defending_team)
	else:
		_start_free_kick(attacking_team, foul_pos)


## --- Restart setup -----------------------------------------------------------

func _start_throw_in(exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	var team: int = _opposing_team_of(last_toucher)
	var rect: Rect2 = _boundary.get_pitch_rect()
	var clamped_x: float = clampf(exit_pos.x, rect.position.x, rect.position.x + rect.size.x)
	# A hair outside the line rather than inside it, so the taker stands
	# completely outside the pitch line.
	var touchline_y: float = (
		rect.position.y - THROW_IN_INSET
		if exit_pos.y < _boundary.get_centre_spot().y
		else rect.position.y + rect.size.y + THROW_IN_INSET
	)
	var position: Vector2 = Vector2(clamped_x, touchline_y)

	_begin_set_piece(GameManager.MatchPhase.THROW_IN, team, position)


func _start_goal_kick(exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	# The attacker's own team touched it last, so the defending team gets the kick.
	var defending_team: int = _opposing_team_of(last_toucher)
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var inward: float = 1.0 if defending_team == 0 else -1.0
	var side_sign: float = 1.0 if exit_pos.y >= _boundary.get_centre_spot().y else -1.0
	var position: Vector2 = goal_centre + Vector2(inward * 150.0, side_sign * 80.0)

	_begin_set_piece(GameManager.MatchPhase.GOAL_KICK, defending_team, position)


func _start_corner_kick(exit_pos: Vector2, last_toucher: HeavyPlayerController) -> void:
	# The defender touched it last, so the attacking team (the opponent of
	# whichever goal this end line belongs to) gets the corner.
	var defending_team: int = last_toucher.team if last_toucher != null else 0
	var attacking_team: int = 1 - defending_team
	var half: Vector2 = _boundary.pitch_size * 0.5
	var centre: Vector2 = _boundary.get_centre_spot()
	var x_sign: float = 1.0 if exit_pos.x >= centre.x else -1.0
	var y_sign: float = 1.0 if exit_pos.y >= centre.y else -1.0
	var position: Vector2 = centre + Vector2(
		x_sign * (half.x - corner_flag_inset),
		y_sign * (half.y - corner_flag_inset),
	)

	_begin_set_piece(GameManager.MatchPhase.CORNER_KICK, attacking_team, position)


func _start_free_kick(team: int, foul_pos: Vector2) -> void:
	GameManager.start_free_kick(team, foul_pos, true)
	_setup_taking_side(GameManager.MatchPhase.FREE_KICK, team, foul_pos)
	_build_defensive_wall(foul_pos, 1 - team)


## Public entry point for offside restarts. Identical to an indirect free kick
## awarded to the defending team at the offside position — but the caller
## (OffsideDetector) has already called GameManager.start_free_kick() itself
## (to set free_kick_is_direct = false), so this only runs the coordinator-local
## setup (freeze → assign taker → position defenders → await confirmation)
## rather than _start_free_kick(), which would call GameManager.start_free_kick()
## a second time and force the restart back to direct.
func handle_indirect_offside(defending_team: int, offside_pos: Vector2) -> void:
	_setup_taking_side(GameManager.MatchPhase.FREE_KICK, defending_team, offside_pos)


## Public entry point for the Practice Arena. Computes the penalty spot for
## `defending_team`'s goal and runs the full penalty setup.
func start_penalty_for_practice(attacking_team: int, defending_team: int) -> void:
	_start_penalty(attacking_team, defending_team)


## Public entry point for shootouts or specific taker assignments.
func start_penalty_with_taker(attacking_team: int, defending_team: int, designated_taker: HeavyPlayerController) -> void:
	_start_penalty(attacking_team, defending_team, designated_taker)


## Public entry point for kickoff. PitchScene has already repositioned everyone
## and frozen the ball; this freezes the players, picks the taker, and parks the
## ball on the centre spot. Unlike the other restarts this does NOT call
## GameManager.start_set_piece() — PitchScene owns the KICKOFF phase via
## GameManager.kickoff(), and a kickoff has no positioning/phase transition to
## perform beyond what the taker mechanic already provides.
func start_kickoff(team: int) -> void:
	if _ball == null or _players == null:
		return
	var centre: Vector2 = _boundary.get_centre_spot()
	# FIX: set_piece_position is normally written by start_set_piece(), which
	# is intentionally skipped for kickoffs. Set it manually so _assign_taker()
	# and _activate_set_piece() read the correct centre spot instead of stale
	# data from the previous dead-ball event.
	GameManager.set_piece_position = centre
	_ball.reset_at(centre)
	_ball.freeze()
	_setup_taking_side(GameManager.MatchPhase.KICKOFF, team, centre)


func _start_penalty(attacking_team: int, defending_team: int, designated_taker: HeavyPlayerController = null) -> void:
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var attack_direction: float = 1.0 if defending_team == 0 else -1.0
	var position: Vector2 = goal_centre + Vector2(penalty_spot_offset * attack_direction, 0.0)

	GameManager.start_penalty(attacking_team, position)
	_setup_taking_side(GameManager.MatchPhase.PENALTY_KICK, attacking_team, position, designated_taker)
	_position_goalkeeper(defending_team)
	_clear_penalty_box_and_arc(position, defending_team)


## Shared setup for the three restarts whose GameManager call only needs
## (phase, team, position) — throw-ins, goal kicks and corners.
func _begin_set_piece(phase: int, team: int, position: Vector2) -> void:
	GameManager.start_set_piece(phase, team, position)
	_setup_taking_side(phase, team, position)


## Common tail of every restart: freeze the pitch, park the ball, pick a taker,
## push the opposition back, and wait for the go-ahead.
func _setup_taking_side(phase: int, team: int, position: Vector2, designated_taker: HeavyPlayerController = null) -> void:
	# Snapshot before freezing — _freeze_all_players() clears is_user_controlled
	# on every player, so _assign_taker()'s kickoff branch would otherwise always
	# read false here regardless of which side the human actually plays.
	var team_has_human: bool = _team_has_human(team)
	_freeze_all_players()
	_ball.reset_at(position)
	_assign_taker(team, team_has_human, designated_taker)
	_position_defending_players(phase)
	if phase == GameManager.MatchPhase.CORNER_KICK:
		_position_attacking_players_for_corner(team, position)
	_await_taker_confirmation()


## --- Player handling ----------------------------------------------------------

func _freeze_all_players() -> void:
	_previous_active_player = null
	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		if player.is_user_controlled:
			_previous_active_player = player
		player.is_user_controlled = false
		player.movement_intent = Vector2.ZERO
		player.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)


## `kickoff_team_has_human` is only meaningful for a KICKOFF restart — it must
## be resolved by the caller before _freeze_all_players() runs (see
## _setup_taking_side), since that clears is_user_controlled on every player
## before this function ever sees it.
func _assign_taker(team: int, kickoff_team_has_human: bool = false, designated_taker: HeavyPlayerController = null) -> void:
	var spot: Vector2 = GameManager.set_piece_position

	_taker_candidates.clear()
	_taker_origins.clear()
	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player.team != team:
			continue
		_taker_candidates.append(player)

	if designated_taker != null and _taker_candidates.has(designated_taker):
		_taker_candidates.erase(designated_taker)
		_taker_candidates.push_front(designated_taker)
	else:
		_taker_candidates.sort_custom(func(a: HeavyPlayerController, b: HeavyPlayerController) -> bool:
			return a.global_position.distance_squared_to(spot) < b.global_position.distance_squared_to(spot)
		)

	# Recorded after sorting, in the same order, so index i of each array
	# always describes the same player — this is each candidate's own spot
	# at freeze time, before anyone is moved onto the ball.
	for candidate: HeavyPlayerController in _taker_candidates:
		_taker_origins.append(candidate.global_position)

	_taker_index = 0
	_current_taker = _taker_candidates[0] if not _taker_candidates.is_empty() else null
	if _current_taker == null:
		print("[SetPiece] _assign_taker team=%d FOUND NO CANDIDATES (spot=%s)" % [team, spot])
		return

	_current_taker.global_position = spot
	_current_taker.velocity = Vector2.ZERO
	_current_taker.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)
	print("[SetPiece] _assign_taker team=%d taker=%s placed_at=%s (spot=%s, dist=%.1fpx) candidates=%d" % [
		team, _current_taker.name, _current_taker.global_position, spot,
		_current_taker.global_position.distance_to(spot), _taker_candidates.size()])

	# The taker is human-controlled only when the set piece belongs to the
	# team the human was already controlling; otherwise it stays a CPU restart
	# and control returns to the human's own player once play resumes.
	_taker_is_human = _previous_active_player != null and _previous_active_player.team == team
	# Kickoff is a special case: control is always handed to the kicking side
	# regardless of which team was controlled before the goal, so the human who
	# just conceded is the one holding the pad for the restart.
	if GameManager.current_phase == GameManager.MatchPhase.KICKOFF:
		_taker_is_human = kickoff_team_has_human
	if _taker_is_human:
		_current_taker.is_user_controlled = true
		# Reuse the existing player-switch channel so the HUD (power meter,
		# stamina bar) and action_switch follow the new controlled player
		# rather than going stale on whoever it was tracking before.
		GameEvents.player_switched.emit(_current_taker)


## Swaps the taker for the next (direction +1) or previous (-1) candidate,
## wrapping around. Only ever called when can_switch_taker() is true, so the
## restart is a human free kick or penalty and there is somebody to switch to.
func _cycle_taker(direction: int) -> void:
	var spot: Vector2 = GameManager.set_piece_position

	var old_taker: HeavyPlayerController = _current_taker
	old_taker.global_position = _taker_origins[_taker_index]
	old_taker.velocity = Vector2.ZERO
	old_taker.is_user_controlled = false

	_taker_index = wrapi(_taker_index + direction, 0, _taker_candidates.size())
	_current_taker = _taker_candidates[_taker_index]

	_current_taker.global_position = spot
	_current_taker.velocity = Vector2.ZERO
	_current_taker.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)
	_current_taker.is_user_controlled = true

	GameEvents.player_switched.emit(_current_taker)


## Moves opposing CPU players back to a legal distance.
func _position_defending_players(phase: int) -> void:
	## KICKOFF: both sides must start in their own half, so this restarts with a
	## dedicated rule instead of the wall-distance push below.
	if phase == GameManager.MatchPhase.KICKOFF:
		_enforce_kickoff_halves()
		return

	if _current_taker == null or _boundary == null:
		return

	var defending_team: int = 1 - _current_taker.team
	var spot: Vector2 = GameManager.set_piece_position
	var pitch_rect: Rect2 = _boundary.get_pitch_rect().grow(-20.0)
	var min_distance: float = wall_distance
	if phase == GameManager.MatchPhase.CORNER_KICK or phase == GameManager.MatchPhase.GOAL_KICK:
		min_distance = penalty_spot_offset

	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player.team != defending_team or player == _current_taker:
			continue

		if phase == GameManager.MatchPhase.GOAL_KICK:
			# Strict IFAB Law 16: Opponents must remain outside the penalty area
			if _is_in_penalty_area(player.global_position, defending_team):
				var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
				var dir: float = 1.0 if defending_team == 0 else -1.0
				var goal_area_x: float = goal_centre.x + dir * (PENALTY_AREA_DEPTH + 30.0)
				player.global_position.x = clampf(goal_area_x, pitch_rect.position.x, pitch_rect.end.x)
				player.velocity = Vector2.ZERO
				continue

		var offset: Vector2 = player.global_position - spot
		if offset.length() < min_distance:
			var direction: Vector2 = offset.normalized() if offset.length() > 0.001 else Vector2.RIGHT
			var target_pos: Vector2 = spot + direction * min_distance
			target_pos.x = clampf(target_pos.x, pitch_rect.position.x, pitch_rect.end.x)
			target_pos.y = clampf(target_pos.y, pitch_rect.position.y, pitch_rect.end.y)
			player.global_position = target_pos
			player.velocity = Vector2.ZERO


## Sends the attacking side's non-taker outfield players into realistic
## crossing positions (near post, six-yard box, far post, edge-of-box
## cutback) instead of leaving them wherever they stood when the corner was
## won — SetPieceFreezeState holds them there until GameManager.restart_play()
## fires, exactly like the defending wall/line positioning above, so this is
## the attacking-side mirror of _position_defending_players() rather than a
## run the players make themselves. GK is exempt. See AGENTS_ERRATA.md:
## corner-kick-no-attacking-box-runs.
func _position_attacking_players_for_corner(attacking_team: int, corner_spot: Vector2) -> void:
	if _boundary == null or _players == null:
		return

	var defending_team: int = 1 - attacking_team
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	# Same "into the pitch, away from the goal line" sign convention as
	# _is_in_penalty_area()'s `direction`.
	var into_pitch: float = 1.0 if defending_team == 0 else -1.0
	var corner_side: float = signf(corner_spot.y - _boundary.get_centre_spot().y)
	if is_zero_approx(corner_side):
		corner_side = 1.0
	var pitch_rect: Rect2 = _boundary.get_pitch_rect().grow(-20.0)

	# Priority order for however many attackers are actually available.
	var box_targets: Array[Vector2] = [
		goal_centre + Vector2(into_pitch * 60.0, corner_side * -70.0),   # near post
		goal_centre + Vector2(into_pitch * 90.0, corner_side * 10.0),    # six-yard box, central
		goal_centre + Vector2(into_pitch * 70.0, corner_side * 90.0),    # far post
		goal_centre + Vector2(into_pitch * 260.0, corner_side * 40.0),   # edge-of-box cutback
	]

	var attackers: Array[HeavyPlayerController] = []
	for node: Node in _players.get_children():
		var p := node as HeavyPlayerController
		if p == null or p.team != attacking_team or p == _current_taker:
			continue
		var brain := p.get_node_or_null("PlayerBrain") as PlayerBrain
		if brain != null and brain.is_goalkeeper:
			continue
		attackers.append(p)

	attackers.sort_custom(func(a: HeavyPlayerController, b: HeavyPlayerController) -> bool:
		return a.global_position.distance_squared_to(goal_centre) < b.global_position.distance_squared_to(goal_centre)
	)

	var count: int = mini(attackers.size(), box_targets.size())
	for i: int in range(count):
		var target: Vector2 = box_targets[i]
		target.x = clampf(target.x, pitch_rect.position.x, pitch_rect.end.x)
		target.y = clampf(target.y, pitch_rect.position.y, pitch_rect.end.y)
		attackers[i].global_position = target
		attackers[i].velocity = Vector2.ZERO


## KICKOFF: constrains every outfield player to their own half of the pitch.
## Handles half-time end swapping dynamically by deriving half from goal centre X.
## The taker is left on the centre spot, and the defending side honours the standard
## center circle radius (176px) without spilling across the halfway line (IFAB Law 8).
func _enforce_kickoff_halves() -> void:
	if _boundary == null or _current_taker == null:
		return

	var centre_spot: Vector2 = _boundary.get_centre_spot()
	var centre_x: float = centre_spot.x
	var defending_team: int = 1 - _current_taker.team
	var spot: Vector2 = GameManager.set_piece_position

	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player == _current_taker:
			continue

		# Determine defending half from goal position (supports half-time end swapping)
		var goal_x: float = _boundary.get_goal_centre(player.team).x
		var defends_left: bool = goal_x < centre_x

		var in_correct_half: bool = (player.global_position.x <= centre_x) if defends_left else (player.global_position.x >= centre_x)
		if not in_correct_half:
			var clamped_x: float = centre_x - 12.0 if defends_left else centre_x + 12.0
			player.global_position = Vector2(clamped_x, player.global_position.y)
			player.velocity = Vector2.ZERO

		if player.team == defending_team:
			var offset: Vector2 = player.global_position - spot
			if offset.length() < wall_distance:
				var push_dir: Vector2 = offset.normalized() if offset.length() > 0.001 else (Vector2.LEFT if defends_left else Vector2.RIGHT)
				var new_pos: Vector2 = spot + push_dir * wall_distance
				if defends_left:
					new_pos.x = minf(new_pos.x, centre_x - 4.0)
				else:
					new_pos.x = maxf(new_pos.x, centre_x + 4.0)
				player.global_position = new_pos
				player.velocity = Vector2.ZERO


## --- Confirmation and activation ----------------------------------------------

func _await_taker_confirmation() -> void:
	if _current_taker == null:
		# No eligible taker was found (e.g. an empty _taker_candidates list).
		# Every player was already pushed into SET_PIECE_FREEZE by
		# _freeze_all_players(), and SetPieceFreezeState only ever hands back
		# to Idle once GameManager.is_in_play() is true again — so silently
		# returning here left the whole match frozen forever with no recovery
		# path (see AGENTS_ERRATA.md: corner-kick-empty-taker-permanent-freeze).
		push_warning("SetPieceCoordinator: no eligible taker for phase %d — aborting restart instead of freezing the match." % GameManager.current_phase)
		GameManager.restart_play()
		return
	_awaiting_confirmation = true
	var delay: float = confirmation_timeout if _current_taker.is_user_controlled else cpu_confirmation_delay
	print("[SetPiece] awaiting confirmation: taker=%s human=%s delay=%.2fs phase=%d" % [
		_current_taker.name, _current_taker.is_user_controlled, delay, GameManager.current_phase])
	_confirmation_timer.start(delay)


func _on_confirmation_timer_timeout() -> void:
	if _awaiting_confirmation:
		_activate_set_piece()


func _activate_set_piece() -> void:
	_awaiting_confirmation = false
	if _current_taker == null:
		print("[SetPiece] _activate_set_piece: current_taker is null — nothing to activate")
		return
	print("[SetPiece] _activate_set_piece: taker=%s phase=%d taker_pos_before=%s set_piece_pos=%s" % [
		_current_taker.name, GameManager.current_phase, _current_taker.global_position, GameManager.set_piece_position])

	_ball.reset_at(GameManager.set_piece_position)
	_ball.unfreeze()
	_ball.mark_set_piece_restart(_current_taker)

	_current_taker.global_position = GameManager.set_piece_position
	_current_taker.velocity = Vector2.ZERO

	# A CPU taker was frozen (SetPieceFreezeState) then teleported onto its
	# restart spot, so its facing_direction is stale — whatever it last was
	# while moving, unrelated to any teammate. ChargeKickState aims a CPU
	# kick along facing_direction (no stick input to fall back on), so
	# without this a kickoff/free kick/corner "pass" fires in an arbitrary
	# stale direction and can gift the ball straight to an opponent.
	if not _current_taker.is_user_controlled:
		var taker_brain: PlayerBrain = _current_taker.get_node_or_null("PlayerBrain") as PlayerBrain
		var pass_target: HeavyPlayerController = taker_brain.find_pass_target_for_set_piece() if taker_brain != null else null
		if pass_target != null:
			_current_taker.facing_direction = _current_taker.global_position.direction_to(pass_target.global_position)
		elif _boundary != null:
			# find_pass_target_for_set_piece() can legally return null (no
			# candidate clears MIN_PASS_SCORE, or every lane is blocked) —
			# that used to leave facing_direction at whatever stale value it
			# held before the freeze, which can point anywhere, including
			# back out of bounds. ChargeKickState's CPU path always fires an
			# immediate tap (wants() is always false for a non-user-controlled
			# player), so a stale out-of-bounds facing taps a corner/free
			# kick/goal kick straight back out and can hand the restart to
			# the other team. Aiming at the pitch centre from any restart
			# spot is always a safe, in-bounds fallback (see AGENTS_ERRATA.md:
			# corner-kick-stale-facing-direction-no-fallback).
			_current_taker.facing_direction = _current_taker.global_position.direction_to(_boundary.get_centre_spot())

	_current_taker.state_factory.state_changed.connect(_on_taker_state_changed)

	match GameManager.current_phase:
		GameManager.MatchPhase.THROW_IN:
			_current_taker.state_factory.transition_to(PlayerState.THROW_IN)
		GameManager.MatchPhase.PENALTY_KICK:
			_current_taker.state_factory.transition_to(PlayerState.PENALTY_KICK)
		# KICKOFF and every other restart fall through to a charge kick.
		_:
			_current_taker.state_factory.transition_to(PlayerState.CHARGE_KICK)


## Fires once the taker's kicking state hands off (ball struck or thrown),
## rather than at the moment we force them into it — that is the point at
## which the set piece has actually been "taken".
func _on_taker_state_changed(from_state: StringName, _to_state: StringName) -> void:
	var taking_states: Array[StringName] = [PlayerState.CHARGE_KICK, PlayerState.THROW_IN, PlayerState.PENALTY_KICK]
	if not taking_states.has(from_state):
		return

	print("[SetPiece] _on_taker_state_changed: from=%s to=%s taker=%s — calling restart_play()" % [
		from_state, _to_state, _current_taker.name if _current_taker != null else "null(!)"])
	_current_taker.state_factory.state_changed.disconnect(_on_taker_state_changed)
	GameEvents.set_piece_taken.emit(_current_taker)
	GameManager.restart_play()

	if not _current_taker.is_user_controlled and _previous_active_player != null and is_instance_valid(_previous_active_player):
		_previous_active_player.is_user_controlled = true
		GameEvents.player_switched.emit(_previous_active_player)

	_current_taker = null


## --- Penalty area & Goalkeeper ------------------------------------------------

func _is_in_penalty_area(pos: Vector2, defending_team: int) -> bool:
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var direction: float = 1.0 if defending_team == 0 else -1.0
	var local: Vector2 = pos - goal_centre
	var depth: float = local.x * direction

	return depth >= 0.0 and depth <= PENALTY_AREA_DEPTH and absf(local.y) <= PENALTY_AREA_HALF_WIDTH


## Places the defending goalkeeper strictly on the goal line facing forward (IFAB Law 14).
func _position_goalkeeper(defending_team: int) -> void:
	if _players == null or _boundary == null:
		return
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var direction: float = -1.0 if defending_team == 0 else 1.0
	var spot: Vector2 = goal_centre - Vector2(direction * 48.0, 0.0)

	for node: Node in _players.get_children():
		var p := node as HeavyPlayerController
		if p == null or p.team != defending_team:
			continue
		var brain := p.get_node_or_null("PlayerBrain") as PlayerBrain
		if brain != null and brain.is_goalkeeper:
			p.global_position = spot
			p.velocity = Vector2.ZERO
			p.movement_intent = Vector2.ZERO
			p.state_factory.transition_to(PlayerState.SET_PIECE_FREEZE)
			break


## Clears all non-taking outfielders (both attacking and defending) outside the penalty box and arc (IFAB Law 14).
func _clear_penalty_box_and_arc(penalty_spot: Vector2, defending_team: int) -> void:
	if _players == null or _boundary == null:
		return
	var attack_dir: float = 1.0 if defending_team == 0 else -1.0
	var arc_radius: float = wall_distance
	var pitch_rect: Rect2 = _boundary.get_pitch_rect().grow(-32.0)

	for node: Node in _players.get_children():
		var p := node as HeavyPlayerController
		if p == null or p == _current_taker:
			continue
		var brain := p.get_node_or_null("PlayerBrain") as PlayerBrain
		if brain != null and brain.is_goalkeeper and p.team == defending_team:
			continue

		var in_box: bool = _is_in_penalty_area(p.global_position, defending_team)
		var dist_to_spot: float = p.global_position.distance_to(penalty_spot)
		var in_arc: bool = dist_to_spot < arc_radius
		var is_ahead_of_spot: bool = (p.global_position.x - penalty_spot.x) * attack_dir > -10.0

		if in_box or in_arc or is_ahead_of_spot:
			var target_x: float = penalty_spot.x - attack_dir * (PENALTY_AREA_DEPTH * 0.5 + 40.0)
			var target_y: float = p.global_position.y
			if absf(target_y - penalty_spot.y) < arc_radius:
				var sign_y: float = 1.0 if target_y >= penalty_spot.y else -1.0
				target_y = penalty_spot.y + sign_y * (arc_radius + 20.0)

			target_x = clampf(target_x, pitch_rect.position.x, pitch_rect.end.x)
			target_y = clampf(target_y, pitch_rect.position.y, pitch_rect.end.y)
			p.global_position = Vector2(target_x, target_y)
			p.velocity = Vector2.ZERO


## --- Defensive wall ------------------------------------------------------------

func _build_defensive_wall(free_kick_pos: Vector2, _defending_team: int) -> void:
	if _boundary == null or _players == null:
		GameEvents.defensive_wall_requested.emit(free_kick_pos)
		return

	var defending_team: int = _defending_team
	var goal_centre: Vector2 = _boundary.get_goal_centre(defending_team)
	var to_goal: Vector2 = (goal_centre - free_kick_pos).normalized()
	var wall_origin: Vector2 = free_kick_pos + to_goal * wall_distance
	var perp: Vector2 = Vector2(-to_goal.y, to_goal.x)
	var pitch_rect: Rect2 = _boundary.get_pitch_rect().grow(-32.0)

	# Collect outfield defenders for the wall (exclude goalkeeper).
	var defenders: Array[HeavyPlayerController] = []
	for node: Node in _players.get_children():
		var cand_def := node as HeavyPlayerController
		if cand_def == null or cand_def.team != defending_team:
			continue
		var brain := cand_def.get_node_or_null("PlayerBrain") as PlayerBrain
		if brain != null and brain.is_goalkeeper:
			continue
		defenders.append(cand_def)

	# Sort by proximity to the free kick spot; take the 4 closest.
	defenders.sort_custom(func(a: HeavyPlayerController, b: HeavyPlayerController) -> bool:
		return a.global_position.distance_squared_to(free_kick_pos) < b.global_position.distance_squared_to(free_kick_pos)
	)
	var wall_size: int = mini(defenders.size(), 4)

	# Space them 60 px apart, centred on wall_origin.
	var spacing: float = 60.0
	var half_span: float = float(wall_size - 1) * spacing * 0.5

	var wall_positions: Array[Vector2] = []
	for i: int in range(wall_size):
		var wall_player: HeavyPlayerController = defenders[i]
		var lateral_offset: float = -half_span + float(i) * spacing
		var target_pos: Vector2 = wall_origin + perp * lateral_offset
		target_pos.x = clampf(target_pos.x, pitch_rect.position.x, pitch_rect.end.x)
		target_pos.y = clampf(target_pos.y, pitch_rect.position.y, pitch_rect.end.y)
		wall_player.global_position = target_pos
		wall_player.velocity = Vector2.ZERO
		wall_positions.append(target_pos)

	if wall_size >= 3:
		_enforce_wall_attacker_separation(wall_positions, 1 - defending_team, 20.0)

	GameEvents.defensive_wall_requested.emit(free_kick_pos)


## Enforces 1m (20px) buffer for all attacking players from a 3+ player defensive wall (IFAB Law 13).
func _enforce_wall_attacker_separation(wall_positions: Array[Vector2], attacking_team: int, buffer: float) -> void:
	for node: Node in _players.get_children():
		var p := node as HeavyPlayerController
		if p == null or p.team != attacking_team or p == _current_taker:
			continue
		for w_pos: Vector2 in wall_positions:
			var dist: float = p.global_position.distance_to(w_pos)
			if dist < buffer:
				var push_dir: Vector2 = (p.global_position - w_pos).normalized()
				if push_dir == Vector2.ZERO:
					push_dir = Vector2.UP
				p.global_position = w_pos + push_dir * buffer
				p.velocity = Vector2.ZERO


func _opposing_team_of(player: HeavyPlayerController) -> int:
	if player == null:
		return 0
	return 1 - player.team


## Whether any player on `team` is human-controlled. Used for kickoff, where
## control should follow the kicking side rather than whoever held pad before.
func _team_has_human(team: int) -> bool:
	for node: Node in _players.get_children():
		var player := node as HeavyPlayerController
		if player != null and player.team == team and player.is_user_controlled:
			return true
	return false
