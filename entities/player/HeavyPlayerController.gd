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
##   - GameEvents (autoload) for stamina_depleted broadcasts and
##     player_mood_changed, which triggers a movement curve recalculation
##   - MoodSystem, attached as a child by PlayerFactory, whose multipliers feed
##     into _recalculate_movement_curve()
##
## Exposes:
##   - apply_kinematic_weight(input_dir, delta)
##   - apply_external_impulse(impulse)   knockback from tackles and collisions
##   - get_ball_in_foot_range() / get_ball_in_aerial_range()
##   - get_mood()
##   - stamina, facing_direction, is_sprinting, movement_intent
##   - signal stamina_state_changed(ratio)
##   - world_index — this player's slot in MatchWorldModel, or -1 if unregistered
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
@export var top_speed: float = 240.0
## Seconds to reach top speed from a standstill, at the neutral 70kg reference
## mass. A 75kg player takes ~0.43s, a 90kg player ~0.52s — mass scales it.
@export var acceleration_time: float = 0.40
## Seconds to coast to a stop from top speed with no input, at the reference
## mass. Heavier players stop faster once they stop driving forward (~29px of
## roll-out at 75kg) but are slower to get going again.
@export var friction_time: float = 0.22
## 0.0 = turn on a dime, 1.0 = a full reversal kills all acceleration.
@export_range(0.0, 1.0) var turning_penalty_factor: float = 0.55
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

const ACTION_TEXT_SCENE: PackedScene = preload("res://ui/ActionText.tscn")
## Minimum seconds between action text spawns (prevents per-frame spam).
const ACTION_TEXT_COOLDOWN: float = 0.25

const NEUTRAL_MASS: float = 70.0
## Below this speed a turn costs nothing — you cannot "bleed momentum" you do
## not have, and applying the penalty at rest makes starting off feel mushy.
const TURN_EVAL_SPEED: float = 10.0
## Facing only updates above this speed, so a player coasting to a halt does not
## spin as the velocity vector decays into noise.
const FACING_UPDATE_SPEED: float = 15.0
## Floor on effective acceleration so a full 180 still eventually resolves.
const MIN_ACCELERATION_RATIO: float = 0.1

## This player's slot in MatchWorldModel, or -1 if registration was refused
## (roster already full).
var world_index: int = -1

var base_acceleration: float = 0.0
var base_friction: float = 0.0

var stamina: float = 0.0
var is_sprinting: bool = false
## Latched true when stamina hits zero; cleared at stamina_sprint_unlock.
var sprint_locked: bool = false

var facing_direction: Vector2 = Vector2.RIGHT
var _input_facing: Vector2 = Vector2.RIGHT
## The movement vector this player acted on last tick — human stick read or the
## brain's steering output. States and the HUD read this rather than Input.
var movement_intent: Vector2 = Vector2.ZERO

## Height above the turf, in pixels. Reserved for jumps/headers in Phase 2 of
## development; already wired into the sprite offset so aerial states can drive
## it without touching rendering code.
var current_z: float = 0.0

var _action_text_cooldown: float = 0.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var shadow: Sprite2D = $ShadowSprite2D
@onready var body_collider: CollisionShape2D = $CollisionShape2D
@onready var foot_sensor: Area2D = $FootSensor
@onready var aerial_hitbox: Area2D = $AerialHitbox
@onready var state_factory: PlayerStateFactory = $PlayerStateFactory
@onready var brain: PlayerBrain = $PlayerBrain
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var facing_arrow: FacingArrow = $FacingArrow


func _ready() -> void:
	# Last in the physics order: MatchWorldModel (-100) refreshes the spatial
	# cache, PlayerBrain (0) decides from it, and only then does the body move.
	process_priority = 100

	_register_with_world_model()
	_recalculate_movement_curve()
	_apply_collision_matrix()
	stamina = stamina_max
	stamina_state_changed.emit(1.0)
	GameEvents.player_mood_changed.connect(_on_player_mood_changed)


