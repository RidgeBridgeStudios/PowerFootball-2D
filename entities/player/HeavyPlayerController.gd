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
## Brain/controller contract: PlayerBrain (or human input, via InputHelper)
## expresses tactical intent through exactly three fields — movement_intent (a
## direction, magnitude 0-1 for stick deflection), wants_sprint (a desired
## speed scale) and wants_tackle (a desired tackle commit) — and never touches
## velocity, acceleration, is_sprinting, or the state machine directly. This
## controller owns turning penalties, acceleration/friction, stamina-gating of
## sprint, and all move_and_slide() integration. A bad tactical read (wrong
## pass target, wrong lane) should only ever surface as a mishit ball, never
## as broken player physics — the two concerns cannot corrupt each other
## because intent and integration are different fields owned by different
## scripts.
##
## Exposes:
##   - apply_kinematic_weight(input_dir, delta)
##   - apply_external_impulse(impulse)   knockback from tackles and collisions
##   - get_ball_in_foot_range() / get_ball_in_aerial_range()
##   - get_mood()
##   - get_trust_system()
##   - get_fatigue_tier() / get_stamina_ratio()
##   - stamina, facing_direction, is_sprinting, movement_intent, wants_sprint,
##     wants_tackle
##   - apply_injury(severity, injury_tag)   knock from a tackle or overexertion
##   - injury_severity                       0.0 clean .. 1.0 stretchered
##   - signal stamina_state_changed(ratio)
##   - world_index — this player's slot in MatchWorldModel, or -1 if unregistered
##
## Injury: apply_injury() is the sole writer of injury_severity (only ever
## rises within a match — see its doc comment). Above INJURY_LIMP_SEVERITY the
## player cannot sprint (_update_sprint()) or contest the air
## (get_ball_in_aerial_range()) — both hard gates live here, not in
## PlayerBrain, so no caller can bypass them by writing wants_sprint anyway.
## GameEvents.player_injured is emitted at INJURY_MINOR_SEVERITY and above for
## ManagerDirector (forced subs) and CareerManager (persistence) to react to.
##
## Fatigue: get_current_top_speed() scales both sprint and base top speed by
## FatigueTier (FRESH/TIRED/EXHAUSTED, from get_stamina_ratio()) so a tiring
## player visibly slows well before sprint_locked's hard zero-stamina cutoff,
## instead of running at full pace right up to the cliff edge.
##
## Contact: _resolve_sprint_jostle(), called once per physics tick right after
## move_and_slide(), reads that same call's slide collisions and exchanges a
## small continuous apply_external_impulse() push (not a direct velocity
## write) between two players who collide while both sprinting in roughly the
## same direction — a side-by-side shoulder duel, distinct from TackleState's
## one-shot lunge knockback.
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
## FM2D compromise: reduced to 0.22s for snappier burst while preserving mass-scaled inertia.
@export var acceleration_time: float = 0.22
## Seconds to coast to a stop from top speed with no input, at the reference
## mass. Heavier players stop faster once they stop driving forward (~29px of
## roll-out at 75kg) but are slower to get going again.
## FM2D compromise: reduced to 0.12s for crisper deceleration without feeling weightless.
@export var friction_time: float = 0.12
## 0.0 = turn on a dime, 1.0 = a full reversal kills all acceleration.
## FM2D compromise: reduced to 0.35 so turns feel responsive but committed reversals still bleed momentum.
@export_range(0.0, 1.0) var turning_penalty_factor: float = 0.35
## Top-speed multiplier while action_sprint is held and stamina remains.
@export var sprint_multiplier: float = 1.45

## --- Stamina ---------------------------------------------------------------

@export var stamina_max: float = 100.0
@export var stamina_drain_rate: float = 18.0
@export var stamina_recover_rate: float = 9.0
## Stamina must climb back above this before sprint unlocks after exhaustion.
@export var stamina_sprint_unlock: float = 20.0

