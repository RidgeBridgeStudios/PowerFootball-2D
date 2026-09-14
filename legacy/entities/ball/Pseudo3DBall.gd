##
## Pseudo3DBall
##
## The ball runs on two independent axes:
##   * ground plane (x, y) — a normal CharacterBody2D moving under pitch friction
##   * height (z)          — a scalar solved here and rendered as a sprite offset
##
## Height physics per tick:
##   z  += vz * dt
##   vz -= gravity * dt
## and on ground contact (z <= 0):
##   |vz| > bounce_threshold -> vz = -vz * restitution, v_xy *= bounce_friction_loss
##   otherwise               -> vz = 0, the ball settles and rolls
##
## The ball never hard-collides with players (see CollisionLayers): touching a
## CharacterBody2D through the physics solver would zero that player's velocity
## and wreck the momentum model. Foot sensors apply impulses through apply_kick()
## instead.
##
## Depends on:
##   - CollisionLayers for the matrix applied in _ready()
##   - GameEvents (autoload) for broadcasting kicks
##
## Exposes:
##   - apply_kick(impulse_xy, impulse_z, kicker)
##   - predict_trajectory(impulse_xy, impulse_z, steps, dt) -> Array[Vector2]
##   - reset_at(position), freeze() / unfreeze()
##   - position_z, velocity_z, is_on_ground, possessor, last_touched_by
##   - signals ball_bounced(impact_velocity), ball_kicked(impulse, height)
##

class_name Pseudo3DBall
extends CharacterBody2D

signal ball_bounced(impact_velocity: float)
signal ball_kicked(impulse: Vector2, height: float)
signal possession_changed(new_possessor: Node2D)

## Pixels per second squared pulling the ball back to the turf.
@export var gravity: float = 580.0
## Ground drag coefficient, applied per second while rolling.
## Calibration: raised from 0.90 so a low driven pass sheds pace naturally
## over turf (206 px/s^2 total decel incl. REST_DRAG_FLAT) instead of gliding
## on ice, opening a genuine window for a covering midfielder to intercept.
@export var pitch_friction: float = 0.94
## Air drag coefficient, applied per second while airborne.
## Calibration: raised from 0.08 so lofted balls settle into a believable
## descending arc rather than carrying at near-constant speed.
@export var air_resistance: float = 0.10
## 0 = dry, 1 = soaked. Scales the rolling friction coefficient down.
@export var surface_wetness: float = 0.0
## Bounce elasticity. 0.68 gives a lively but not rubbery ball.
@export var restitution: float = 0.68
## Vertical speed below which a bounce stops resolving and the ball settles.
@export var bounce_threshold: float = 40.0
## Horizontal energy kept through a bounce.
@export var bounce_friction_loss: float = 0.85
## Speed under which a rolling ball is treated as stationary.
@export var rest_speed: float = 4.0

## Scales pitch_friction into pixels/second of velocity shed per second.
const FRICTION_SCALE: float = 200.0
## Flat drag added on top of the proportional term so a nearly-stopped ball
## actually settles rather than asymptotically bleeding speed forever.
const REST_DRAG_FLAT: float = 18.0
## Shadow shrink/fade reference heights, in pixels.
const SHADOW_SCALE_REFERENCE: float = 300.0
const SHADOW_ALPHA_REFERENCE: float = 400.0
## Visual rolling radius used to integrate physical rotation per distance traveled.
const BALL_VISUAL_RADIUS: float = 4.0

var position_z: float = 0.0
var velocity_z: float = 0.0
var is_on_ground: bool = true
## One-off micro-impulse as the ball settles; reset on kick and restart.
var _drift_applied: bool = false
## Frozen balls ignore all integration — used for kickoffs, throw-ins and goals.
var is_frozen: bool = false

