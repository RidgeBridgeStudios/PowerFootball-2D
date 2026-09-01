##
## PitchBoundary
##
## Builds the pitch's edges at runtime from a single pitch_size value, so the
## playing area can be retuned from one exported field instead of by dragging
## collision shapes around the editor.
##
## The touchlines and end lines are open: crossing them is detected by Area2D
## sensors on LAYER_BOUNDARY_SENSOR rather than a rebound, so the ball can
## genuinely leave the pitch for throw-ins, goal kicks and corners. Only short
## "post" stubs remain hard collision, right at the goal mouth edges, so a shot
## that clips the frame still rebounds instead of sliding straight through into
## the open end line. GoalZone (a separate node, positioned just behind the end
## line within the goal mouth) still owns scoring.
##
## Depends on: CollisionLayers, GameEvents, Pseudo3DBall, HeavyPlayerController.
## Exposes: build_boundaries(), get_pitch_rect(), get_centre_spot(), get_goal_centre()
##

class_name PitchBoundary
extends StaticBody2D

## Playing area in pixels, centred on this node.
@export var pitch_size: Vector2 = Vector2(1600.0, 900.0):
	set(value):
		pitch_size = value
		if is_inside_tree():
			build_boundaries()
## Height of the goal mouth opening in each end line.
@export var goal_mouth_height: float = 200.0
## Thickness of the hard goalpost stubs.
@export var wall_thickness: float = 32.0
## Thickness of the touchline/end-line out-of-bounds sensors.
@export var sensor_thickness: float = 32.0

## Canonical penalty area dimensions in pixels.
const PENALTY_AREA_DEPTH: float = 200.0
const PENALTY_AREA_HEIGHT: float = 380.0

## Whether team defending ends are swapped (e.g., during the second half).
var sides_flipped: bool = false


func _ready() -> void:
	collision_layer = CollisionLayers.LAYER_PITCH_WORLD
	collision_mask = CollisionLayers.MASK_PITCH_WORLD
	build_boundaries()


func set_sides_flipped(flipped: bool) -> void:
	sides_flipped = flipped


## Rebuilds every wall and sensor. Safe to call at runtime after resizing.
func build_boundaries() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	var half: Vector2 = pitch_size * 0.5
	var half_mouth: float = goal_mouth_height * 0.5
	var side_length: float = half.y - half_mouth

	_build_goalpost_stubs(half, half_mouth)
	_build_touchline_sensors(half)
	_build_endline_sensors(half, half_mouth, side_length)


func get_pitch_rect() -> Rect2:
	return Rect2(global_position - pitch_size * 0.5, pitch_size)


func get_centre_spot() -> Vector2:
	return global_position


## World position of a goal line centre. Dynamically tracks half-time side swapping.
func get_goal_centre(team: int) -> Vector2:
	var defends_left: bool = (team == 0) if not sides_flipped else (team != 0)
	var direction: float = -1.0 if defends_left else 1.0
	return global_position + Vector2(direction * pitch_size.x * 0.5, 0.0)


## Returns whether a world-space point lies within the defending team's penalty box.
func is_in_penalty_area(pos: Vector2, defending_team: int) -> bool:
	var goal_centre: Vector2 = get_goal_centre(defending_team)
	var defends_left: bool = (defending_team == 0) if not sides_flipped else (defending_team != 0)
	var inward_dir: float = 1.0 if defends_left else -1.0
	var local: Vector2 = pos - goal_centre
	var depth: float = local.x * inward_dir
	var half_height: float = PENALTY_AREA_HEIGHT * 0.5
	return depth >= 0.0 and depth <= PENALTY_AREA_DEPTH and absf(local.y) <= half_height


## World-space bounding rectangle of the defending team's penalty box.
func get_penalty_area_rect(defending_team: int) -> Rect2:
	var goal_centre: Vector2 = get_goal_centre(defending_team)
	var defends_left: bool = (defending_team == 0) if not sides_flipped else (defending_team != 0)
	var half_height: float = PENALTY_AREA_HEIGHT * 0.5
	if defends_left:
		return Rect2(goal_centre.x, goal_centre.y - half_height, PENALTY_AREA_DEPTH, PENALTY_AREA_HEIGHT)
	else:
		return Rect2(goal_centre.x - PENALTY_AREA_DEPTH, goal_centre.y - half_height, PENALTY_AREA_DEPTH, PENALTY_AREA_HEIGHT)