## Three-tier metabolic model: get_current_top_speed() scales top speed by
## tier so speed degrades progressively as stamina drains, rather than
## holding full pace until sprint_locked's hard cutoff at zero. Ratio
## boundaries only — sprint_locked (zero stamina) still owns the hard floor.
enum FatigueTier { FRESH, TIRED, EXHAUSTED }
## Stamina ratio at/below which a player drops from FRESH to TIRED.
const FATIGUE_TIRED_RATIO: float = 0.6
## Stamina ratio at/below which a player drops from TIRED to EXHAUSTED.
const FATIGUE_EXHAUSTED_RATIO: float = 0.25
## Sprint top-speed multiplier per tier, applied on top of sprint_multiplier.
const FATIGUE_SPRINT_SCALE: Dictionary = {
	FatigueTier.FRESH: 1.0,
	FatigueTier.TIRED: 0.85,
	FatigueTier.EXHAUSTED: 0.65,
}
## Base (non-sprint) top-speed multiplier per tier — fatigue slows jogging
## too, just far less severely than it slows sprinting.
const FATIGUE_BASE_SCALE: Dictionary = {
	FatigueTier.FRESH: 1.0,
	FatigueTier.TIRED: 0.95,
	FatigueTier.EXHAUSTED: 0.85,
}

## --- Injury -----------------------------------------------------------------
## Severity bands for injury_severity below. Shared as the single source of
## truth across layers: ManagerDirector reads INJURY_FORCED_SUB_SEVERITY for
## the mandatory-sub gate, CareerManager buckets these same floats into
## PlayerCareerState.InjuryKind for persistence.
## KNOCK tier floor — below this a hard collision is a stumble, not an injury.
const INJURY_MINOR_SEVERITY: float = 0.1
## STRAIN tier floor. Above this a player cannot sprint (_update_sprint()) or
## contest the air (get_ball_in_aerial_range()).
const INJURY_LIMP_SEVERITY: float = 0.4
## MUSCLE_TEAR tier floor. ManagerDirector forces an immediate substitution.
const INJURY_FORCED_SUB_SEVERITY: float = 0.7
## LIGAMENT tier floor.
const INJURY_SEVERE_SEVERITY: float = 0.9
## Fully immobilised — stretchered off.
const INJURY_STRETCHER_SEVERITY: float = 1.0
## Absolute stamina below which a contact event's knock vulnerability rises —
## see apply_kinematic_weight()'s companion knock-risk call sites in
## TackleState._apply_tackle_injury_risk() and _apply_jostle_strain() below.
const INJURY_STAMINA_CRITICAL: float = 15.0

## --- Identity / control ----------------------------------------------------

@export var team: int = 0
## When true this player reads InputHelper; when false PlayerBrain drives it.
@export var is_user_controlled: bool = false
## Index into this player's team squad in DataLoader — which PlayerData
## PlayerFactory applies. PitchScene assigns this at bind time from each
## player's position in the $Players list, so scenes need no per-instance setup.
@export var squad_index: int = 0
## When true the shadow sprite rotates with facing_direction. Disable for
## circular shadow art, where per-frame rotation would be pointless.
@export var rotate_shadow: bool = true
## Role-specific tuning resource. Assign a .tres from res://shared/roles/
## in the Inspector or via ManagerDirector at spawn time.
## Consumed by PlayerBrain._find_open_space_target() (anchor_weight).
@export var role_config: PlayerRoleConfig

const ACTION_TEXT_SCENE: PackedScene = preload("res://ui/ActionText.tscn")
## Minimum seconds between action text spawns (prevents per-frame spam).
const ACTION_TEXT_COOLDOWN: float = 0.25

const NEUTRAL_MASS: float = 70.0
## Below this speed a turn costs nothing — you cannot "bleed momentum" you do
## not have, and applying the penalty at rest makes starting off feel mushy.
## FM2D compromise: lowered to 6.0 so turn momentum penalties engage earlier during lower-speed changes of direction.
const TURN_EVAL_SPEED: float = 6.0
## Facing only updates above this speed, so a player coasting to a halt does not
## spin as the velocity vector decays into noise.
const FACING_UPDATE_SPEED: float = 15.0
## Floor on effective acceleration so a full 180 still eventually resolves.
## FM2D compromise: raised to 0.18 to prevent prolonged dead-stops on reversals while keeping defenders favored on anticipated cuts.
const MIN_ACCELERATION_RATIO: float = 0.18

## This player's slot in MatchWorldModel, or -1 if registration was refused
## (roster already full).
var world_index: int = -1

var base_acceleration: float = 0.0
var base_friction: float = 0.0

