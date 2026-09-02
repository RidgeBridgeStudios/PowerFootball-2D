##
## DribbleState
##
## Loose possession, Sensible Soccer style. The ball is never parented or
## snapped to the player: it is nudged forward with micro-impulses whenever it
## drifts inside the foot sensor. Turn sharply or sprint too hard and the ball
## runs away from you — that separation is the mechanic, not a bug.
## Magnetism layer: every physics tick a velocity-correction pull keeps the ball
## at CARRY_OFFSET px ahead of the player along the travel direction. The magnet
## is intentionally strong — a 10px gap produces a 550 px/s correction so a
## sprinting player never outruns it. Only lateral/reverse momentum is damped;
## forward momentum is not braked.
##
## Depends on: PlayerState, HeavyPlayerController, Pseudo3DBall, TrustSystem.
## Exposes: the PlayerState interface.
##

class_name DribbleState
extends PlayerState

## --- Magnetism constants ----------------------------------------------------

## Pixels ahead of the player (along travel direction) the ball is pulled toward.
## NOTE: unused by live logic — kept as a fallback reference value only. The
## carry target now derives its offset from `close_control` dynamically (see
## physics_process) so high-control players keep the ball tighter.
const CARRY_OFFSET: float = 22.0

## Scales gap-in-pixels to correction px/s. 55.0 → 550 px/s per 10px gap.
## Strong enough that even a sprinting player (up to 304 px/s) cannot outrun
## the correction within a physics tick.
const MAGNET_STRENGTH: float = 55.0

## Lerp weight applied per physics tick to blend toward the magnet velocity.
## 0.85 locks the ball onto the carry target within ~1 frame at 60 Hz.
const MAGNET_BLEND: float = 0.85

## Fraction of MAGNET_STRENGTH applied to a FORWARD overshoot past
## carry_target (the ball got out ahead of the offset — normal right after a
## touch, not drift). Kept well below 1.0 so the magnet doesn't fight a
## touch's own momentum hard enough to flip velocity into reverse every
## cycle. Lateral/reverse offset is unaffected by this — see _apply_magnet().
const FORWARD_OVERSHOOT_SOFTEN: float = 0.20

## Fraction of the ball's lateral (perpendicular-to-travel) velocity kept each
## tick while possessed. Only sideways/reverse drift is damped — forward
## momentum along the carry direction is left untouched so the magnet never
## fights the ball's own momentum.
const LATERAL_DAMPING: float = 0.6

## Seconds the ball may stay outside the foot sensor before possession drops.
## Prevents jitter-drops from momentary physics separations at high speed.
const POSSESSION_GRACE: float = 0.10

## --- Touch constants ---------------------------------------------------------

## Sprint multiplier on touch speed. The ball still drifts looser at pace,
## but by one body length — not three.
const SPRINT_TOUCH_BONUS: float = 1.15
## Close control: dribbling costs a slice of top speed.
const DRIBBLE_SPEED_PENALTY: float = 0.9

## --- State vars -------------------------------------------------------------

var _touch_cooldown: float = 0.0
var _grace_timer: float = 0.0
var _carry_start_pos: Vector2 = Vector2.ZERO
## The ball this dribble session is tracking. Cached on enter so the magnet
## still has a target even on a tick where the ball is momentarily outside
## the foot sensor (grace window).
var _possessed_ball: Pseudo3DBall = null


func enter(player: HeavyPlayerController) -> void:
	_touch_cooldown = 0.0
	_grace_timer = 0.0
	_carry_start_pos = player.global_position
	var ball: Pseudo3DBall = player.get_ball_in_foot_range()
	if ball != null and player.can_carry_ball() \
			and (ball.possessor == null or ball.possessor == player):
		_notify_trust_of_reception(player, ball)
		ball.set_possessor(player)
		_possessed_ball = ball
		player.possession_gained.emit()
	else:
		_possessed_ball = null