## Short hard stubs right at the goal mouth edges — the posts — so a shot that
## clips the frame rebounds instead of sliding past it into the open end line.
func _build_goalpost_stubs(half: Vector2, half_mouth: float) -> void:
	for direction: float in [-1.0, 1.0]:
		var x: float = direction * (half.x + wall_thickness * 0.5)
		for mouth_side: float in [-1.0, 1.0]:
			_add_wall(Vector2(x, mouth_side * half_mouth), Vector2(wall_thickness, wall_thickness))


func _build_touchline_sensors(half: Vector2) -> void:
	var size: Vector2 = Vector2(pitch_size.x + wall_thickness * 2.0, sensor_thickness)
	var top: Area2D = _make_sensor("TouchlineSensorTop", "touchline_top")
	_add_sensor_shape(top, Vector2(0.0, -half.y - sensor_thickness * 0.5), size)
	add_child(top)

	var bottom: Area2D = _make_sensor("TouchlineSensorBottom", "touchline_bottom")
	_add_sensor_shape(bottom, Vector2(0.0, half.y + sensor_thickness * 0.5), size)
	add_child(bottom)


## Each end line sensor covers the full pitch height minus the goal mouth gap —
## two shapes (above and below the mouth) under one Area2D per side, positioned
## just beyond the goalpost stubs.
func _build_endline_sensors(half: Vector2, half_mouth: float, side_length: float) -> void:
	var segment_size: Vector2 = Vector2(sensor_thickness, side_length)
	var offset_y: float = half_mouth + side_length * 0.5

	for direction: float in [-1.0, 1.0]:
		var sensor_name: String = "EndlineSensorLeft" if direction < 0.0 else "EndlineSensorRight"
		var side: String = "end_line_left" if direction < 0.0 else "end_line_right"
		var x: float = direction * (half.x + wall_thickness + sensor_thickness * 0.5)
		var sensor: Area2D = _make_sensor(sensor_name, side)
		_add_sensor_shape(sensor, Vector2(x, -offset_y), segment_size)
		_add_sensor_shape(sensor, Vector2(x, offset_y), segment_size)
		add_child(sensor)


func _make_sensor(node_name: String, side: String) -> Area2D:
	var sensor := Area2D.new()
	sensor.name = node_name
	sensor.collision_layer = CollisionLayers.LAYER_BOUNDARY_SENSOR
	sensor.collision_mask = CollisionLayers.MASK_BOUNDARY_SENSOR
	sensor.monitoring = true
	sensor.body_entered.connect(_on_sensor_body_entered.bind(side))
	return sensor


func _add_sensor_shape(sensor: Area2D, offset: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size

	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = offset
	sensor.add_child(collider)


func _add_wall(offset: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size

	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = offset
	add_child(collider)


func _on_sensor_body_entered(body: Node2D, side: String) -> void:
	var ball := body as Pseudo3DBall
	if ball == null:
		return
	_on_ball_crossed_boundary(ball, side)


## Records nothing itself — last-touch tracking lives on the ball — but decides
## which out-of-bounds event to raise: a touchline crossing is always a
## throw-in, while an end-line crossing is a goal kick or a corner depending on
## whether the attacker or the defender of that goal touched it last.
func _on_ball_crossed_boundary(ball: Pseudo3DBall, side: String) -> void:
	match side:
		"touchline_top", "touchline_bottom":
			GameEvents.ball_out_of_bounds.emit(side)
		"end_line_left", "end_line_right":
			var is_left: bool = (side == "end_line_left")
			var defending_team: int = (0 if is_left else 1) if not sides_flipped else (1 if is_left else 0)
			var toucher: HeavyPlayerController = ball.last_touched_by
			# No recorded touch (e.g. it rolled out untouched): default to the
			# simpler goal kick rather than guessing a corner.
			var attacker_touched_last: bool = toucher == null or toucher.team != defending_team
			GameEvents.ball_out_of_bounds.emit("end_line_goal_kick" if attacker_touched_last else "end_line_corner")
