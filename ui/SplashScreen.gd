##
## SplashScreen
##
## Initial game startup splash screen displaying the Ridgebridge Studios indie
## logo with smooth fade transitions, controller/keyboard/mouse skip support,
## and progression to MainMenu.tscn.
##
## Depends on: GameManager.
## Exposes: nothing — scene entry point.
##

class_name SplashScreen
extends Control

const MAIN_MENU_SCENE: String = "res://ui/MainMenu.tscn"
const FADE_IN_DURATION: float = 0.8
const DISPLAY_DURATION: float = 1.6
const FADE_OUT_DURATION: float = 0.6

@onready var background_rect: ColorRect = $Background
@onready var logo_rect: TextureRect = $LogoRect
@onready var prompt_label: Label = $PromptLabel

var _tween: Tween = null
var _is_transitioning: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	modulate.a = 0.0
	prompt_label.modulate.a = 0.0
	_start_splash_sequence()


func _start_splash_sequence() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	# 1. Fade in splash screen
	_tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# 2. Fade in subtle skip prompt slightly after
	_tween.parallel().tween_property(prompt_label, "modulate:a", 0.6, FADE_IN_DURATION * 0.8).set_delay(0.3)
	# 3. Hold on screen
	_tween.tween_interval(DISPLAY_DURATION)
	# 4. Fade out
	_tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# 5. Switch to Main Menu
	_tween.tween_callback(_transition_to_main_menu)


func _transition_to_main_menu() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	if _tween != null and _tween.is_valid():
		_tween.kill()

	var err: int = get_tree().change_scene_to_file(MAIN_MENU_SCENE)
	if err != OK:
		push_error("SplashScreen: Failed to change scene to %s (Error %d)" % [MAIN_MENU_SCENE, err])


func _skip_splash() -> void:
	if _is_transitioning:
		return

	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Fast fade out before transitioning
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_transition_to_main_menu)


func _unhandled_input(event: InputEvent) -> void:
	if _is_transitioning:
		return

	if event is InputEventKey:
		var key_ev := event as InputEventKey
		if key_ev.pressed and not key_ev.is_echo():
			get_viewport().set_input_as_handled()
			_skip_splash()
	elif event is InputEventJoypadButton:
		var joy_ev := event as InputEventJoypadButton
		if joy_ev.pressed:
			get_viewport().set_input_as_handled()
			_skip_splash()
	elif event is InputEventMouseButton:
		var mouse_ev := event as InputEventMouseButton
		if mouse_ev.pressed:
			get_viewport().set_input_as_handled()
			_skip_splash()


func _gui_input(event: InputEvent) -> void:
	if _is_transitioning:
		return

	if event is InputEventMouseButton:
		var mouse_ev := event as InputEventMouseButton
		if mouse_ev.pressed:
			accept_event()
			_skip_splash()
