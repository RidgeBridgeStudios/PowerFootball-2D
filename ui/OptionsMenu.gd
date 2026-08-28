##
## OptionsMenu
##
## Audio/graphics settings overlay shown by MainMenu. Applies volume live via
## AudioServer and stores the fullscreen/FPS-counter preferences; FPS display
## itself lives on GameManager meta rather than here since the HUD (not the
## menu) owns the on-screen counter.
##
## Depends on: GameManager, AudioServer, DisplayServer.
## Exposes: signal menu_closed, open()
##

extends Control

signal menu_closed

@onready var slider_master: HSlider = $Panel/Layout/AudioSection/MasterRow/MasterSlider
@onready var slider_music: HSlider = $Panel/Layout/AudioSection/MusicRow/MusicSlider
@onready var slider_sfx: HSlider = $Panel/Layout/AudioSection/SfxRow/SfxSlider
@onready var lbl_master: Label = $Panel/Layout/AudioSection/MasterRow/MasterValueLabel
@onready var lbl_music: Label = $Panel/Layout/AudioSection/MusicRow/MusicValueLabel
@onready var lbl_sfx: Label = $Panel/Layout/AudioSection/SfxRow/SfxValueLabel
@onready var chk_fullscreen: CheckButton = $Panel/Layout/GraphicsSection/FullscreenRow/FullscreenCheck
@onready var chk_fps: CheckButton = $Panel/Layout/GraphicsSection/FpsRow/FpsCheck
@onready var btn_back: Button = $Panel/Layout/BackButton


func _ready() -> void:
	visible = false
	slider_master.value_changed.connect(_on_master_changed)
	slider_music.value_changed.connect(_on_music_changed)
	slider_sfx.value_changed.connect(_on_sfx_changed)
	chk_fullscreen.toggled.connect(_on_fullscreen_toggled)
	chk_fps.toggled.connect(_on_fps_toggled)
	btn_back.pressed.connect(_on_back_pressed)

	_on_master_changed(slider_master.value)
	_on_music_changed(slider_music.value)
	_on_sfx_changed(slider_sfx.value)


func open() -> void:
	visible = true
	slider_master.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"action_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_pressed()


func _on_master_changed(value: float) -> void:
	lbl_master.text = str(int(value))
	_apply_bus_volume("Master", value)


func _on_music_changed(value: float) -> void:
	lbl_music.text = str(int(value))
	_apply_bus_volume("Music", value)


func _on_sfx_changed(value: float) -> void:
	lbl_sfx.text = str(int(value))
	_apply_bus_volume("SFX", value)


## "Master" always resolves (Godot creates it by default). "Music" and "SFX"
## no-op until those buses are added to the project's Audio Bus Layout — add
## them there (Audio panel → Add Bus) to wire this up for real.
func _apply_bus_volume(bus_name: String, value: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(value / 100.0))


func _on_fullscreen_toggled(on: bool) -> void:
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_fps_toggled(on: bool) -> void:
	GameManager.set_meta(&"show_fps", on)


func _on_back_pressed() -> void:
	menu_closed.emit()
