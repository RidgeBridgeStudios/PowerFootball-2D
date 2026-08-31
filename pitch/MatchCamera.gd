##
## MatchCamera
##
## Three-mode camera controller for PowerFootball-2D.
## BALL_FOLLOW  — tracks the ball closely; zoom is fixed at ball_follow_zoom.
##                Best for close-quarters play.
## DYNAMIC      — tracks a weighted average of the ball position and the human
##                player's position; zoom expands when the two are far apart and
##                contracts when the action is tight. The default gameplay mode.
## FULL_FIELD   — centres on the pitch midpoint and zooms out so the entire
##                pitch fits inside the viewport. Zoom is read-only.
## The active mode cycles on the "camera_cycle_mode" input action (Tab), or by
## calling set_mode()/cycle_mode() directly. All transitions are lerped — no
## instant snap.
##
## Depends on: PitchBoundary (bound via bind_pitch()), Pseudo3DBall (bound via
## bind_ball()), HeavyPlayerController (bound via bind_human_player()).
## PitchScene owns calling all three bind methods and keeping the human player
## reference current across player switches.
## Exposes: bind_ball(), bind_human_player(), bind_pitch(), set_mode(),
##          cycle_mode(), get_mode(), get_mode_name()
##

class_name MatchCamera
extends Camera2D

## ── Mode ─────────────────────────────────────────────────────────────────────

enum Mode { BALL_FOLLOW, DYNAMIC, FULL_FIELD }

## Human-readable labels, indexed by Mode. Kept alongside the enum so the HUD
## and the cycling logic never drift out of sync with each other.
const _MODE_NAMES: Array[String] = ["BALL FOLLOW", "DYNAMIC", "FULL FIELD"]

signal camera_mode_changed(mode_name: String)

## Starting mode. Override in the Inspector or via set_mode() at runtime.
@export var initial_mode: Mode = Mode.DYNAMIC

## Margin to allow camera to show out of bounds
@export var out_of_bounds_margin: float = 150.0

## ── Zoom levels ──────────────────────────────────────────────────────────────

## Zoom used in BALL_FOLLOW. Higher value = more zoomed in.
@export var ball_follow_zoom: float = 1.50

## DYNAMIC zoom range. The camera interpolates between these two extremes
## based on the distance between the ball and the human player.
@export var dynamic_zoom_min: float = 0.80   ## zoomed out (action spread wide)
@export var dynamic_zoom_max: float = 1.30   ## zoomed in  (action tight)

## World-space distance at which DYNAMIC zoom reaches its minimum.
@export var dynamic_spread_max: float = 700.0

## Computed at runtime from the pitch rect — overwritten in bind_pitch().
var _full_field_zoom: float = 0.52

## ── Smoothing ────────────────────────────────────────────────────────────────

## Position lerp speed (higher = snappier). Applied every physics frame.
@export var position_lerp_speed: float = 6.0

## Zoom lerp speed (lower = lazier zoom transitions).
@export var zoom_lerp_speed: float = 3.0

## DYNAMIC lead-ahead: the camera looks slightly ahead of the ball's velocity.
## 0.0 = no lead, 1.0 = very aggressive.
@export_range(0.0, 1.0) var velocity_lead_strength: float = 0.18

## Max pixels the lead-ahead offset can push the camera from the base target.
@export var max_lead_distance: float = 120.0

## ── Internal state ───────────────────────────────────────────────────────────

var _mode: Mode = Mode.DYNAMIC
var _ball: Node2D = null              ## Pseudo3DBall
var _human: Node2D = null             ## HeavyPlayerController
var _boundary: Node = null            ## PitchBoundary
var _pitch_rect: Rect2 = Rect2()
var _target_zoom: float = 1.0
var _target_position: Vector2 = Vector2.ZERO


func _ready() -> void:
	_mode = initial_mode
	position_smoothing_enabled = false  ## we handle smoothing manually
	_target_zoom = _zoom_for_mode(_mode)
	zoom = Vector2(_target_zoom, _target_zoom)


## ── Bind API (called by PitchScene) ─────────────────────────────────────────

func bind_ball(b: Node2D) -> void:
	_ball = b


func bind_human_player(p: Node2D) -> void:
	_human = p


func bind_pitch(boundary: Node) -> void:
	_boundary = boundary
	if _boundary != null and _boundary.has_method("get_pitch_rect"):
		_pitch_rect = _boundary.get_pitch_rect()
	else:
		_pitch_rect = Rect2(Vector2(-864.0, -512.0), Vector2(1728.0, 1024.0))
	_full_field_zoom = _compute_full_field_zoom()
	if _mode == Mode.FULL_FIELD:
		_target_zoom = _full_field_zoom
		zoom = Vector2(_target_zoom, _target_zoom)


## ── Mode switching ───────────────────────────────────────────────────────────

## Cycles BALL_FOLLOW → DYNAMIC → FULL_FIELD → BALL_FOLLOW.
func cycle_mode() -> void:
	set_mode((int(_mode) + 1) % _MODE_NAMES.size())