func exit(player: HeavyPlayerController) -> void:
	if _possessed_ball != null and _possessed_ball.possessor == player:
		_possessed_ball.release_possession()
	if _carry_start_pos.distance_squared_to(player.global_position) > 40.0 * 40.0:
		MatchStatsTracker.record_carry_completed(player, _carry_start_pos, player.global_position)
	_possessed_ball = null
	player.possession_lost.emit()


func process(player: HeavyPlayerController, delta: float) -> StringName:
	# CPU players: exit dribble when the brain has decided to shoot or pass.
	# The brain's _steer_for_action() already handles the kick execution inline —
	# DribbleState only needs to step aside so the next frame's movement is correct.
	if not player.is_user_controlled:
		var brain: PlayerBrain = player.get_node_or_null("PlayerBrain") as PlayerBrain
		if brain != null:
			if brain.current_action == &"AttemptShoot" or brain.current_action == &"Pass":
				return PlayerState.MOVE

	_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)

	var common: StringName = check_common_transitions(player)
	if common != &"":
		return common

	var ball_in_range: Pseudo3DBall = player.get_ball_in_foot_range()

	if ball_in_range != null and player.can_carry_ball() \
			and (ball_in_range.possessor == null or ball_in_range.possessor == player):
		# Ball is inside the sensor and legitimately available — reset grace,
		# keep tracking.
		_grace_timer = 0.0
		if _possessed_ball == null:
			_notify_trust_of_reception(player, ball_in_range)
			_possessed_ball = ball_in_range
			ball_in_range.set_possessor(player)
	else:
		# Ball has left the sensor, or someone else now legitimately owns it
		# (e.g. a won tackle) — check grace window before dropping. See
		# AGENTS_ERRATA.md (dribble-claim-ignores-existing-possessor-dual-
		# driver-jitter).
		if _possessed_ball != null and _possessed_ball.possessor == player:
			_grace_timer += delta
			if _grace_timer >= POSSESSION_GRACE:
				# Grace expired — genuine loss of possession.
				return MOVE if player.movement_intent.length() > 0.05 else IDLE
		else:
			# No possessor link at all — drop immediately.
			return MOVE if player.movement_intent.length() > 0.05 else IDLE

	return &""


## Tells whoever last touched the ball (ball.last_touched_by, read BEFORE
## set_possessor() overwrites possession — last_touched_by itself is untouched
## by set_possessor(), see soccer-physics.md) that `player` has just gained the
## ball, so a pending pass registered by PlayerBrain.register_pass() can be
## resolved as a completed link-up or an interception. No-ops for a player
## picking the ball back up after their own touch (dribble continuation) and
## for anyone with no TrustSystem (a goalkeeper's brain never registers a
## pending pass, but the accessor is still safe to call).
func _notify_trust_of_reception(player: HeavyPlayerController, ball: Pseudo3DBall) -> void:
	var previous_toucher: HeavyPlayerController = ball.last_touched_by
	if previous_toucher == null or previous_toucher == player:
		return
	if previous_toucher.team == player.team:
		MatchStatsTracker.record_pass_completed(previous_toucher, player, previous_toucher.global_position, player.global_position)
	else:
		MatchStatsTracker.record_defensive_action(player, &"interception", player.global_position)
		player.show_action_text("INTERCEPT", Color(0.44, 0.85, 1.0))

	var passer_trust: TrustSystem = previous_toucher.get_trust_system()
	if passer_trust != null:
		passer_trust.resolve_possession_change(
			TrustSystem.player_key(player), previous_toucher.team == player.team)



