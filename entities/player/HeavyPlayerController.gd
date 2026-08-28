##
## HeavyPlayerController
##
## The kinematic weight system: a CharacterBody2D that accelerates on a ramp,
## bleeds speed through turns, and never snaps to an input vector. This is the
## script that makes the game feel heavy — every other system is downstream of
## it.
##
## Movement model (per physics tick):
##   target_velocity  = input_direction * top_speed * stick_deflection
##   turn_severity    = 1.0 - clamp(velocity.normalized().dot(input_dir), 0, 1)
##   effective_accel  = base_acceleration * (1.0 - turning_penalty_factor * turn_severity)
##   velocity         = velocity.move_toward(target_velocity, effective_accel * delta)
##
## Depends on:
##   - InputHelper (autoload) for stick reads on the human-controlled player
##   - CollisionLayers for the matrix set up in _ready()
##   - GameEvents (autoload) for stamina_depleted broadcasts
##
## Exposes:
##   - apply_kinematic_weight(input_dir, delta)
##   - apply_external_impulse(impulse)   knockback from tackles and collisions
##   - get_ball_in_foot_range() / get_ball_in_aerial_range()
##   - stamina, facing_direction, is_sprinting, movement_intent
##   - signal stamina_state_changed(ratio)
##

class_name HeavyPlayerController
extends CharacterBody2D

signal stamina_state_changed(ratio: float)
signal possession_gained
signal possession_lost

## --- Physical identity -----------------------------------------------------

## Kilograms. Scales acceleration down and friction up: a 90kg centre-back
## takes longer to get going and is harder to shove off the ball than a 68kg
## winger. 70kg is the neutral reference mass.
@export var player_mass: float = 75.0
## Pixels per second at full left-stick deflection.
@export var top_speed: float = 210.0
## Seconds to reach top speed from a standstill, at the neutral 70kg reference
## mass. A 75kg player takes ~0.70s, a 90kg player ~0.84s — mass scales it.
@export var acceleration_time: float = 0.65
## Seconds to coast to a stop from top speed with no input, at the reference
## mass. Heavier players stop faster once they stop driving forward (~33px of
## roll-out at 75kg) but are slower to get going again.
@export var friction_time: float = 0.35
## 0.0 = turn on a dime, 1.0 = a full reversal kills all acceleration.
@export_range(0.0, 1.0) var turning_penalty_factor: float = 0.75
## Top-speed multiplier while action_sprint is held and stamina remains.
@export var sprint_multiplier: float = 1.45

## --- Stamina ---------------------------------------------------------------

@export var stamina_max: float = 100.0
@export var stamina_drain_rate: float = 18.0
@export var stamina_recover_rate: float = 9.0
## Stamina must climb back above this before sprint unlocks after exhaustion.
@export var stamina_sprint_unlock: float = 20.0

## --- Identity / control ----------------------------------------------------

@export var team: int = 0
## When true this player reads InputHelper; when false PlayerBrain drives it.
@export var is_user_controlled: bool = false
## Index into this player's team squad in DataLoader — which PlayerData
## PlayerFactory applies. PitchScene assigns this at bind time from each
## player's position in the $Players list, so scenes need no per-instance setup.
@export var squad_index: int = 0

const NEUTRAL_MASS: float = 70.0
## Below this speed a turn costs nothing — you cannot "bleed momentum" you do
## not have, and applying the penalty at rest makes starting off feel mushy.
const TURN_EVAL_SPEED: float = 10.0
## Facing only updates above this speed, so a player coasting to a halt does not
## spin as the velocity vector decays into noise.
const FACING_UPDATE_SPEED: float = 15.0
## Floor on effective acceleration so a full 180 still eventually resolves.
const MIN_ACCELERATION_RATIO: float = 0.1

var base_acceleration: float = 0.0
var base_friction: float = 0.0

var stamina: float = 0.0
var is_sprinting: bool = false
## Latched true when stamina hits zero; cleared at stamina_sprint_unlock.
var sprint_locked: bool = false

