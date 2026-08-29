##
## PlayerBrain
##
## CPU decision matrix. Instead of a static if-else ladder, the brain builds a
## contextual vector (pressure, distance to ball, stamina) and passes it through
## personality biases — vision, composure, aggression — so two defenders with
## different attributes read the same situation differently, and a tired player
## under a heavy press makes unforced errors.
##
## The brain writes steering into HeavyPlayerController.movement_intent; it never
## touches velocity directly, so CPU players are bound by exactly the same weight
## model as the human one.
##
## Depends on: Pseudo3DBall, HeavyPlayerController (as parent node), MoodSystem
## (read via player.get_mood() to bias vision/composure/aggression at the
## decision site — mood never touches the exported attributes themselves),
## PitchBoundary (bound via bind_boundary(), used for goalkeeper positioning).
## Exposes: evaluate_tactical_action(), calculate_pressure_index(), ball
##

class_name PlayerBrain
extends Node

## Awareness of teammates and passing lanes.
@export_range(0.0, 1.0) var vision_attribute: float = 0.75
## Resistance to panicking under pressure.
@export_range(0.0, 1.0) var composure_attribute: float = 0.60
## Willingness to dive into tackles and shoot from distance.
@export_range(0.0, 1.0) var aggression_attribute: float = 0.80
## Base position this player holds when the ball is elsewhere, in world space.
@export var formation_anchor: Vector2 = Vector2.ZERO
## How far the anchor drifts toward the ball, 0.0-1.0 (team compactness).
@export_range(0.0, 1.0) var formation_ball_weight: float = 0.35
## Seconds between decision re-evaluations. Human-scale latency, and cheap.
@export var decision_interval: float = 0.25
## True for the goalkeeper — swaps evaluate_tactical_action() for a simple
## stay-near-goal/chase-goal-area rule instead of the outfield decision tree.
@export var is_goalkeeper: bool = false

## Radius inside which an opponent contributes to the pressure index.
const PRESSURE_RADIUS: float = 180.0
## Distance at which the brain commits to chasing the ball rather than holding shape.
const CHASE_RADIUS: float = 220.0
## Arrival radius — inside this the player eases off instead of oscillating.
const ARRIVE_RADIUS: float = 24.0
## How close the ball must be to the keeper's own goal centre before they chase it.
const GOALKEEPER_CHASE_RADIUS: float = 200.0

var player: HeavyPlayerController = null
var ball: Pseudo3DBall = null
var pitch_boundary: PitchBoundary = null
var current_action: StringName = &"MaintainFormation"

var _decision_cooldown: float = 0.0


func _ready() -> void:
	player = get_parent() as HeavyPlayerController
	if formation_anchor == Vector2.ZERO and player != null:
		formation_anchor = player.global_position


## The pitch calls this after spawning so the brain knows which ball to track.
func bind_ball(match_ball: Pseudo3DBall) -> void:
	ball = match_ball


## The pitch calls this after spawning so a goalkeeper's brain can measure
## distance to its own goal centre.
func bind_boundary(b: PitchBoundary) -> void:
	pitch_boundary = b


func _physics_process(delta: float) -> void:
	if player == null or ball == null or player.is_user_controlled:
		return
	if not GameManager.is_in_play():
		player.movement_intent = Vector2.ZERO
		return

	_decision_cooldown -= delta
	if _decision_cooldown <= 0.0:
		_decision_cooldown = decision_interval
		current_action = evaluate_tactical_action(_find_nearby_opponents())

	player.movement_intent = _steer_for_action()


