##
## PitchBoundary
##
## Builds the pitch's hard edges at runtime from a single pitch_size value, so
## the playing area can be retuned from one exported field instead of by dragging
## collision shapes around the editor.
##
## The walls sit on layer 1 (PitchWorld) and mask players (2) and the ball (3).
## Goal mouths are left open — GoalZone areas sit behind them.
##
## Depends on: CollisionLayers, GameEvents.
## Exposes: build_boundaries(), get_pitch_rect(), get_centre_spot()
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
## Thickness of the surrounding walls.
@export var wall_thickness: float = 32.0


func _ready() -> void:
	collision_layer = CollisionLayers.LAYER_PITCH_WORLD
	collision_mask = CollisionLayers.MASK_PITCH_WORLD
	build_boundaries()


## Rebuilds every wall collider. Safe to call at runtime after resizing.
func build_boundaries() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()

	var half: Vector2 = pitch_size * 0.5
	var half_mouth: float = goal_mouth_height * 0.5
	var side_length: float = half.y - half_mouth

	# Touchlines (top and bottom), full width.
	_add_wall(Vector2(0.0, -half.y - wall_thickness * 0.5), Vector2(pitch_size.x + wall_thickness * 2.0, wall_thickness))
	_add_wall(Vector2(0.0, half.y + wall_thickness * 0.5), Vector2(pitch_size.x + wall_thickness * 2.0, wall_thickness))

	# End lines, split around the goal mouth so the ball can enter the goal.
	for direction: float in [-1.0, 1.0]:
		var x: float = direction * (half.x + wall_thickness * 0.5)
		var offset: float = half_mouth + side_length * 0.5
		_add_wall(Vector2(x, -offset), Vector2(wall_thickness, side_length))
		_add_wall(Vector2(x, offset), Vector2(wall_thickness, side_length))

	# TODO: replace the closed box with proper out-of-bounds detection — throw-ins
	# and corners need the ball to leave the pitch and emit
	# GameEvents.ball_out_of_bounds(side) rather than rebound off a wall.


func get_pitch_rect() -> Rect2:
	return Rect2(global_position - pitch_size * 0.5, pitch_size)


func get_centre_spot() -> Vector2:
	return global_position


## World position of a goal line centre. team 0 defends the left goal.
func get_goal_centre(team: int) -> Vector2:
	var direction: float = -1.0 if team == 0 else 1.0
	return global_position + Vector2(direction * pitch_size.x * 0.5, 0.0)


func _add_wall(offset: Vector2, size: Vector2) -> void:
	var shape := RectangleShape2D.new()
	shape.size = size

	var collider := CollisionShape2D.new()
	collider.shape = shape
	collider.position = offset
	add_child(collider)
