##
## FacingArrow
## A small directional triangle drawn in front of the player's feet,
## rotating each physics tick to match HeavyPlayerController.facing_direction.
## Tinted by team colour so it doubles as a team identifier at a glance.
## Brightens to full opacity when in possession so it is instantly obvious
## who has the ball and which way they intend to go.
## Depends on: HeavyPlayerController (parent node).
##

class_name FacingArrow
extends Node2D

## Distance from the player's centre to the arrow's base, in pixels.
@export var offset_from_centre: float = 22.0
@export var arrow_length: float = 14.0
@export var arrow_half_width: float = 5.0

## Colour per team. Index 0 = TEAM_A, index 1 = TEAM_B.
## PlayerFactory can override these if it already applies team tints.
@export var team_colors: Array[Color] = [
	Color(0.25, 0.55, 1.0, 0.85),   ## TEAM_A — blue
	Color(1.0, 0.35, 0.25, 0.85),   ## TEAM_B — red
]

## Opacity when off-ball / when in possession.
@export var default_alpha: float = 0.55
@export var possession_alpha: float = 1.0

var _controller: HeavyPlayerController = null
var _current_alpha: float = 0.55


func _ready() -> void:
	_controller = get_parent() as HeavyPlayerController
	if _controller == null:
		push_error("FacingArrow must be a direct child of HeavyPlayerController.")
		return
	_controller.possession_gained.connect(_on_possession_gained)
	_controller.possession_lost.connect(_on_possession_lost)
	z_index = 1


func _physics_process(_delta: float) -> void:
	if _controller == null:
		return
	var facing: Vector2 = _controller.facing_direction
	position = facing * offset_from_centre
	rotation = facing.angle()
	queue_redraw()


func _draw() -> void:
	if _controller == null:
		return

	var team_idx: int = clampi(_controller.team, 0, team_colors.size() - 1)
	var base_color: Color = team_colors[team_idx]
	base_color.a = _current_alpha

	# Filled isoceles triangle pointing along local +X.
	# _physics_process rotation aligns +X with facing_direction.
	var tip: Vector2      = Vector2(arrow_length, 0.0)
	var base_top: Vector2 = Vector2(0.0, -arrow_half_width)
	var base_bot: Vector2 = Vector2(0.0,  arrow_half_width)

	draw_colored_polygon(PackedVector2Array([base_top, tip, base_bot]), base_color)

	# Thin outline for legibility on both light and dark pitch backgrounds.
	var outline: Color = Color(0.0, 0.0, 0.0, _current_alpha * 0.4)
	draw_line(base_top, tip, outline, 1.0)
	draw_line(tip, base_bot, outline, 1.0)
	draw_line(base_bot, base_top, outline, 1.0)


func _on_possession_gained() -> void:
	_current_alpha = possession_alpha
	queue_redraw()


func _on_possession_lost() -> void:
	_current_alpha = default_alpha
	queue_redraw()