## Turns the contextual vector into an action name. Returned names are
## deliberately tactical rather than mechanical — the steering layer decides how
## to execute them.
func evaluate_tactical_action(defenders_nearby: Array[Node2D]) -> StringName:
	if is_goalkeeper:
		if pitch_boundary != null and ball != null and player != null:
			var goal_centre: Vector2 = pitch_boundary.get_goal_centre(player.team)
			if ball.global_position.distance_to(goal_centre) < GOALKEEPER_CHASE_RADIUS:
				return &"ChaseBall"
		return &"MaintainFormation"

	var pressure: float = calculate_pressure_index(defenders_nearby)

	# Read base attributes, then layer mood on top. Mood never mutates the
	# exported attributes — it is applied only at the decision site so the
	# Inspector always shows the base talent regardless of in-match state.
	var mood_node: MoodSystem = player.get_mood() if player != null else null
	var eff_vision: float = vision_attribute + (mood_node.get_vision_delta() if mood_node != null else 0.0)
	var eff_composure: float = composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0)
	var eff_aggression: float = aggression_attribute + (mood_node.get_aggression_delta() if mood_node != null else 0.0)

	# Clamp so extreme mood cannot push attributes out of the 0-1 behavioural range.
	eff_vision = clampf(eff_vision, 0.0, 1.0)
	eff_composure = clampf(eff_composure, 0.0, 1.0)
	eff_aggression = clampf(eff_aggression, 0.0, 1.0)

	# Composure decides how much of the pressure actually reaches the decision.
	var vision_bias: float = eff_vision * (1.0 - (pressure * (1.0 - eff_composure)))
	var ego_bias: float = eff_aggression * pressure

	if pressure > 0.85 and eff_composure < 0.45:
		return &"PanicClear"

	if ball != null and player != null:
		var distance_to_ball: float = player.global_position.distance_to(ball.global_position)
		if distance_to_ball < CHASE_RADIUS:
			return &"ChaseBall"

	if vision_bias > 0.55:
		return &"SearchOpenPass"
	if ego_bias > 0.65:
		return &"AttemptDribble"

	return &"MaintainFormation"


## 0.0-1.0 crowding score from opponents within PRESSURE_RADIUS.
func calculate_pressure_index(defenders: Array[Node2D]) -> float:
	if player == null:
		return 0.0

	var total_pressure: float = 0.0
	for defender: Node2D in defenders:
		var distance: float = player.global_position.distance_to(defender.global_position)
		if distance < PRESSURE_RADIUS:
			total_pressure += 1.0 - (distance / PRESSURE_RADIUS)

	return clampf(total_pressure, 0.0, 1.0)


## Where the brain wants to be, given the action and the ball's position. The
## anchor drifts toward the ball so the whole shape shifts with play instead of
## standing on marked spots.
func get_target_position() -> Vector2:
	if ball == null:
		return formation_anchor

	match current_action:
		&"ChaseBall", &"PanicClear":
			return ball.global_position
		&"AttemptDribble":
			return ball.global_position
		_:
			return formation_anchor + (ball.global_position - formation_anchor) * formation_ball_weight


func _steer_for_action() -> Vector2:
	var target: Vector2 = get_target_position()
	var offset: Vector2 = target - player.global_position
	var distance: float = offset.length()

	if distance <= ARRIVE_RADIUS:
		return Vector2.ZERO

	# Ease the stick deflection down on approach: full pace far out, a controlled
	# walk close in. Feeding a partial vector means the CPU inherits the same
	# analog speed scaling the human player gets.
	var deflection: float = clampf(distance / (ARRIVE_RADIUS * 4.0), 0.35, 1.0)
	player.is_sprinting = current_action == &"ChaseBall" and distance > CHASE_RADIUS * 0.5
	return offset.normalized() * deflection

	# TODO: replace this direct-seek steering with the full behaviour blend
	# (pursue the ball's predicted position, separate from teammates, mark the
	# nearest runner) once formations exist — Pseudo3DBall.predict_trajectory()
	# already gives the interception point.


func _find_nearby_opponents() -> Array[Node2D]:
	var opponents: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as HeavyPlayerController
		if other != null and other != player and other.team != player.team:
			opponents.append(other)
	return opponents