## Claims the next MatchWorldModel slot and tells this player's brain which
## index it was given, so the brain's frame-stagger and its world-model reads
## agree on who it is.
func _register_with_world_model() -> void:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		push_warning("HeavyPlayerController: MatchWorldModel autoload missing; %s is uncached." % name)
		return

	# Pass NO_INDEX to let MatchWorldModel own the slot counter entirely, so a
	# stale node re-registering during match teardown can't double-claim a slot.
	world_index = world.register_player(MatchWorldModel.NO_INDEX, self, team)

	if world_index >= 0 and has_node("PlayerBrain"):
		var player_brain := get_node("PlayerBrain") as PlayerBrain
		if player_brain != null:
			player_brain.player_index = world_index


func _physics_process(delta: float) -> void:
	movement_intent = _read_movement_intent()
	if movement_intent.length() > 0.01:
		_input_facing = movement_intent.normalized()
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
	if _action_text_cooldown > 0.0:
		_action_text_cooldown = maxf(0.0, _action_text_cooldown - delta)


## Recomputes the acceleration/friction constants from the exported tuning
## values. Call this after changing mass or speed at runtime (e.g. a fatigue or
## injury modifier) — nothing caches them elsewhere. Mood multipliers are folded
## in here too, so this is the only place mood ever touches the movement model.
func _recalculate_movement_curve() -> void:
	var mood_node: MoodSystem = get_mood()
	var speed_mult: float = mood_node.get_speed_multiplier() if mood_node != null else 1.0
	var accel_mult: float = mood_node.get_accel_multiplier() if mood_node != null else 1.0

	var effective_top_speed: float = top_speed * speed_mult
	var effective_accel_time: float = acceleration_time * accel_mult

	base_acceleration = (effective_top_speed / maxf(effective_accel_time, 0.01)) * (NEUTRAL_MASS / maxf(player_mass, 1.0))
	base_friction = (effective_top_speed / maxf(friction_time, 0.01)) * (maxf(player_mass, 1.0) / NEUTRAL_MASS)


## MoodSystem is attached dynamically by PlayerFactory rather than living in the
## scene, so it cannot be an @onready var — this looks it up lazily instead.
func get_mood() -> MoodSystem:
	return get_node_or_null("MoodSystem") as MoodSystem


func _on_player_mood_changed(player: Node, _tier: int) -> void:
	if player == self:
		_recalculate_movement_curve()


## Re-applies a different PlayerData onto this already-live controller for an
## in-match substitution. Unlike PlayerFactory.apply() (spawn time only) this
## never touches formation_anchor or FSM state — the incoming player picks up
## exactly wherever the outgoing one stood, in whatever FSM state it left
## behind; the state machine self-corrects on its next tick.
func apply_player_data(p: PlayerData, reset_stamina: bool = true) -> void:
	player_mass = p.mass
	top_speed = p.top_speed
	acceleration_time = p.acceleration_time
	friction_time = p.friction_time
	turning_penalty_factor = p.turning_penalty
	sprint_multiplier = p.sprint_multiplier
	stamina_max = p.stamina_max
	stamina_drain_rate = p.stamina_drain
	stamina_recover_rate = p.stamina_recover

	_recalculate_movement_curve()
	## When `false`, preserve current stamina and mood: use for stat
	## recalculations (e.g. a MoodSystem-driven stat change or a debug reload)
	## where the player is not actually being swapped. Pass `true` (the
	## default) only for a genuine substitution — the incoming player is fresh.
	if reset_stamina:
		stamina = stamina_max

	set_meta(&"player_data", p)

	# Mood belongs to the player, not the pitch slot — a substitute must not
	# inherit whatever SLUMP/STREAK the outgoing player had accumulated.
	if reset_stamina:
		var mood_node: MoodSystem = get_mood()
		if mood_node != null:
			mood_node.reset()

	if brain != null:
		brain.apply_player_data(p)


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


