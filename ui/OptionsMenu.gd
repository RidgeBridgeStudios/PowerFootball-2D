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

const DURATION_OPTIONS: Array[Dictionary] = [
	{"label": "2.5 min half (5 min match)", "seconds": 150.0},
	{"label": "3 min half (6 min match)", "seconds": 180.0},
	{"label": "4 min half (8 min match)", "seconds": 240.0},
	{"label": "5 min half (10 min match)", "seconds": 300.0},
	{"label": "10 min half (20 min match)", "seconds": 600.0},
	{"label": "45 min half (90 min full real-time match)", "seconds": 2700.0},
]

@onready var slider_master: HSlider = $Panel/Layout/AudioSection/MasterRow/MasterSlider
@onready var slider_music: HSlider = $Panel/Layout/AudioSection/MusicRow/MusicSlider
@onready var slider_sfx: HSlider = $Panel/Layout/AudioSection/SfxRow/SfxSlider
@onready var lbl_master: Label = $Panel/Layout/AudioSection/MasterRow/MasterValueLabel
@onready var lbl_music: Label = $Panel/Layout/AudioSection/MusicRow/MusicValueLabel
@onready var lbl_sfx: Label = $Panel/Layout/AudioSection/SfxRow/SfxValueLabel
@onready var chk_fullscreen: CheckButton = $Panel/Layout/GraphicsSection/FullscreenRow/FullscreenCheck
@onready var chk_fps: CheckButton = $Panel/Layout/GraphicsSection/FpsRow/FpsCheck
@onready var opt_half_length: OptionButton = $Panel/Layout/GameplaySection/HalfLengthRow/HalfLengthOption
@onready var btn_custom_league: Button = $Panel/Layout/DatabaseSection/CustomLeagueRow/CustomLeagueButton
@onready var lbl_league_status: Label = $Panel/Layout/DatabaseSection/CustomLeagueStatusLabel
@onready var btn_back: Button = $Panel/Layout/BackButton
@onready var file_dialog: ConfirmationDialog = $FileDialog


func _ready() -> void:
	visible = false
	slider_master.value_changed.connect(_on_master_changed)
	slider_music.value_changed.connect(_on_music_changed)
	slider_sfx.value_changed.connect(_on_sfx_changed)
	chk_fullscreen.toggled.connect(_on_fullscreen_toggled)
	chk_fps.toggled.connect(_on_fps_toggled)
	if opt_half_length != null:
		opt_half_length.item_selected.connect(_on_half_length_selected)
	if btn_custom_league != null:
		btn_custom_league.pressed.connect(_on_custom_league_pressed)
	if file_dialog != null:
		file_dialog.file_selected.connect(_on_league_file_selected)
	btn_back.pressed.connect(_on_back_pressed)

	_populate_durations()
	_on_master_changed(slider_master.value)
	_on_music_changed(slider_music.value)
	_on_sfx_changed(slider_sfx.value)


func _populate_durations() -> void:
	if opt_half_length == null:
		return
	opt_half_length.clear()
	var selected_idx: int = 0
	for i: int in range(DURATION_OPTIONS.size()):
		var opt: Dictionary = DURATION_OPTIONS[i]
		opt_half_length.add_item(opt["label"])
		if is_equal_approx(opt["seconds"], GameManager.half_duration_real_sec):
			selected_idx = i
	opt_half_length.select(selected_idx)


func _on_half_length_selected(index: int) -> void:
	if index >= 0 and index < DURATION_OPTIONS.size():
		var sec: float = DURATION_OPTIONS[index]["seconds"]
		GameManager.set_half_duration(sec)
		GameManager.set_meta(&"half_duration_real_sec", sec)


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


func _on_custom_league_pressed() -> void:
	if file_dialog != null:
		file_dialog.popup_centered()


func _on_league_file_selected(path: String) -> void:
	if DataLoader.load_league_from(path):
		var count: int = DataLoader.league.teams.size() if DataLoader.league != null else 0
		var name_str: String = DataLoader.league.league_name if DataLoader.league != null else ""
		if lbl_league_status != null:
			lbl_league_status.text = "Loaded: %s (%d teams)" % [name_str, count]
	else:
		if lbl_league_status != null:
			lbl_league_status.text = "Failed to load league from %s" % path


func _on_back_pressed() -> void:
	menu_closed.emit()
