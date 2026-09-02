##
## PlayerVisual
##
## Dedicated presentation and token rendering system for HeavyPlayerController.
## Manages 3D spherized tactile lighting, anti-aliased perimeter, team kit palettes,
## centered upright jersey numerals, golden captaincy badges, and goalkeeper gloves.
##
## Purely a visual Node2D component -- reads data and physics state from HeavyPlayerController.
## Choke point: never mutates kinematic physics or tactical AI state.
##

class_name PlayerVisual
extends Node2D

const TOKEN_RADIUS: float = 10.0
const NUMBER_FONT_SIZE: int = 9
const CAPTAIN_BADGE_RADIUS: float = 3.8
const SELECTION_CHEVRON_HEIGHT: float = 18.0

var _controller: HeavyPlayerController = null
var _font: Font = null
var _material: ShaderMaterial = null

var shirt_number: int = 0
var is_captain: bool = false
var is_goalkeeper: bool = false
var is_user_controlled: bool = false
var is_possessor: bool = false

var team_color: Color = Color(0.25, 0.55, 1.0, 1.0)
var secondary_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var gk_color: Color = Color(0.12, 0.78, 0.42, 1.0)
var facing_angle: float = 0.0

@onready var dot_sprite: Sprite2D = $DotSprite if has_node("DotSprite") else null
@onready var shadow_sprite: Sprite2D = $ShadowSprite if has_node("ShadowSprite") else null


func _ready() -> void:
	_font = ThemeDB.fallback_font
	_controller = get_parent() as HeavyPlayerController
	if dot_sprite != null and dot_sprite.material is ShaderMaterial:
		_material = dot_sprite.material as ShaderMaterial
	queue_redraw()


## Applies complete identity, kit styling, and tactical roles onto the presentation layer.
func apply_data(p_data: PlayerData, t_data: TeamData, is_gk: bool) -> void:
	is_goalkeeper = is_gk
	if p_data != null:
		shirt_number = p_data.shirt_number
		is_captain = p_data.is_captain
	if t_data != null:
		team_color = t_data.team_color
		secondary_color = t_data.secondary_color
		gk_color = t_data.gk_color

	_update_shader_uniforms()
	queue_redraw()


## Called every tick from HeavyPlayerController to keep visual orientation and height synchronized.
func sync_physics(facing: Vector2, current_z: float, is_user: bool, in_possession: bool) -> void:
	facing_angle = facing.angle()
	is_user_controlled = is_user
	is_possessor = in_possession

	if dot_sprite != null:
		dot_sprite.position.y = -current_z

	if shadow_sprite != null:
		var shadow_scale_ratio: float = clampf(1.0 - (current_z / 200.0), 0.4, 1.0)
		shadow_sprite.scale = Vector2(shadow_scale_ratio, shadow_scale_ratio)
		shadow_sprite.modulate.a = clampf(0.50 - (current_z / 300.0), 0.15, 0.50)

	_update_shader_uniforms()
	queue_redraw()


func _update_shader_uniforms() -> void:
	if _material == null:
		if dot_sprite != null and dot_sprite.material is ShaderMaterial:
			_material = dot_sprite.material as ShaderMaterial
		else:
			return

	_material.set_shader_parameter(&"team_color", team_color)
	_material.set_shader_parameter(&"secondary_color", secondary_color)
	_material.set_shader_parameter(&"is_goalkeeper", is_goalkeeper)
	_material.set_shader_parameter(&"gk_color", gk_color)
	_material.set_shader_parameter(&"is_captain", is_captain)
	_material.set_shader_parameter(&"facing_angle", facing_angle)
	_material.set_shader_parameter(&"is_user_controlled", is_user_controlled)
	_material.set_shader_parameter(&"is_possessor", is_possessor)