## 3D orientation basis updated continuously as the ball rolls and tumbles.
var _ball_basis: Basis = Basis.IDENTITY
## Aerial spin axis and angular speed imparted by kicks and deflections.
var _air_spin_axis: Vector3 = Vector3.UP
var _air_spin_speed: float = 0.0

## The player loosely controlling the ball, if any. Typed as Node2D rather than
## HeavyPlayerController so the ball stays independent of the player module.
var possessor: Node2D = null
## Set by whoever last struck the ball, via apply_kick()'s kicker argument. Used
## for assists/own-goal attribution and, by PitchBoundary, to tell a goal kick
## from a corner when the ball goes out over the end line.
var last_touched_by: HeavyPlayerController = null

## Taker who kicked/threw the dead ball restart. Used to prevent double-touch infractions.
var restart_taker: HeavyPlayerController = null
## False immediately after a dead ball restart; true once another player touches the ball.
var has_secondary_touch_occurred: bool = true

@onready var ball_sprite: Sprite2D = $BallSprite
@onready var shadow_sprite: Sprite2D = $ShadowSprite
@onready var ball_collider: CollisionShape2D = $CollisionShape2D
@onready var state_factory: BallStateFactory = $BallStateFactory


func _ready() -> void:
	collision_layer = CollisionLayers.LAYER_BALL_PHYSICS
	collision_mask = CollisionLayers.MASK_BALL_PHYSICS


func _physics_process(delta: float) -> void:
	if is_frozen:
		render_visuals()
		return

	state_factory.physics_update(delta)
	simulate_z_axis(delta)
	simulate_xy_axis(delta)

	var collision: KinematicCollision2D = move_with_rebound()
	if collision != null:
		# Walls and goal frames are the only things the ball can hit, so a
		# rebound is always a hard surface worth hearing.
		ball_bounced.emit(velocity.length())

	update_rolling_rotation(delta)
	render_visuals()


## Strikes the ball. `impulse_xy` is the ground vector in px/s, `impulse_z` the
## vertical launch speed (0.0 keeps it on the deck). `kicker` records the last
## touch for out-of-bounds attribution; pass null for a wall/scenery rebound.
func apply_kick(impulse_xy: Vector2, impulse_z: float, kicker: HeavyPlayerController = null) -> void:
	velocity = impulse_xy
	velocity_z = impulse_z
	if impulse_z > 0.0:
		is_on_ground = false
		_air_spin_speed = clampf(impulse_xy.length() * 0.025 + impulse_z * 0.035, 4.0, 20.0)
		var kick_len: float = impulse_xy.length()
		var kick_dir: Vector2 = impulse_xy / kick_len if kick_len > 0.001 else Vector2.RIGHT
		_air_spin_axis = Vector3(-kick_dir.y * 0.7 + randf_range(-0.3, 0.3), kick_dir.x * 0.7 + randf_range(-0.3, 0.3), randf_range(-0.6, 0.6)).normalized()
	else:
		_air_spin_speed = 0.0
	_drift_applied = false
	last_touched_by = kicker
	if kicker != null:
		register_player_touch(kicker)
	release_possession()
	ball_kicked.emit(impulse_xy, impulse_z)


## Adds to the current motion instead of replacing it — dribble touches and
## deflections, where the ball's existing momentum should still matter.
func apply_impulse(impulse_xy: Vector2, impulse_z: float = 0.0) -> void:
	velocity += impulse_xy
	velocity_z += impulse_z
	if velocity_z > 0.0:
		is_on_ground = false


func simulate_z_axis(delta: float) -> void:
	if is_on_ground and is_zero_approx(velocity_z):
		position_z = 0.0
		return

	var prev_vz: float = velocity_z
	velocity_z -= gravity * delta
	velocity_z -= velocity_z * air_resistance * delta
	position_z += (prev_vz + velocity_z) * 0.5 * delta

	if position_z > 0.0:
		is_on_ground = false
		return

	position_z = 0.0
	if absf(velocity_z) > bounce_threshold:
		velocity_z = -velocity_z * restitution
		velocity *= bounce_friction_loss
		is_on_ground = false
		_air_spin_speed *= 0.6
		ball_bounced.emit(absf(velocity_z))
	else:
		velocity_z = 0.0
		is_on_ground = true
		_air_spin_speed = 0.0


