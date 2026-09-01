##
## TackleState
##
## A committed lunge with a success window, in the spirit of FIFA 12's tactical
## defending: contact inside the window wins the ball, contact outside it (or no
## contact at all) leaves the defender stumbling and out of position.
##
##   0.0 .. WINDUP            planting, no hitbox
##   WINDUP .. WINDUP+WINDOW  live window — ball contact wins possession
##   after                    recovery, movement input ignored
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, GameEvents.
## Exposes: the PlayerState interface.
##

class_name TackleState
extends PlayerState

## Seconds before the tackle goes live.
const WINDUP: float = 0.08
## Length of the successful-contact window.
const WINDOW: float = 0.2
## Seconds of stumble after a miss, during which input is ignored.
const RECOVERY: float = 0.45
## Lunge impulse along the facing direction.
const LUNGE_SPEED: float = 190.0
## How hard a won ball is knocked clear of the loser.
const DISPOSSESS_IMPULSE: float = 150.0
## A miss that still lands the tackler this close to an opponent is judged a
## foul rather than a clean whiff — a proxy for "the challenge took the man".
const FOUL_CONTACT_RADIUS: float = 40.0
## Duration of possession lockout applied to the tackled player (victim).
const TACKLE_DISPOSSESS_LOCKOUT: float = 0.20

## Minimum dot product (tackler facing_direction · direction_to_ball) for the
## challenge to be considered aimed at the ball.
## 0.42 ≈ cos(65°) — within a 65° half-cone. Wider than this is a side-lunge.
const MIN_FACING_DOT: float = 0.42

## Dot product below which a non-facing challenge is always a foul.
## -0.10 ≈ cos(96°) — clearly back-facing; no "aggression saves you" clause.
const BACK_TACKLE_FOUL_DOT: float = -0.10

var _elapsed: float = 0.0
var _resolved: bool = false
var _foul_checked: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func enter(player: HeavyPlayerController) -> void:
	_elapsed = 0.0
	_resolved = false
	_foul_checked = false
	# Commit the body forward. The lunge is an impulse, not a steering change:
	# once you have dived in, you are going where you were pointed.
	player.apply_external_impulse(player.facing_direction * LUNGE_SPEED)
	player.is_sprinting = false


func process(player: HeavyPlayerController, delta: float) -> StringName:
	_elapsed += delta

	if not _resolved and _elapsed >= WINDUP and _elapsed <= WINDUP + WINDOW:
		if _try_win_ball(player):
			_resolved = true
			return DRIBBLE

	# The live window has closed without winning the ball: a lunge that still
	# landed the tackler on top of an opponent is a mistimed, foul-worthy
	# challenge rather than a clean miss.
	if not _resolved and not _foul_checked and _elapsed > WINDUP + WINDOW:
		_foul_checked = true
		_check_mistimed_foul(player)

	if _elapsed >= WINDUP + WINDOW + RECOVERY:
		return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


func physics_process(player: HeavyPlayerController, delta: float) -> void:
	# No steering during a tackle — the lunge and friction alone decide where the
	# defender ends up. This is what makes a mistimed challenge expensive.
	player.apply_kinematic_weight(Vector2.ZERO, delta)


func _try_win_ball(player: HeavyPlayerController) -> bool:
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball == null or ball.is_airborne():
		return false

	# ── Facing check ──────────────────────────────────────────────────────
	# The tackler must be roughly aimed at the ball. A lunge from the side or
	# behind reaches the man, not the ball — that is a foul, not a tackle.
	var facing_dot: float = player.get_facing_dot(ball.global_position)

	if facing_dot < MIN_FACING_DOT:
		# Not aimed at the ball. Call the foul check now (inside the live
		# window) so it is not called a second time by the post-window path
		# in process(). Do NOT set _resolved — fall through to RECOVERY.
		if not _foul_checked:
			_foul_checked = true
			_check_mistimed_foul(player, facing_dot)
		return false

	# ── Existing win-ball path ─────────────────────────────────────────────
	var loser: Node2D = ball.possessor
	var victim := loser as HeavyPlayerController
	if victim != null:
		victim.ball_control_lockout = TACKLE_DISPOSSESS_LOCKOUT

	ball.apply_kick(player.facing_direction * DISPOSSESS_IMPULSE, 0.0, player)
	if player.can_carry_ball():
		ball.set_possessor(player)

	if loser != null and loser != player:
		GameEvents.tackle_won.emit(player, loser)

	if player.is_user_controlled:
		InputHelper.rumble(0.4, 0.7, 0.15)

	return true


## Called when a challenge missed or was not aimed at the ball.
## facing_dot: the dot product stored by _try_win_ball (or 0.0 from the
## post-window timeout path in process(), where no facing data was captured).
func _check_mistimed_foul(
		player: HeavyPlayerController,
		facing_dot: float = 0.0) -> void:
	var victim: HeavyPlayerController = _find_nearby_opponent(player)
	if victim == null:
		return

	# A fully back-facing challenge is always a foul — no attribute saves it.
	if facing_dot < BACK_TACKLE_FOUL_DOT:
		GameEvents.foul_committed.emit(player, victim, player.global_position)
		return

	# Side-on misses: foul probability scales with how off-angle the challenge
	# was, reduced by the aggression attribute (aggressive players are better
	# at last-ditch side challenges).
	var brain: PlayerBrain = player.get_node_or_null("PlayerBrain") as PlayerBrain
	var aggression: float = brain.aggression_attribute if brain != null else 0.5

	# side_factor: 0.0 = perfectly aimed (MIN_FACING_DOT), 1.0 = side-on (dot ≤ 0)
	var side_factor: float = clampf(1.0 - facing_dot / MIN_FACING_DOT, 0.0, 1.0)
	var foul_probability: float = side_factor * (1.0 - aggression * 0.4)

	if _rng.randf() < foul_probability:
		GameEvents.foul_committed.emit(player, victim, player.global_position)


func _find_nearby_opponent(player: HeavyPlayerController) -> HeavyPlayerController:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null:
		var opp_team: int = 1 - player.team
		var closest_opp: HeavyPlayerController = null
		var closest_dist_sq: float = FOUL_CONTACT_RADIUS * FOUL_CONTACT_RADIUS
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			if world.player_teams[i] != opp_team or not world.is_slot_live(i):
				continue
			var dist_sq: float = player.global_position.distance_squared_to(world.player_positions[i])
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				closest_opp = world.player_nodes[i]
		if closest_opp != null:
			return closest_opp

	var closest: HeavyPlayerController = null
	var closest_distance: float = FOUL_CONTACT_RADIUS
	for node: Node in player.get_tree().get_nodes_in_group(&"players"):
		var other := node as HeavyPlayerController
		if other == null or other == player or other.team == player.team:
			continue
		var distance: float = player.global_position.distance_to(other.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest = other
	return closest
