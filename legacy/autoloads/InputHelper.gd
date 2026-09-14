##
## InputHelper (Autoload singleton)
##
## Controller-first input front-end for the whole game. Every gameplay script
## reads intent through this singleton rather than touching Input directly, so
## that deadzones, analog scaling and device routing are tuned in exactly one
## place.
##
## Depends on:
##   - The input actions declared in project.godot (Phase 2 table).
##
## Exposes:
##   - get_movement_vector()      -> Vector2  left stick, deadzone filtered,
##                                            magnitude preserved (analog scaling)
##   - get_aim_vector()           -> Vector2  right stick, falls back to left stick
##   - get_movement_deflection()  -> float    0.0-1.0 stick push magnitude
##   - rumble()                             wraps Input.start_joy_vibration()
##   - has_gamepad() / active_device
##   - signal gamepad_connection_changed(connected: bool)
##

extends Node

signal gamepad_connection_changed(connected: bool)

## Analog sticks below this magnitude read as neutral. Tuned per the design
## brief: 0.2 is loose enough to avoid drift, tight enough that a deliberate
## nudge still registers as a walk.
const DEADZONE: float = 0.2

## Below this the right stick is considered neutral and aiming falls back to
## the movement vector. Slightly higher than DEADZONE so a resting thumb never
## steals the aim direction from the run direction.
const AIM_DEADZONE: float = 0.35

## Device index of the pad we are currently listening to. -1 means keyboard only.
var active_device: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_refresh_active_device()


func has_gamepad() -> bool:
	return active_device >= 0


## Left stick / WASD. The returned vector keeps its magnitude (0.0-1.0) so that
## callers can scale top speed by stick deflection instead of snapping to full
## pace. Input.get_vector() already rescales past the deadzone, which gives a
## clean ramp from a walk to a full run.
func get_movement_vector() -> Vector2:
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down", DEADZONE)


## How hard the left stick is pushed, 0.0-1.0. Drives analog speed scaling.
func get_movement_deflection() -> float:
	return clampf(get_movement_vector().length(), 0.0, 1.0)


## Right stick aim, normalized. Falls back to the left stick direction when the
## right stick is at rest, which is what makes single-stick play (and keyboard)
## viable without a dedicated aim input.
func get_aim_vector() -> Vector2:
	var aim: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down", DEADZONE)
	if aim.length() >= AIM_DEADZONE:
		return aim.normalized()

	var move: Vector2 = get_movement_vector()
	if move.length() >= DEADZONE:
		return move.normalized()

	return Vector2.ZERO


## True while the aim stick is actively deflected (as opposed to falling back to
## the movement vector). Charged kicks use this to decide whether the player is
## genuinely aiming or just running.
func is_aiming() -> bool:
	var aim: Vector2 = Input.get_vector(&"aim_left", &"aim_right", &"aim_up", &"aim_down", DEADZONE)
	return aim.length() >= AIM_DEADZONE


## Haptics wrapper. Strength values are 0.0-1.0, duration in seconds.
## Silently no-ops when no pad is connected.
func rumble(weak: float, strong: float, duration: float) -> void:
	if not has_gamepad():
		return
	Input.start_joy_vibration(active_device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), maxf(duration, 0.0))


func stop_rumble() -> void:
	if has_gamepad():
		Input.stop_joy_vibration(active_device)


func _on_joy_connection_changed(device: int, connected: bool) -> void:
	_refresh_active_device()
	# TODO: with local multiplayer, map each device to a specific controlled
	# player instead of collapsing everything onto a single active_device.
	if connected and active_device == device:
		gamepad_connection_changed.emit(true)
	elif not connected and not has_gamepad():
		gamepad_connection_changed.emit(false)


func _refresh_active_device() -> void:
	var pads: Array[int] = Input.get_connected_joypads()
	active_device = pads[0] if pads.size() > 0 else -1