var facing_direction: Vector2 = Vector2.RIGHT
## The movement vector this player acted on last tick — human stick read or the
## brain's steering output. States and the HUD read this rather than Input.
var movement_intent: Vector2 = Vector2.ZERO

## Height above the turf, in pixels. Reserved for jumps/headers in Phase 2 of
## development; already wired into the sprite offset so aerial states can drive
## it without touching rendering code.
var current_z: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $ShadowSprite2D
@onready var body_collider: CollisionShape2D = $CollisionShape2D
@onready var foot_sensor: Area2D = $FootSensor
@onready var aerial_hitbox: Area2D = $AerialHitbox
@onready var state_factory: PlayerStateFactory = $PlayerStateFactory
@onready var brain: PlayerBrain = $PlayerBrain
@onready var stamina_bar: ProgressBar = $StaminaBar


func _ready() -> void:
	_recalculate_movement_curve()
	_apply_collision_matrix()
	stamina = stamina_max
	stamina_state_changed.emit(1.0)


func _physics_process(delta: float) -> void:
	movement_intent = _read_movement_intent()
	_update_sprint(delta)
	# The active state owns the movement model: MoveState applies the full weight
	# curve, DribbleState softens it, TackleState ignores input entirely. Driving
	# the FSM from here (rather than letting the factory run its own physics
	# callback) guarantees the state writes velocity in the same tick it is
	# consumed by move_and_slide, with no one-frame lag.
	state_factory.physics_update(delta)
	move_and_slide()
	_update_facing()
	_update_visual_anchors()


## Recomputes the acceleration/friction constants from the exported tuning
## values. Call this after changing mass or speed at runtime (e.g. a fatigue or
## injury modifier) — nothing caches them elsewhere.
func _recalculate_movement_curve() -> void:
	base_acceleration = (top_speed / maxf(acceleration_time, 0.01)) * (NEUTRAL_MASS / maxf(player_mass, 1.0))
	base_friction = (top_speed / maxf(friction_time, 0.01)) * (maxf(player_mass, 1.0) / NEUTRAL_MASS)


func _apply_collision_matrix() -> void:
	collision_layer = CollisionLayers.LAYER_PLAYER_BODIES
	collision_mask = CollisionLayers.MASK_PLAYER_BODIES

	foot_sensor.collision_layer = CollisionLayers.LAYER_FOOT_SENSOR
	foot_sensor.collision_mask = CollisionLayers.MASK_FOOT_SENSOR
	foot_sensor.monitorable = false

	aerial_hitbox.collision_layer = CollisionLayers.LAYER_AERIAL_HITBOX
	aerial_hitbox.collision_mask = CollisionLayers.MASK_AERIAL_HITBOX
	aerial_hitbox.monitorable = false


## THE weight function. `input_dir` may be shorter than one unit — its length is
## the stick deflection and scales the speed target directly, so a half-pushed
## stick yields roughly half pace instead of a digital snap to a full sprint.
func apply_kinematic_weight(input_dir: Vector2, delta: float) -> void:
	var deflection: float = clampf(input_dir.length(), 0.0, 1.0)

	if deflection <= 0.0:
		velocity = velocity.move_toward(Vector2.ZERO, base_friction * delta)
		return

	var direction: Vector2 = input_dir / deflection
	var target_velocity: Vector2 = direction * get_current_top_speed() * deflection

	# How far off the current heading is the requested one? 0.0 = straight
	# ahead, 1.0 = a full reversal. Below TURN_EVAL_SPEED there is no meaningful
	# heading to fight against.
	var turn_severity: float = 0.0
	if velocity.length() > TURN_EVAL_SPEED:
		turn_severity = 1.0 - clampf(velocity.normalized().dot(direction), 0.0, 1.0)

	var penalty: float = turning_penalty_factor * turn_severity
	var effective_acceleration: float = base_acceleration * maxf(1.0 - penalty, MIN_ACCELERATION_RATIO)

	# A sharp turn should bleed pace, not merely accelerate slowly. When the new
	# target is slower than the current speed, friction scaled by the turn
	# penalty takes over, so hard changes of direction cost real momentum while
	# a gentle curve costs almost nothing.
	var rate: float = effective_acceleration
	if target_velocity.length() < velocity.length():
		rate = maxf(effective_acceleration, base_friction * penalty)

	velocity = velocity.move_toward(target_velocity, rate * delta)