var stamina: float = 0.0
## Resolved, gated sprint state actually applied to top speed this frame.
## Never written from outside _update_sprint() — it is the OUTPUT of resolving
## wants_sprint against stamina/sprint_locked, not an input. PlayerBrain
## expresses sprint intent through wants_sprint instead.
var is_sprinting: bool = false
## Desired sprint state as expressed by the input source: human input for a
## user-controlled player (polled directly in _update_sprint()), PlayerBrain's
## tactical intent for a CPU one. This is the controller's one extra intent
## channel beyond movement_intent — only the controller knows whether stamina
## actually allows the sprint, so the brain requests it here rather than
## asserting the resolved is_sprinting itself.
var wants_sprint: bool = false
## Latched true when stamina hits zero; cleared at stamina_sprint_unlock.
var sprint_locked: bool = false
## Desired tackle-commit state, expressed the same way as wants_sprint: human
## input reads action_tackle directly (PlayerState.wants()); CPU intent is
## pre-written here each physics tick by PlayerBrain
## (PlayerBrain._should_attempt_tackle(), called from _steer_for_action()).
## PlayerState.check_common_transitions() ORs this in alongside the human
## action_tackle read as the sole gate into TackleState. Always false for a
## user-controlled player — PlayerBrain._physics_process() bails out
## immediately for one (see is_user_controlled) — so this can never fight a
## human's own tackle input.
var wants_tackle: bool = false

## Current physical knock state: 0.0 (clean) .. 1.0 (stretchered). Persists for
## the rest of the match once set — there is no in-match healing, only
## inter-match recovery via the career layer (PlayerCareerState.tick_recovery()).
## Set exclusively through apply_injury(); never assign directly.
var injury_severity: float = 0.0
## Turn severity ([0,1], 90°=0.5/180°=1.0) from this tick's apply_kinematic_weight()
## call. Read by TackleState's injury-risk calculator as a knock-vulnerability
## factor — a player caught mid-reversal absorbs a challenge worse than one
## running straight. Not consumed by PlayerBrain.
var last_turn_severity: float = 0.0

var facing_direction: Vector2 = Vector2.RIGHT
var _input_facing: Vector2 = Vector2.RIGHT
## The movement vector this player acted on last tick — human stick read or the
## brain's steering output. States and the HUD read this rather than Input.
var movement_intent: Vector2 = Vector2.ZERO

## Height above the turf, in pixels. Reserved for jumps/headers in Phase 2 of
## development; already wired into the sprite offset so aerial states can drive
## it without touching rendering code.
var current_z: float = 0.0

## Maximum pseudo-3D height (px) at which a ball can be controlled by ground feet.
const MAX_CAPTURE_HEIGHT: float = 25.0
## Maximum reach (radius & height) for a goalkeeper catching the ball with hands.
const GOALKEEPER_CATCH_RADIUS: float = 34.0
const GOALKEEPER_CATCH_MAX_HEIGHT: float = 65.0
## Duration of foot-sensor lockout after striking or losing the ball.
var ball_control_lockout: float = 0.0

var _action_text_cooldown: float = 0.0
var _sprint_text_cooldown: float = 0.0
var _jostle_text_cooldown: float = 0.0
var _jockey_text_cooldown: float = 0.0
var _fatigue_text_cooldown: float = 0.0
var _was_sprinting: bool = false

@onready var visual: PlayerVisual = $PlayerVisual if has_node("PlayerVisual") else null
@onready var sprite: Sprite2D = $Sprite2D if has_node("Sprite2D") else ($PlayerVisual/DotSprite if has_node("PlayerVisual/DotSprite") else null)
@onready var shadow: Sprite2D = $ShadowSprite2D if has_node("ShadowSprite2D") else ($PlayerVisual/ShadowSprite if has_node("PlayerVisual/ShadowSprite") else null)
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
	_setup_stamina_bar()
	stamina = stamina_max
	stamina_state_changed.emit(1.0)
	GameEvents.player_mood_changed.connect(_on_player_mood_changed)

	if visual != null:
		var team_data: TeamData = DataLoader.get_match_team(team) if DataLoader.league != null else null
		var p_data: PlayerData = get_meta(&"player_data") as PlayerData if has_meta(&"player_data") else null
		var is_gk: bool = brain != null and brain.is_goalkeeper
		visual.apply_data(p_data, team_data, is_gk)


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
	_resolve_sprint_jostle(delta)
	_update_facing()
	_update_visual_anchors()
	if _action_text_cooldown > 0.0:
		_action_text_cooldown = maxf(0.0, _action_text_cooldown - delta)
	if _sprint_text_cooldown > 0.0:
		_sprint_text_cooldown = maxf(0.0, _sprint_text_cooldown - delta)
	if _jostle_text_cooldown > 0.0:
		_jostle_text_cooldown = maxf(0.0, _jostle_text_cooldown - delta)
	if _jockey_text_cooldown > 0.0:
		_jockey_text_cooldown = maxf(0.0, _jockey_text_cooldown - delta)
	if _fatigue_text_cooldown > 0.0:
		_fatigue_text_cooldown = maxf(0.0, _fatigue_text_cooldown - delta)
	if ball_control_lockout > 0.0:
		ball_control_lockout = maxf(0.0, ball_control_lockout - delta)


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