func physics_process(player: HeavyPlayerController, delta: float) -> void:
	player.apply_kinematic_weight(player.movement_intent * DRIBBLE_SPEED_PENALTY, delta)

	var ball: Pseudo3DBall = _possessed_ball
	# possessor != player: someone else won this ball (e.g. a tackle) since
	# our last process() tick. process() and physics_process() run on
	# independently-scheduled callbacks (see PlayerStateFactory.gd), so this
	# guard — not process()'s own bookkeeping — is what actually stops a
	# dispossessed player from still driving the ball's velocity. See
	# AGENTS_ERRATA.md (dribble-claim-ignores-existing-possessor-dual-driver-
	# jitter).
	if ball == null or ball.is_airborne() or ball.possessor != player:
		return

	# --- Carry direction: where the player is physically travelling ----------
	# Use velocity.normalized() (actual travel) rather than facing_direction
	# (intent, can lag a frame during a turn). Fall back to facing_direction
	# at rest, where velocity carries no useful heading.
	var carry_dir: Vector2 = player.velocity.normalized() \
		if player.velocity.length() > 10.0 \
		else player.facing_direction

	var world: MatchWorldModel = MatchWorldModel.instance
	var shield_dir: Vector2 = carry_dir
	if world != null:
		var nearest_opp: Vector2 = world.nearest_opponent_position(
			player.global_position, player.team)
		var to_opp: Vector2 = (nearest_opp - player.global_position).normalized()
		if player.movement_intent.normalized().dot(to_opp) < -0.3:
			shield_dir = -to_opp
			player.show_action_text("SHIELD", Color(1.0, 0.82, 0.30))

	var dynamic_offset: float = lerpf(28.0, 16.0, player.get_close_control())
	var carry_target: Vector2 = player.global_position + shield_dir * dynamic_offset

	# --- Branch: touch frames skip the magnet entirely -----------------------
	# A touch tick already overwrites ball.velocity via apply_kick(), so the
	# magnet correction (selective damping + lerp) would be pure wasted work
	# on that frame. Branch on cooldown so each frame runs exactly one block:
	# either the touch impulse, or the magnet pull — never both.
	if _touch_cooldown <= 0.0:
		_apply_touch(player, carry_dir, shield_dir)
	else:
		_apply_magnet(ball, carry_dir, carry_target)
		_touch_cooldown = maxf(_touch_cooldown - delta, 0.0)


func _apply_magnet(ball: Pseudo3DBall, carry_dir: Vector2, carry_target: Vector2) -> void:
	# --- Selective damping: kill lateral/reverse drift, preserve forward -----
	# Project the ball's current velocity onto the carry direction; damp only
	# the perpendicular remainder so the magnet never brakes a ball that is
	# already rolling the right way.
	var forward_component: Vector2 = carry_dir * ball.velocity.dot(carry_dir)
	var lateral_component: Vector2 = ball.velocity - forward_component
	ball.velocity = forward_component + lateral_component * LATERAL_DAMPING

	# --- Magnet pull: blend toward offset-derived velocity -------------------
	# Split the position offset along the same forward/lateral axes as the
	# velocity damping above. A touch kick (up to ~340px/s at a sprint) can
	# send the ball meaningfully past the 16-28px carry_target offset within
	# a frame or two — that overshoot is the touch doing its job, not drift.
	# Correcting it at full MAGNET_STRENGTH every following magnet frame
	# fights the touch's own momentum hard enough to flip velocity from
	# strongly forward to meaningfully backward in a single blend step,
	# which then overshoots the other way and repeats — reading as the ball
	# visibly bouncing/jittering in a small area rather than smoothly
	# following the dribbler. Lateral/reverse drift — the actual "turn
	# sharply and the ball runs away from you" case this magnet exists for —
	# still gets the full, intentionally strong pull; only a FORWARD
	# overshoot along carry_dir is softened. See AGENTS_ERRATA.md
	# (dribble-magnet-forward-overshoot-oscillation).
	var offset: Vector2 = carry_target - ball.global_position
	var forward_offset: float = offset.dot(carry_dir)
	var lateral_offset: Vector2 = offset - carry_dir * forward_offset
	var forward_strength: float = MAGNET_STRENGTH if forward_offset >= 0.0 else MAGNET_STRENGTH * FORWARD_OVERSHOOT_SOFTEN
	var pull_velocity: Vector2 = carry_dir * forward_offset * forward_strength + lateral_offset * MAGNET_STRENGTH
	ball.velocity = ball.velocity.lerp(pull_velocity, MAGNET_BLEND)