## Total ground deceleration in px/s^2 currently acting on a rolling ball:
##   pitch_friction * FRICTION_SCALE * (1 - wetness * 0.45) + REST_DRAG_FLAT
## At the default tuning (0.94 friction, dry pitch) this is 206 px/s^2. Exposed
## as one accessor because three call sites need it and one of them is outside
## this file: PlayerBrain solves its pass launch speed from the closed-form
## v0 = sqrt(2 * d * a) so a pass actually reaches its target, which only stays
## true if the AI reads the same deceleration the physics applies rather than a
## hardcoded copy that silently drifts when the pitch is retuned or wet.
func get_ground_deceleration() -> float:
	var effective_friction: float = pitch_friction * FRICTION_SCALE * (1.0 - surface_wetness * 0.45)
	return effective_friction + REST_DRAG_FLAT


func simulate_xy_axis(delta: float) -> void:
	if is_on_ground:
		var total_deceleration: float = get_ground_deceleration()
		velocity = velocity.move_toward(Vector2.ZERO, total_deceleration * delta)
		if velocity.length() < rest_speed and velocity.length() > 0.5 and not _drift_applied:
			velocity = velocity.rotated(randf_range(-0.18, 0.18)) * 0.7
			_drift_applied = true
		if velocity.length() < rest_speed:
			velocity = Vector2.ZERO
	else:
		velocity -= velocity * air_resistance * delta


## move_and_slide() would skid the ball along a wall; a football rebounds off it.
## Returns the collision that produced a rebound, or null.
func move_with_rebound() -> KinematicCollision2D:
	var collision: KinematicCollision2D = move_and_collide(velocity * get_physics_process_delta_time())
	if collision == null:
		return null
	velocity = velocity.bounce(collision.get_normal()) * restitution
	return collision


func update_rolling_rotation(delta: float) -> void:
	var speed_sq: float = velocity.length_squared()
	if is_on_ground:
		if speed_sq > 0.01:
			var speed: float = sqrt(speed_sq)
			var delta_rot: float = (speed * delta) / BALL_VISUAL_RADIUS
			var roll_axis: Vector3 = Vector3(-velocity.y / speed, velocity.x / speed, 0.0)
			_ball_basis = Basis(roll_axis, delta_rot) * _ball_basis
			_ball_basis = _ball_basis.orthonormalized()
	else:
		if _air_spin_speed > 0.01:
			_ball_basis = Basis(_air_spin_axis, _air_spin_speed * delta) * _ball_basis
			_air_spin_speed = move_toward(_air_spin_speed, 0.0, 0.5 * delta)
		if speed_sq > 1.0:
			var speed_xy: float = sqrt(speed_sq)
			var air_roll_speed: float = (speed_xy / BALL_VISUAL_RADIUS) * 0.45
			var air_axis: Vector3 = Vector3(-velocity.y / speed_xy, velocity.x / speed_xy, 0.0)
			_ball_basis = Basis(air_axis, air_roll_speed * delta) * _ball_basis
		_ball_basis = _ball_basis.orthonormalized()


func render_visuals() -> void:
	# Height lifts the sprite up the screen; the shadow marks the true ground
	# position so aerial balls stay readable.
	ball_sprite.position.y = -position_z

	var shadow_scale: float = clampf(1.0 - (position_z / SHADOW_SCALE_REFERENCE), 0.35, 1.0)
	shadow_sprite.scale = Vector2(shadow_scale, shadow_scale)
	shadow_sprite.modulate.a = clampf(0.8 - (position_z / SHADOW_ALPHA_REFERENCE), 0.2, 0.8)
	shadow_sprite.position = Vector2.ZERO

	var shader_mat: ShaderMaterial = ball_sprite.material as ShaderMaterial
	if shader_mat != null:
		shader_mat.set_shader_parameter(&"ball_rotation", _ball_basis)