## TrustSystem is attached dynamically by PlayerFactory (same reasoning as
## get_mood() above) — this player's own memory of how much it trusts each
## teammate as a pass target.
func get_trust_system() -> TrustSystem:
	return get_node_or_null("TrustSystem") as TrustSystem


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
		var trust_node: TrustSystem = get_trust_system()
		if trust_node != null:
			trust_node.reset()

	if brain != null:
		brain.apply_player_data(p)

	if visual != null:
		var team_data: TeamData = DataLoader.get_match_team(team) if DataLoader.league != null else null
		var is_gk: bool = brain != null and brain.is_goalkeeper
		visual.apply_data(p, team_data, is_gk)


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
	var current_speed: float = velocity.length()

	# How far off the current heading is the requested one? 0.0 = straight
	# ahead, 1.0 = a full reversal. Below TURN_EVAL_SPEED there is no meaningful
	# heading to fight against.
	var turn_severity: float = 0.0
	var dot_heading: float = 1.0
	if current_speed > TURN_EVAL_SPEED:
		dot_heading = velocity.normalized().dot(direction)
		# Map cosine from [-1.0, 1.0] smoothly to [1.0, 0.0] severity:
		# 0° (dot=1.0) -> 0.0, 90° (dot=0.0) -> 0.5, 180° (dot=-1.0) -> 1.0
		turn_severity = clampf((1.0 - dot_heading) * 0.5, 0.0, 1.0)
	last_turn_severity = turn_severity

	var penalty: float = turning_penalty_factor * turn_severity
	var effective_acceleration: float = base_acceleration * maxf(1.0 - penalty, MIN_ACCELERATION_RATIO)

	# A sharp turn or reversal should bleed pace, not merely accelerate slowly. When the new
	# target is slower than the current speed OR the player is cutting back against heading,
	# friction scaled by the turn penalty takes over.
	var rate: float = effective_acceleration
	if target_velocity.length() < current_speed or (current_speed > TURN_EVAL_SPEED and dot_heading < 0.0):
		var brake_friction: float = base_friction * maxf(penalty, 0.5)
		rate = maxf(effective_acceleration, brake_friction)

	velocity = velocity.move_toward(target_velocity, rate * delta)


## Momentum transfer from tackles, shoulder contact and stumbles. Added raw so
## that a hit can genuinely knock a player off their line.
func apply_external_impulse(impulse: Vector2) -> void:
	velocity += impulse * (NEUTRAL_MASS / maxf(player_mass, 1.0))


## Applies a knock. injury_severity only ever rises within a match — a second,
## lesser knock (e.g. a jostle strain after an already-registered tackle
## impact) is a no-op, mirroring how a real injury compounds rather than
## resets. Emits GameEvents.player_injured once per event at
## INJURY_MINOR_SEVERITY and above so ManagerDirector (forced subs) and
## CareerManager (persistence) can react; anything below that floor still
## nudges mood but is treated as a stumble, not a logged injury.
func apply_injury(severity: float, injury_tag: StringName) -> void:
	var clamped: float = clampf(severity, 0.0, 1.0)
	if clamped <= injury_severity:
		return
	injury_severity = clamped

	var mood_node: MoodSystem = get_mood()
	if mood_node != null:
		# Frustration/fear scales with how bad the knock is — a severe one
		# alone can tip a NORMAL player straight into SLUMP (threshold 0.33)
		# and, via MoodSystem's existing tier-based scatter multiplier,
		# widens kick dispersion the same way any other SLUMP does.
		mood_node.apply_delta(-clamped * 0.30)

	if clamped < INJURY_MINOR_SEVERITY:
		return

	if clamped >= INJURY_STRETCHER_SEVERITY:
		show_action_text("STRETCHERED OFF", Color(1.0, 0.15, 0.15))
	elif clamped >= INJURY_FORCED_SUB_SEVERITY:
		show_action_text("INJURED!", Color(1.0, 0.35, 0.20))
	else:
		show_action_text("KNOCK", Color(1.0, 0.65, 0.30))

	GameEvents.player_injured.emit(self, injury_severity, injury_tag)