func _apply_touch(player: HeavyPlayerController, carry_dir: Vector2, shield_dir: Vector2) -> void:
	var ball: Pseudo3DBall = _possessed_ball
	var control: float = player.get_close_control() if player.has_method(&"get_close_control") else 0.65
	var effective_touch_ratio: float = lerpf(0.85, 0.50, 1.0 - control)
	var effective_interval: float = lerpf(0.10, 0.20, 1.0 - control)

	# Push the ball along the running line rather than the stick line: a heavy
	# player cannot redirect the ball faster than they can redirect themselves.
	# Blend carry_dir toward the desired intent. At low speed the blend is 0 —
	# the ball follows the body's current heading. At full pace, up to 30° of
	# re-direction per touch is allowed, matching how a heavy player
	# realistically redirects the ball.
	var touch_direction: Vector2 = carry_dir
	if player.movement_intent.length() > 0.05:
		var desired: Vector2 = player.movement_intent.normalized()
		var blend: float = clampf(player.get_speed_ratio() * 0.5, 0.0, 0.5)
		touch_direction = carry_dir.lerp(desired, 1.0 - blend).normalized()

	# When actively shielding (shield_dir was diverted away from carry_dir),
	# push the ball slightly behind ourselves toward the shielded position
	# rather than continuing straight along the carry direction.
	if shield_dir != carry_dir:
		touch_direction = touch_direction.lerp(shield_dir, 0.4).normalized()

	# Deflect touch direction safely inward when carrying near the pitch perimeter
	var world_model: MatchWorldModel = MatchWorldModel.instance
	if world_model != null:
		var pitch_size: Vector2 = world_model.get_pitch_size()
		var half_pitch: Vector2 = pitch_size * 0.5
		var margin_top: float = player.global_position.y - (-half_pitch.y)
		var margin_bot: float = half_pitch.y - player.global_position.y
		if margin_top < 50.0 and touch_direction.y < 0.0:
			var damp_t: float = 1.0 - clampf(margin_top / 50.0, 0.0, 1.0)
			touch_direction.y = lerpf(touch_direction.y, 0.05, damp_t)
			if touch_direction.length_squared() > 0.0001:
				touch_direction = touch_direction.normalized()
		elif margin_bot < 50.0 and touch_direction.y > 0.0:
			var damp_b: float = 1.0 - clampf(margin_bot / 50.0, 0.0, 1.0)
			touch_direction.y = lerpf(touch_direction.y, -0.05, damp_b)
			if touch_direction.length_squared() > 0.0001:
				touch_direction = touch_direction.normalized()

		var margin_left: float = player.global_position.x - (-half_pitch.x)
		var margin_right: float = half_pitch.x - player.global_position.x
		if margin_left < 50.0 and touch_direction.x < 0.0:
			var damp_l: float = 1.0 - clampf(margin_left / 50.0, 0.0, 1.0)
			touch_direction.x = lerpf(touch_direction.x, 0.05, damp_l)
			if touch_direction.length_squared() > 0.0001:
				touch_direction = touch_direction.normalized()
		elif margin_right < 50.0 and touch_direction.x > 0.0:
			var damp_r: float = 1.0 - clampf(margin_right / 50.0, 0.0, 1.0)
			touch_direction.x = lerpf(touch_direction.x, -0.05, damp_r)
			if touch_direction.length_squared() > 0.0001:
				touch_direction = touch_direction.normalized()

	var touch_speed: float = player.get_current_top_speed() * effective_touch_ratio
	if player.is_sprinting:
		touch_speed *= SPRINT_TOUCH_BONUS

	ball.apply_kick(touch_direction * touch_speed, 0.0, player)
	ball.set_possessor(player)
	_touch_cooldown = effective_interval