## Momentum transfer from tackles, shoulder contact and stumbles. Added raw so
## that a hit can genuinely knock a player off their line.
func apply_external_impulse(impulse: Vector2) -> void:
	velocity += impulse * (NEUTRAL_MASS / maxf(player_mass, 1.0))


func get_current_top_speed() -> float:
	return top_speed * (sprint_multiplier if is_sprinting else 1.0)


## 0.0-1.0 — how close this player is to their (possibly sprinting) top speed.
func get_speed_ratio() -> float:
	return clampf(velocity.length() / maxf(get_current_top_speed(), 1.0), 0.0, 1.0)


func get_stamina_ratio() -> float:
	return clampf(stamina / maxf(stamina_max, 1.0), 0.0, 1.0)


## World position of the kicking/controlling zone, a little ahead of the body.
func get_kick_origin() -> Vector2:
	return global_position + facing_direction * 10.0


## The ball currently inside the foot sensor, or null. Duck-typed lookups are
## avoided: the sensor only masks the ball layer, so anything it reports is one.
func get_ball_in_foot_range() -> Pseudo3DBall:
	for body: Node2D in foot_sensor.get_overlapping_bodies():
		var ball := body as Pseudo3DBall
		if ball != null:
			return ball
	return null


func get_ball_in_aerial_range() -> Pseudo3DBall:
	for body: Node2D in aerial_hitbox.get_overlapping_bodies():
		var ball := body as Pseudo3DBall
		if ball != null:
			return ball
	return null


func _read_movement_intent() -> Vector2:
	if is_user_controlled:
		return InputHelper.get_movement_vector()
	# CPU players: PlayerBrain writes into movement_intent each tick, so the
	# steering output simply carries over.
	return movement_intent


## Sprint is a held modifier, not a toggle, and it is gated on stamina: run the
## tank dry and the burst is locked out until it recovers past the unlock
## threshold. Only a human player reads the trigger here; the brain sets
## is_sprinting itself.
func _update_sprint(delta: float) -> void:
	var wants_sprint: bool = is_sprinting
	if is_user_controlled:
		wants_sprint = Input.is_action_pressed(&"action_sprint")

	var is_moving: bool = movement_intent.length() > 0.0
	is_sprinting = wants_sprint and is_moving and not sprint_locked

	var previous_ratio: float = get_stamina_ratio()

	if is_sprinting:
		stamina = maxf(stamina - stamina_drain_rate * delta, 0.0)
		if stamina <= 0.0 and not sprint_locked:
			sprint_locked = true
			is_sprinting = false
			GameEvents.stamina_depleted.emit(self)
	else:
		stamina = minf(stamina + stamina_recover_rate * delta, stamina_max)
		if sprint_locked and stamina >= stamina_sprint_unlock:
			sprint_locked = false

	var ratio: float = get_stamina_ratio()
	if not is_equal_approx(ratio, previous_ratio):
		stamina_state_changed.emit(ratio)


func _update_facing() -> void:
	if velocity.length() > FACING_UPDATE_SPEED:
		facing_direction = velocity.normalized()


func _update_visual_anchors() -> void:
	# Height reads as a vertical offset on the sprite; the shadow stays pinned to
	# the ground truth position. Same convention as Pseudo3DBall.
	sprite.position.y = -current_z
	sprite.rotation = facing_direction.angle()
	shadow.position = Vector2.ZERO
