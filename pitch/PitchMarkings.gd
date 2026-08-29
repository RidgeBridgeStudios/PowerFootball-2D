##
## PitchMarkings
##
## Draws the pitch lines (touchlines, halfway line, centre circle, penalty
## areas, goal mouths, penalty spots) once at startup. Purely visual — no
## collision, no per-frame updates. Reads pitch_size from the $PitchBoundary
## sibling so the markings always match whatever boundary is actually built.
##
## Depends on: PitchBoundary (read once, via get_parent(), for pitch_size).
## Exposes: nothing — draws itself in _ready()/_draw().
##

class_name PitchMarkings
extends Node2D

const LINE_COLOR: Color = Color(1, 1, 1, 0.85)
const LINE_WIDTH: float = 3.0
const GOAL_FILL_COLOR: Color = Color(1, 1, 1, 0.15)

const CENTRE_CIRCLE_RADIUS: float = 80.0
const CENTRE_SPOT_RADIUS: float = 5.0
const PENALTY_AREA_HEIGHT: float = 380.0
const PENALTY_SPOT_X: float = 680.0
const PENALTY_SPOT_RADIUS: float = 4.0
const GOAL_MOUTH_HEIGHT: float = 200.0

var _pitch_size: Vector2 = Vector2(1600.0, 900.0)


func _ready() -> void:
	var boundary: PitchBoundary = get_parent().get_node("PitchBoundary") as PitchBoundary
	if boundary != null:
		_pitch_size = boundary.pitch_size
	queue_redraw()


func _draw() -> void:
	var half: Vector2 = _pitch_size * 0.5

	draw_rect(Rect2(-half, _pitch_size), LINE_COLOR, false, LINE_WIDTH)
	draw_line(Vector2(0.0, -half.y), Vector2(0.0, half.y), LINE_COLOR, LINE_WIDTH)
	draw_arc(Vector2.ZERO, CENTRE_CIRCLE_RADIUS, 0.0, TAU, 64, LINE_COLOR, LINE_WIDTH)
	draw_circle(Vector2.ZERO, CENTRE_SPOT_RADIUS, LINE_COLOR)

	_draw_penalty_area(-800.0, -600.0)
	_draw_penalty_area(600.0, 800.0)

	_draw_goal_mouth(-824.0, -776.0)
	_draw_goal_mouth(776.0, 824.0)

	draw_circle(Vector2(-PENALTY_SPOT_X, 0.0), PENALTY_SPOT_RADIUS, LINE_COLOR)
	draw_circle(Vector2(PENALTY_SPOT_X, 0.0), PENALTY_SPOT_RADIUS, LINE_COLOR)


func _draw_penalty_area(x_from: float, x_to: float) -> void:
	var rect := Rect2(Vector2(x_from, -PENALTY_AREA_HEIGHT * 0.5), Vector2(x_to - x_from, PENALTY_AREA_HEIGHT))
	draw_rect(rect, LINE_COLOR, false, LINE_WIDTH)


func _draw_goal_mouth(x_from: float, x_to: float) -> void:
	var rect := Rect2(Vector2(x_from, -GOAL_MOUTH_HEIGHT * 0.5), Vector2(x_to - x_from, GOAL_MOUTH_HEIGHT))
	draw_rect(rect, GOAL_FILL_COLOR, true)