## Discrete numerical integration of a prospective kick, for the aim preview arc.
## Returns screen-space points (ground position offset by height), matching how
## the ball sprite is actually rendered.
func predict_trajectory(impulse_xy: Vector2, impulse_z: float, steps: int = 25, dt: float = 0.05) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var sim_pos_xy: Vector2 = global_position
	var sim_vel_xy: Vector2 = impulse_xy
	var sim_pos_z: float = position_z
	var sim_vel_z: float = impulse_z
	var sim_grounded: bool = is_on_ground and is_zero_approx(impulse_z)
	var total_deceleration: float = get_ground_deceleration()

	for i: int in range(steps):
		if sim_grounded:
			sim_vel_xy = sim_vel_xy.move_toward(Vector2.ZERO, total_deceleration * dt)
			if sim_vel_xy.length() < rest_speed:
				sim_vel_xy = Vector2.ZERO
		else:
			sim_vel_xy -= sim_vel_xy * air_resistance * dt
			var prev_sim_vz: float = sim_vel_z
			sim_vel_z -= gravity * dt
			sim_vel_z -= sim_vel_z * air_resistance * dt
			sim_pos_z += (prev_sim_vz + sim_vel_z) * 0.5 * dt

			if sim_pos_z <= 0.0:
				sim_pos_z = 0.0
				if absf(sim_vel_z) > bounce_threshold:
					sim_vel_z = -sim_vel_z * restitution
					sim_vel_xy *= bounce_friction_loss
				else:
					sim_vel_z = 0.0
					sim_grounded = true

		sim_pos_xy += sim_vel_xy * dt
		points.append(sim_pos_xy + Vector2(0.0, -sim_pos_z))

	return points


func set_possessor(player: Node2D) -> void:
	if possessor == player:
		return
	possessor = player
	possession_changed.emit(player)


func release_possession() -> void:
	set_possessor(null)


## Tracks whether the dead-ball restart has not yet been struck for the first time.
var _is_first_touch_pending: bool = false


func is_airborne() -> bool:
	return position_z > 0.0 or not is_on_ground


## Places the ball for a restart and kills all motion.
func reset_at(spot: Vector2) -> void:
	global_position = spot
	velocity = Vector2.ZERO
	velocity_z = 0.0
	position_z = 0.0
	is_on_ground = true
	_drift_applied = false
	_air_spin_speed = 0.0
	release_possession()
	last_touched_by = null
	restart_taker = null
	has_secondary_touch_occurred = true
	_is_first_touch_pending = false
	render_visuals()


## Arms the anti-double-touch constraint for a set piece taker.
func mark_set_piece_restart(taker: HeavyPlayerController) -> void:
	restart_taker = taker
	has_secondary_touch_occurred = false
	_is_first_touch_pending = true


## Registers a player touch, returning false if this touch is an illegal double touch.
func register_player_touch(player: HeavyPlayerController) -> bool:
	if restart_taker != null:
		if _is_first_touch_pending and player == restart_taker:
			_is_first_touch_pending = false
			return true
		if not has_secondary_touch_occurred and player == restart_taker:
			return false
		has_secondary_touch_occurred = true
		_is_first_touch_pending = false
		restart_taker = null
	return true


## Whether a player is currently permitted to make contact with the ball.
func can_player_touch(player: HeavyPlayerController) -> bool:
	if restart_taker != null and player == restart_taker:
		if _is_first_touch_pending:
			return true
		if not has_secondary_touch_occurred:
			return false
	return true


func freeze() -> void:
	is_frozen = true
	velocity = Vector2.ZERO
	velocity_z = 0.0


func unfreeze() -> void:
	is_frozen = false