func set_mode(new_mode: Mode) -> void:
	_mode = new_mode
	_target_zoom = _zoom_for_mode(_mode)
	camera_mode_changed.emit(get_mode_name())


func get_mode() -> Mode:
	return _mode


func get_mode_name() -> String:
	return _MODE_NAMES[_mode]


## ── Core update loop ─────────────────────────────────────────────────────────

func _physics_process(delta: float) -> void:
	if _ball == null:
		return

	_target_position = _compute_target_position()
	_target_zoom     = _compute_target_zoom()

	# Clamp position so the camera never shows outside the pitch in overview.
	if _mode == Mode.FULL_FIELD:
		global_position = _pitch_rect.get_center()
	else:
		var clamped: Vector2 = _clamp_to_pitch(_target_position)
		global_position = global_position.lerp(clamped, clampf(position_lerp_speed * delta, 0.0, 1.0))

	var new_zoom: float = lerpf(zoom.x, _target_zoom, clampf(zoom_lerp_speed * delta, 0.0, 1.0))
	zoom = Vector2(new_zoom, new_zoom)


## ── Input ────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"camera_cycle_mode"):
		cycle_mode()


## ── Private helpers ──────────────────────────────────────────────────────────

func _ball_velocity() -> Vector2:
	if _ball == null:
		return Vector2.ZERO
	if _ball.has_method("get_velocity"):
		return _ball.get_velocity()
	if "velocity" in _ball:
		return _ball.velocity
	return Vector2.ZERO


func _compute_target_position() -> Vector2:
	var ball_pos: Vector2 = _ball.global_position

	match _mode:
		Mode.BALL_FOLLOW:
			# Lead slightly in the direction the ball is travelling.
			var follow_lead: Vector2 = _ball_velocity().limit_length(max_lead_distance) * velocity_lead_strength
			return ball_pos + follow_lead

		Mode.DYNAMIC:
			if _human == null:
				return ball_pos
			# Weighted average: ball gets 65%, human player gets 35%. Keeps the
			# ball as the star of the show while giving the human player enough
			# screen presence to anticipate the next touch.
			var weighted: Vector2 = ball_pos * 0.65 + _human.global_position * 0.35
			var dyn_lead: Vector2 = _ball_velocity().limit_length(max_lead_distance) * velocity_lead_strength * 0.6
			return weighted + dyn_lead

		Mode.FULL_FIELD:
			return _pitch_rect.get_center()

	return ball_pos


func _compute_target_zoom() -> float:
	match _mode:
		Mode.BALL_FOLLOW:
			return ball_follow_zoom

		Mode.DYNAMIC:
			if _human == null:
				return dynamic_zoom_max
			var spread: float = _ball.global_position.distance_to(_human.global_position)
			# Remap spread [0 … dynamic_spread_max] → zoom [max … min].
			var t: float = clampf(spread / dynamic_spread_max, 0.0, 1.0)
			return lerpf(dynamic_zoom_max, dynamic_zoom_min, t)

		Mode.FULL_FIELD:
			return _full_field_zoom

	return dynamic_zoom_max


func _zoom_for_mode(m: Mode) -> float:
	match m:
		Mode.BALL_FOLLOW:
			return ball_follow_zoom
		Mode.DYNAMIC:
			return dynamic_zoom_max
		Mode.FULL_FIELD:
			return _full_field_zoom
	return dynamic_zoom_max


func _compute_full_field_zoom() -> float:
	if _pitch_rect.size == Vector2.ZERO:
		return 0.52
	var expanded_rect: Rect2 = _pitch_rect.grow(out_of_bounds_margin)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# 10% padding so the touchlines are not flush with the screen edge.
	var padding: float = 0.90
	var zoom_x: float = viewport_size.x / expanded_rect.size.x * padding
	var zoom_y: float = viewport_size.y / expanded_rect.size.y * padding
	# Use the smaller axis so the full pitch always fits.
	return minf(zoom_x, zoom_y)


## Clamp the camera centre so it does not scroll past the pitch edges. The
## clamp margin shrinks as zoom increases (you see less world space).
func _clamp_to_pitch(pos: Vector2) -> Vector2:
	if _pitch_rect.size == Vector2.ZERO:
		return pos
	var expanded_rect: Rect2 = _pitch_rect.grow(out_of_bounds_margin)
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var half_view: Vector2 = viewport_size * 0.5 / zoom
	var min_pos: Vector2 = expanded_rect.position + half_view
	var max_pos: Vector2 = expanded_rect.end      - half_view
	# If the viewport is wider than the pitch (e.g. a near full-field view),
	# centre on the pitch on that axis rather than clamping.
	var clamped_x: float = pos.x if half_view.x >= expanded_rect.size.x * 0.5 else clampf(pos.x, min_pos.x, max_pos.x)
	var clamped_y: float = pos.y if half_view.y >= expanded_rect.size.y * 0.5 else clampf(pos.y, min_pos.y, max_pos.y)
	return Vector2(clamped_x, clamped_y)