func _draw() -> void:
	var z_offset: float = _controller.current_z if _controller != null else 0.0
	var center: Vector2 = Vector2(0.0, -z_offset)

	## 1. Centered Upright Jersey Number
	if shirt_number > 0 and _font != null:
		var num_str: String = str(shirt_number)
		var text_size: Vector2 = _font.get_string_size(num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, NUMBER_FONT_SIZE)
		var baseline: Vector2 = center + Vector2(-text_size.x * 0.5, text_size.y * 0.35)

		var kit_rgb: Color = gk_color if is_goalkeeper else team_color
		var luminance: float = kit_rgb.r * 0.299 + kit_rgb.g * 0.587 + kit_rgb.b * 0.114
		var text_color: Color = Color.WHITE if luminance < 0.65 else Color(0.12, 0.12, 0.14, 1.0)
		var outline_color: Color = Color(0.08, 0.08, 0.10, 0.95) if luminance < 0.65 else Color(1.0, 1.0, 1.0, 0.95)

		draw_string_outline(_font, baseline, num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, NUMBER_FONT_SIZE, 2, outline_color)
		draw_string(_font, baseline, num_str, HORIZONTAL_ALIGNMENT_CENTER, -1, NUMBER_FONT_SIZE, text_color)

	## 2. Captaincy 'C' Badge on upper-right shoulder
	if is_captain and _font != null:
		var badge_pos: Vector2 = center + Vector2(6.8, -6.8)
		draw_circle(badge_pos + Vector2(0.8, 0.8), CAPTAIN_BADGE_RADIUS, Color(0.0, 0.0, 0.0, 0.40))
		draw_circle(badge_pos, CAPTAIN_BADGE_RADIUS + 0.8, Color(0.12, 0.12, 0.15, 1.0))
		draw_circle(badge_pos, CAPTAIN_BADGE_RADIUS, Color(1.0, 0.82, 0.10, 1.0))

		var user_c_size: Vector2 = _font.get_string_size("C", HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
		var c_baseline: Vector2 = badge_pos + Vector2(-user_c_size.x * 0.5, user_c_size.y * 0.38)

	draw_string(_font, c_baseline, "C", HORIZONTAL_ALIGNMENT_CENTER, -1, 6, Color(0.10, 0.10, 0.12, 1.0))

	## 3. Exhaustion / Severe Fatigue Warning Indicator
	if _controller != null and (_controller.sprint_locked or _controller.get_fatigue_tier() == HeavyPlayerController.FatigueTier.EXHAUSTED) and _font != null:
		var fatigue_pos: Vector2 = center + Vector2(-6.8, -6.8)
		draw_circle(fatigue_pos + Vector2(0.8, 0.8), CAPTAIN_BADGE_RADIUS, Color(0.0, 0.0, 0.0, 0.40))
		draw_circle(fatigue_pos, CAPTAIN_BADGE_RADIUS + 0.8, Color(0.12, 0.12, 0.15, 1.0))
		draw_circle(fatigue_pos, CAPTAIN_BADGE_RADIUS, Color(0.95, 0.25, 0.25, 1.0))

		var user_ex_size: Vector2 = _font.get_string_size("!", HORIZONTAL_ALIGNMENT_CENTER, -1, 6)
		var ex_baseline: Vector2 = fatigue_pos + Vector2(-user_ex_size.x * 0.5, user_ex_size.y * 0.38)
		draw_string(_font, ex_baseline, "!", HORIZONTAL_ALIGNMENT_CENTER, -1, 6, Color.WHITE)

	## 4. User Selection Tactical Indicator
	if is_user_controlled:
		var tip: Vector2 = center + Vector2(0.0, -SELECTION_CHEVRON_HEIGHT)
		var left: Vector2 = tip + Vector2(-4.5, -5.5)
		var right: Vector2 = tip + Vector2(4.5, -5.5)
		var chevron_poly := PackedVector2Array([tip, left, right])
		draw_colored_polygon(chevron_poly, Color(0.95, 0.95, 1.0, 0.95))
		draw_line(tip, left, Color(0.1, 0.1, 0.15, 0.8), 1.0)
		draw_line(left, right, Color(0.1, 0.1, 0.15, 0.8), 1.0)
		draw_line(right, tip, Color(0.1, 0.1, 0.15, 0.8), 1.0)