## --- Contact / jostling -----------------------------------------------------

## Cosine of the max heading misalignment for a shoulder-to-shoulder jostle —
## 0.70 ≈ cos(45°), so this is the same "within ~45° of each other" test
## expressed as a dot product: two players running roughly the same direction.
## A larger misalignment reads as a crossing run or a tackle, not a side-by-
## side duel, and is left to plain move_and_slide separation.
const JOSTLE_HEADING_DOT_MIN: float = 0.70
## Both players must be moving at least this fast (px/s) for contact to read
## as a sprinting duel rather than incidental jogging contact.
const JOSTLE_MIN_SPEED: float = 100.0
## Continuous push-apart strength (px/s, scaled by delta below) while two
## sprinting players stay in contact — a per-frame nudge, not a one-shot
## knockback like TackleState's lunge.
const JOSTLE_IMPULSE_PER_SECOND: float = 90.0


## Reads this tick's move_and_slide() collisions (must run right after it) and
## exchanges a small apply_external_impulse() push between self and any other
## HeavyPlayerController both sprinting in roughly the same direction — see
## JOSTLE_HEADING_DOT_MIN. Only the lower instance ID of the pair computes and
## applies the exchange, so both bodies do not each push the other every
## frame and double the effect.
func _resolve_sprint_jostle(delta: float) -> void:
	for i: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		var other: HeavyPlayerController = collision.get_collider() as HeavyPlayerController
		if other == null or get_instance_id() >= other.get_instance_id():
			continue

		if velocity.length() < JOSTLE_MIN_SPEED or other.velocity.length() < JOSTLE_MIN_SPEED:
			continue

		var heading_dot: float = velocity.normalized().dot(other.velocity.normalized())
		if heading_dot < JOSTLE_HEADING_DOT_MIN:
			continue

		# get_normal() points away from the collision surface, back toward
		# self — i.e. the direction self should be nudged to separate.
		var push: Vector2 = collision.get_normal() * JOSTLE_IMPULSE_PER_SECOND * delta
		apply_external_impulse(push)
		other.apply_external_impulse(-push)
		_apply_jostle_strain()
		other._apply_jostle_strain()

		show_action_text("SHOULDER", Color(1.0, 0.84, 0.25))
		other.show_action_text("SHOULDER", Color(1.0, 0.84, 0.25))


## Self-inflicted overexertion knock: a shoulder duel taken on empty legs
## (stamina below INJURY_STAMINA_CRITICAL) can pull something even without a
## foul. Deliberately capped low (<= 0.22, well under INJURY_LIMP_SEVERITY) —
## jostle strain is a minor knock, never the source of a forced substitution;
## only a tackle-impact foul (TackleState._apply_tackle_injury_risk()) can
## produce a knock severe enough for that.
func _apply_jostle_strain() -> void:
	if stamina >= INJURY_STAMINA_CRITICAL:
		return
	var fatigue_ratio: float = 1.0 - clampf(stamina / INJURY_STAMINA_CRITICAL, 0.0, 1.0)
	var severity: float = fatigue_ratio * 0.22
	if severity >= INJURY_MINOR_SEVERITY:
		apply_injury(severity, &"exertion_strain")


## Halts all momentum immediately (used during dead-ball / set-piece freezes).
func freeze_momentum() -> void:
	velocity = Vector2.ZERO
	movement_intent = Vector2.ZERO
	is_sprinting = false


func get_current_top_speed() -> float:
	var tier: FatigueTier = get_fatigue_tier()
	if is_sprinting:
		return top_speed * sprint_multiplier * float(FATIGUE_SPRINT_SCALE.get(tier, 1.0))
	return top_speed * float(FATIGUE_BASE_SCALE.get(tier, 1.0))