## Close-ball control attribute (0.0-1.0). Higher keeps the ball tighter while
## dribbling. Reads from the bound PlayerData, falling back to a neutral 0.65.
func get_close_control() -> float:
	var pd: PlayerData = get_meta(&"player_data", null) as PlayerData
	return pd.close_control if pd != null else 0.65


## 0.0-1.0 — how close this player is to their (possibly sprinting) top speed.
func get_speed_ratio() -> float:
	return clampf(velocity.length() / maxf(get_current_top_speed(), 1.0), 0.0, 1.0)


func get_stamina_ratio() -> float:
	return clampf(stamina / maxf(stamina_max, 1.0), 0.0, 1.0)


## World position of the kicking/controlling zone, a little ahead of the body.
func get_kick_origin() -> Vector2:
	return global_position + facing_direction * 10.0


## Returns how directly this player is facing toward a world-space point.
## Return value:
##   +1.0  perfectly facing the target
##    0.0  target is exactly 90° to the side
##   -1.0  target is directly behind
func get_facing_dot(target_world_pos: Vector2) -> float:
	var to_target: Vector2 = target_world_pos - global_position
	if to_target.is_zero_approx():
		return 1.0  # standing on the target — treat as facing
	return facing_direction.dot(to_target.normalized())


## Gate checked wherever ball possession is about to be granted (DribbleState,
## TackleState). Delegates to PlayerBrain.can_carry_ball(), which is false for
## a goalkeeper whose own goal line the ball has already crossed near — every
## other player is always eligible.
func can_carry_ball() -> bool:
	return brain == null or brain.can_carry_ball()


## Spawns floating action text in world space above this player.
## Added to the parent (not self) so the text does not rotate with the player.
func show_action_text(message: String) -> void:
	if message.is_empty() or _action_text_cooldown > 0.0:
		return
	var fx: ActionText = ACTION_TEXT_SCENE.instantiate() as ActionText
	if fx == null:
		return
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector2(0.0, -28.0)
	fx.show_text(message)
	_action_text_cooldown = ACTION_TEXT_COOLDOWN


## The ball currently inside the foot sensor, or null. Returns the candidate
## closest to this player so multi-ball overlaps resolve deterministically.
func get_ball_in_foot_range() -> Pseudo3DBall:
	return _nearest_ball_from(foot_sensor.get_overlapping_bodies())


func get_ball_in_aerial_range() -> Pseudo3DBall:
	return _nearest_ball_from(aerial_hitbox.get_overlapping_bodies())


## Collects every Pseudo3DBall among [bodies] and returns the one closest to this
## player's global_position. Physics reports overlaps in internal, frame-variable
## order, so iterating all candidates and comparing distance keeps selection
## deterministic and physically correct when two balls briefly overlap.
func _nearest_ball_from(bodies: Array) -> Pseudo3DBall:
	var nearest: Pseudo3DBall = null
	var nearest_distance_sq: float = INF
	for body: Node2D in bodies:
		var ball := body as Pseudo3DBall
		if ball == null:
			continue
		var distance_sq: float = global_position.distance_squared_to(ball.global_position)
		if distance_sq < nearest_distance_sq:
			nearest_distance_sq = distance_sq
			nearest = ball
	return nearest


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
	# Human player: face the input direction, not the lagging velocity vector.
	# CPU players keep the velocity-derived facing so their animations are truthful.
	if is_user_controlled and movement_intent.length() > 0.01:
		facing_direction = _input_facing
	if velocity.length() > FACING_UPDATE_SPEED:
		facing_direction = velocity.normalized()


func _update_visual_anchors() -> void:
	# Height reads as a vertical offset on the sprite; the shadow stays pinned to
	# the ground truth position. Same convention as Pseudo3DBall.
	sprite.position.y = -current_z
	sprite.rotation = facing_direction.angle()
	shadow.position = Vector2.ZERO
