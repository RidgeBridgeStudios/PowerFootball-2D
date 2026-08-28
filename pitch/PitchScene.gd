##
## PitchScene
##
## Match scene root. It wires the pieces together — ball, players, boundary,
## goals, camera, HUD — and owns restarts: kickoff placement, the pause after a
## goal, and full time. It reacts to GameEvents rather than being called by the
## systems that raise them.
##
## Collision matrix (see shared/CollisionLayers.gd for the authoritative table):
##   1 PitchWorld       walls + goal frames   masks players (2) and ball (3)
##   2 PlayerBodies     player bodies         masks world (1) and players (2)
##   3 BallPhysicsBody  ball body             masks world (1) ONLY
##   4 FootSensorArea   foot Area2D           masks ball (3)
##   5 AerialHitboxZone shoulder Area2D       masks ball (3)
## The ball never masks players: a hard ball/player contact would zero player
## velocity in the move_and_slide solver and flatten the momentum model.
##
## Depends on: GameManager, GameEvents, PitchBoundary, Pseudo3DBall,
##             HeavyPlayerController, PlayerBrain, SetPieceCoordinator,
##             DataLoader, PlayerFactory.
## Exposes: reset_for_kickoff(), shake_camera(amount)
##

class_name PitchScene
extends Node2D

## Seconds the celebration holds before the ball is placed for the restart.
@export var goal_restart_delay: float = 2.5
## Camera shake decay, in units per second.
@export var shake_decay: float = 6.0
## Maximum camera offset in pixels at full shake.
@export var shake_strength: float = 8.0

var _shake_amount: float = 0.0

@onready var boundary: PitchBoundary = $PitchBoundary
@onready var ball: Pseudo3DBall = $Ball
@onready var players: Node2D = $Players
@onready var camera: Camera2D = $MatchCamera
@onready var restart_timer: Timer = $RestartTimer
@onready var hud: HUD = $HUD
@onready var _set_piece_coordinator: SetPieceCoordinator = $SetPieceCoordinator


func _ready() -> void:
	randomize()

	GameEvents.goal_scored.connect(_on_goal_scored)
	GameEvents.match_ended.connect(_on_match_ended)
	GameEvents.ball_out_of_bounds.connect(_on_ball_out_of_bounds)
	GameEvents.foul_committed.connect(_on_foul_committed)
	ball.ball_bounced.connect(_on_ball_bounced)
	restart_timer.timeout.connect(_on_restart_timer_timeout)

	_bind_players()
	_set_piece_coordinator.bind(ball, boundary, players)
	reset_for_kickoff()
	GameManager.start_match()
	GameManager.restart_play()


func _process(delta: float) -> void:
	_update_camera(delta)
	if Input.is_action_just_pressed(&"action_switch"):
		switch_to_nearest_teammate()


## Places the ball on the centre spot and returns every player to their
## formation anchor.
##
## TODO: unify with SetPieceCoordinator. Kickoff deliberately stays on this
## older, simpler path rather than being routed through the coordinator: it
## has no "out of bounds" or "foul" trigger to react to, always uses the same
## fixed centre-spot placement, and — unlike the other restarts — happens
## before any players exist to freeze/assign a taker from on the very first
## call. Folding it in would mean special-casing the coordinator for a case it
## does not otherwise need to handle; left as-is until there is a real reason
## (e.g. a kickoff-specific taker/ready-up UI) to share the machinery.
func reset_for_kickoff() -> void:
	ball.reset_at(boundary.get_centre_spot())

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		if player.brain != null and player.brain.formation_anchor != Vector2.ZERO:
			player.global_position = player.brain.formation_anchor
		player.velocity = Vector2.ZERO

	var kickoff_team: int = GameManager.TEAM_A
	if GameManager.last_scoring_team >= 0:
		kickoff_team = 1 - GameManager.last_scoring_team
	GameEvents.kickoff_confirmed.emit(kickoff_team)


## Camera feel. Kept here deliberately small.
## TODO: extract into a CameraRig node alongside dynamic zoom (pull out when play
## is stretched, push in near the box) once there are more than two players.
func shake_camera(amount: float) -> void:
	_shake_amount = minf(_shake_amount + amount, 1.0)


func _update_camera(delta: float) -> void:
	# Follow the ball, damped, so the pitch stays readable and the camera never
	# snaps. The high-angle view is otherwise static by design.
	var target: Vector2 = ball.global_position.lerp(boundary.get_centre_spot(), 0.35)
	camera.global_position = camera.global_position.lerp(target, 1.0 - exp(-3.0 * delta))

	if _shake_amount <= 0.0:
		camera.offset = Vector2.ZERO
		return

	_shake_amount = maxf(_shake_amount - shake_decay * delta * _shake_amount, 0.0)
	var magnitude: float = shake_strength * _shake_amount
	camera.offset = Vector2(randf_range(-magnitude, magnitude), randf_range(-magnitude, magnitude))


func _bind_players() -> void:
	var squad_counts: Dictionary = {}

	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null:
			continue
		player.add_to_group(&"players")
		if player.brain != null:
			player.brain.bind_ball(ball)
		if player.is_user_controlled:
			hud.bind_active_player(player)

		var anchor: Vector2 = player.brain.formation_anchor if player.brain != null else player.global_position
		player.squad_index = squad_counts.get(player.team, 0)
		squad_counts[player.team] = player.squad_index + 1
		PlayerFactory.apply(player, DataLoader.get_player(player.team, player.squad_index), anchor)


## Hands control to whichever teammate is closest to the ball. Control transfers
## wholesale: the player being left behind hands off to its brain, which picks up
## from the exact velocity it was moving at, so a switch never teleports momentum.
func switch_to_nearest_teammate() -> void:
	var current: HeavyPlayerController = hud.active_player
	if current == null:
		return

	var best: HeavyPlayerController = null
	var best_distance: float = INF
	for node: Node in players.get_children():
		var player := node as HeavyPlayerController
		if player == null or player == current or player.team != current.team:
			continue
		var distance: float = player.global_position.distance_to(ball.global_position)
		if distance < best_distance:
			best_distance = distance
			best = player

	if best == null:
		return

	current.is_user_controlled = false
	current.movement_intent = Vector2.ZERO
	best.is_user_controlled = true
	hud.bind_active_player(best)
	GameEvents.player_switched.emit(best)


func _on_goal_scored(_team: int) -> void:
	ball.freeze()
	shake_camera(1.0)
	InputHelper.rumble(0.5, 0.9, 0.35)
	restart_timer.start(goal_restart_delay)


func _on_restart_timer_timeout() -> void:
	reset_for_kickoff()
	ball.unfreeze()
	GameManager.kickoff()
	GameManager.restart_play()


func _on_match_ended(_winner: int) -> void:
	ball.freeze()
	# TODO: full-time screen and a rematch flow; for now the pitch simply stops.


func _on_ball_out_of_bounds(side: String) -> void:
	ball.freeze()
	_set_piece_coordinator.handle_out_of_bounds(side, ball.global_position, ball.last_touched_by)


func _on_foul_committed(fouler: Node, victim: Node, pos: Vector2) -> void:
	var fouler_player := fouler as HeavyPlayerController
	var victim_player := victim as HeavyPlayerController
	if fouler_player == null or victim_player == null:
		return
	ball.freeze()
	_set_piece_coordinator.handle_foul(fouler_player, victim_player, pos)


func _on_ball_bounced(impact_velocity: float) -> void:
	# Only meaningful impacts shake the frame — a settling ball should not.
	if impact_velocity > 200.0:
		shake_camera(clampf(impact_velocity / 900.0, 0.0, 0.6))