## Three-tier read of get_stamina_ratio() — FRESH above FATIGUE_TIRED_RATIO,
## EXHAUSTED at/below FATIGUE_EXHAUSTED_RATIO, TIRED between the two.
func get_fatigue_tier() -> FatigueTier:
	var ratio: float = get_stamina_ratio()
	if ratio <= FATIGUE_EXHAUSTED_RATIO:
		return FatigueTier.EXHAUSTED
	if ratio <= FATIGUE_TIRED_RATIO:
		return FatigueTier.TIRED
	return FatigueTier.FRESH


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


## Returns this player's anchor_weight from role_config, or -1.0 if no
## config is assigned. A return of -1.0 means the caller's own fallback
## applies. anchor_weight is 1.0 = rigid / 0.0 = free roam — convert with
## (1.0 - anchor_weight) before using it as a roam-weighted alpha.
## PlayerBrain._evaluate_off_ball_target() reads role_config directly to
## stay allocation-free on the decision path.
func get_role_alpha() -> float:
	if role_config != null:
		return role_config.anchor_weight
	push_warning(
		"PlayerRoleConfig not assigned on %s — using inline fallback." % name
	)
	return -1.0


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


## Returns whether this player is actively holding the ball in hands (GoalkeeperHoldState).
func is_holding_ball() -> bool:
	return state_factory != null and state_factory.current_state_name == PlayerState.GOALKEEPER_HOLD


## Gate checked before a grounded foot capture is granted.
func can_capture_ball(ball: Pseudo3DBall) -> bool:
	if ball == null or ball.is_frozen:
		return false
	if ball.possessor != null and ball.possessor is HeavyPlayerController:
		var carrier := ball.possessor as HeavyPlayerController
		if carrier != self and carrier.is_holding_ball():
			return false
	if ball_control_lockout > 0.0:
		return false
	if ball.position_z > MAX_CAPTURE_HEIGHT:
		return false
	if not ball.can_player_touch(self):
		return false
	return can_carry_ball()


## Evaluates whether the match ball is within hand-catching reach for this goalkeeper.
## Only valid for a goalkeeper inside their defending penalty area, and disallows intentional
## back-passes kicked by a teammate.
func get_ball_in_catch_range() -> Pseudo3DBall:
	if brain == null or not brain.is_goalkeeper:
		return null
	if ball_control_lockout > 0.0:
		return null
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or world.ball_node == null:
		return null
	var match_ball: Pseudo3DBall = world.ball_node
	if not is_instance_valid(match_ball) or match_ball.is_frozen:
		return null
	if match_ball.position_z > GOALKEEPER_CATCH_MAX_HEIGHT:
		return null

	var boundary: PitchBoundary = brain.pitch_boundary if brain != null else null
	if boundary == null and get_parent() != null and get_parent().has_node("PitchBoundary"):
		boundary = get_parent().get_node("PitchBoundary") as PitchBoundary
	if boundary == null or not boundary.is_in_penalty_area(global_position, team):
		return null

	if match_ball.last_touched_by != null and match_ball.last_touched_by != self \
			and match_ball.last_touched_by.team == team and not match_ball.is_airborne():
		return null

	var dist_sq: float = global_position.distance_squared_to(match_ball.global_position)
	if dist_sq <= GOALKEEPER_CATCH_RADIUS * GOALKEEPER_CATCH_RADIUS:
		return match_ball

	return null


## Spawns floating action text in world space above this player.
## Added to the parent (not self) so the text does not rotate with the player.
func show_action_text(message: String, color: Color = Color.WHITE) -> void:
	if message.is_empty():
		return
	if message == "SPRINT" or message == "RUN":
		if _sprint_text_cooldown > 0.0:
			return
		_sprint_text_cooldown = 2.0
	elif message == "SHOULDER" or message == "DUEL":
		if _jostle_text_cooldown > 0.0:
			return
		_jostle_text_cooldown = 1.2
	elif message == "JOCKEY" or message == "CONTAIN":
		if _jockey_text_cooldown > 0.0:
			return
		_jockey_text_cooldown = 1.8
	elif message == "TIRED" or message == "EXHAUSTED!":
		if _fatigue_text_cooldown > 0.0:
			return
		_fatigue_text_cooldown = 4.0
	else:
		if _action_text_cooldown > 0.0:
			return
		_action_text_cooldown = ACTION_TEXT_COOLDOWN

	var fx: ActionText = ACTION_TEXT_SCENE.instantiate() as ActionText
	if fx == null:
		return
	get_parent().add_child(fx)
	fx.global_position = global_position + Vector2(0.0, -28.0)
	fx.show_text(message, color)


func _setup_stamina_bar() -> void:
	if stamina_bar == null:
		return
	stamina_bar.offset_left = -13.0
	stamina_bar.offset_right = 13.0
	stamina_bar.offset_top = 13.0
	stamina_bar.offset_bottom = 16.5
	stamina_bar.max_value = 1.0
	stamina_bar.step = 0.005
	stamina_bar.value = 1.0
	stamina_bar.show_percentage = false
	stamina_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.04, 0.04, 0.06, 0.70)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	bg_style.border_width_left = 1
	bg_style.border_width_top = 1
	bg_style.border_width_right = 1
	bg_style.border_width_bottom = 1
	bg_style.border_color = Color(0.15, 0.15, 0.20, 0.6)
	stamina_bar.add_theme_stylebox_override("background", bg_style)

	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(1.0, 1.0, 1.0, 1.0)
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	stamina_bar.add_theme_stylebox_override("fill", fill_style)


func _update_stamina_bar_display(ratio: float) -> void:
	if stamina_bar == null:
		return
	stamina_bar.value = ratio

	var tier: FatigueTier = get_fatigue_tier()
	var bar_color: Color
	if sprint_locked or tier == FatigueTier.EXHAUSTED:
		bar_color = Color(0.95, 0.25, 0.25)
	elif tier == FatigueTier.TIRED:
		bar_color = Color(1.0, 0.75, 0.15)
	else:
		bar_color = Color(0.24, 0.86, 0.41)

	stamina_bar.modulate = bar_color

	var is_sim: bool = GameManager.get_meta(&"simulate_match", false)
	var show_all: bool = GameManager.get_meta(&"stamina_bars_always_visible", false)
	if is_user_controlled or is_sim or show_all:
		stamina_bar.visible = true
	else:
		stamina_bar.visible = ratio < 0.98 or sprint_locked or is_sprinting


## The ball currently inside the foot sensor, or null. Returns the candidate
## closest to this player so multi-ball overlaps resolve deterministically.
func get_ball_in_foot_range() -> Pseudo3DBall:
	if ball_control_lockout > 0.0:
		return null
	return _nearest_ball_from(foot_sensor.get_overlapping_bodies(), true)


func get_ball_in_aerial_range() -> Pseudo3DBall:
	# Limping gate: a player past INJURY_LIMP_SEVERITY cannot contest the air —
	# see apply_injury()'s doc comment. AerialState reads this sensor to enter,
	# so returning null here is a hard block, not just a lower score.
	if injury_severity > INJURY_LIMP_SEVERITY:
		return null
	return _nearest_ball_from(aerial_hitbox.get_overlapping_bodies(), false)


## Collects every Pseudo3DBall among [bodies] and returns the one closest to this
## player's global_position. Physics reports overlaps in internal, frame-variable
## order, so iterating all candidates and comparing distance keeps selection
## deterministic and physically correct when two balls briefly overlap.
func _nearest_ball_from(bodies: Array, ground_check: bool = false) -> Pseudo3DBall:
	var nearest: Pseudo3DBall = null
	var nearest_distance_sq: float = INF
	for body: Node2D in bodies:
		var ball := body as Pseudo3DBall
		if ball == null:
			continue
		if ground_check and not can_capture_ball(ball):
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
## threshold. A human player's intent is polled directly from Input here; a
## CPU player's intent arrives pre-written on wants_sprint by PlayerBrain.
## Either way, this function alone resolves that intent into the gated
## is_sprinting — the one place that decides whether the sprint actually happens.
func _update_sprint(delta: float) -> void:
	if is_user_controlled:
		wants_sprint = Input.is_action_pressed(&"action_sprint")

	var is_moving: bool = movement_intent.length() > 0.0
	var was_sprinting: bool = is_sprinting
	# Limping gate: this is the sole authoritative block on sprint for an
	# injured player, regardless of how many PlayerBrain call sites still
	# request wants_sprint = true — see apply_injury()'s doc comment.
	is_sprinting = wants_sprint and is_moving and not sprint_locked \
		and injury_severity <= INJURY_LIMP_SEVERITY

	if not was_sprinting and is_sprinting and velocity.length() > 110.0:
		show_action_text("SPRINT", Color(0.33, 0.95, 0.55))
	_was_sprinting = is_sprinting

	var previous_tier: FatigueTier = get_fatigue_tier()
	var previous_ratio: float = get_stamina_ratio()
	var time_dilation_scale: float = GameManager.get_time_scale() / (GameManager.SIMULATED_HALF_DURATION / GameManager.BASE_HALF_DURATION_REAL_SEC)

	if is_sprinting:
		stamina = maxf(stamina - stamina_drain_rate * time_dilation_scale * delta, 0.0)
		if stamina <= 0.0 and not sprint_locked:
			sprint_locked = true
			is_sprinting = false
			GameEvents.stamina_depleted.emit(self)
			show_action_text("EXHAUSTED!", Color(1.0, 0.25, 0.25))
	else:
		stamina = minf(stamina + stamina_recover_rate * time_dilation_scale * delta, stamina_max)
		if sprint_locked and stamina >= stamina_sprint_unlock:
			sprint_locked = false

	var current_tier: FatigueTier = get_fatigue_tier()
	if current_tier != previous_tier:
		if current_tier == FatigueTier.TIRED and previous_tier == FatigueTier.FRESH:
			show_action_text("TIRED", Color(1.0, 0.72, 0.20))
		elif current_tier == FatigueTier.EXHAUSTED and previous_tier != FatigueTier.EXHAUSTED:
			show_action_text("EXHAUSTED!", Color(1.0, 0.25, 0.25))

	var ratio: float = get_stamina_ratio()
	if not is_equal_approx(ratio, previous_ratio):
		stamina_state_changed.emit(ratio)

	_update_stamina_bar_display(ratio)


func _update_facing() -> void:
	# Human player: face the input direction, not the lagging velocity vector.
	if is_user_controlled and movement_intent.length() > 0.01:
		facing_direction = _input_facing
		return

	# If carrying the ball, face movement velocity or input intent.
	var is_possessor: bool = brain != null and brain.ball != null and brain.ball.possessor == self
	if is_possessor:
		if velocity.length() > FACING_UPDATE_SPEED:
			facing_direction = velocity.normalized()
		elif movement_intent.length() > 0.01:
			facing_direction = movement_intent.normalized()
		return

	# High-speed sprint off-ball (breakaway run or recovery sprint): face velocity
	if is_sprinting and velocity.length() > 150.0:
		facing_direction = velocity.normalized()
		return

	# Off-ball positioning, jogging, jockeying, or holding shape:
	# Orient toward the ball (open body shape) so players watch the play.
	var ball_pos: Vector2 = Vector2.ZERO
	var has_ball: bool = false
	if brain != null and brain.ball != null:
		ball_pos = brain.ball.global_position
		has_ball = true
	elif MatchWorldModel.instance != null and MatchWorldModel.instance.ball_node != null:
		ball_pos = MatchWorldModel.instance.ball_position
		has_ball = true

	if has_ball:
		var to_ball: Vector2 = ball_pos - global_position
		if to_ball.length_squared() > 100.0:
			var ball_facing: Vector2 = to_ball.normalized()
			if velocity.length() > FACING_UPDATE_SPEED:
				# Moving: blend 65% toward ball + 35% toward movement direction
				facing_direction = (ball_facing * 0.65 + velocity.normalized() * 0.35).normalized()
			else:
				# Stationary / settled at anchor: face the ball directly
				facing_direction = ball_facing
			return

	if velocity.length() > FACING_UPDATE_SPEED:
		facing_direction = velocity.normalized()


func _update_visual_anchors() -> void:
	var in_possession: bool = brain != null and brain.ball != null and brain.ball.possessor == self
	if visual != null:
		visual.sync_physics(facing_direction, current_z, is_user_controlled, in_possession)
	elif sprite != null:
		sprite.position.y = -current_z
		sprite.rotation = facing_direction.angle()
		if shadow != null:
			if rotate_shadow:
				shadow.rotation = facing_direction.angle()
			shadow.position = Vector2.ZERO
