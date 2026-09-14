##
## MainMenu
##
## Entry point of the game (res://ui/SplashScreen.tscn is run/main_scene and
## hands off here). Owns the three top-level menu buttons and the quit
## confirmation popup; OptionsMenu is a separate scene instanced as a child and
## shown/hidden as an overlay rather than a swapped scene, so the menu list
## underneath never has to reload state.
##
## The manager-only pivot retired the Kick Off and Practice Arena buttons along
## with the real-time PitchScene they launched, and with them the locked
## "Player Career" placeholder — Manager Mode is now the single playable mode.
##
## Depends on: OptionsMenu.
## Exposes: nothing — this is a scene root, not a service other scripts call into.
##

extends Control

const MENU_FONT_SIZE: int = 22
const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)
const TEXT_COLOR: Color = Color(0.909804, 0.941176, 0.913725)

@onready var menu_list: VBoxContainer = $MenuList
@onready var btn_manager: Button = $MenuList/ManagerButton
@onready var btn_options: Button = $MenuList/OptionsButton
@onready var btn_quit: Button = $MenuList/QuitButton

@onready var options_menu: Control = $OptionsMenu
@onready var menu_music: AudioStreamPlayer = $MenuMusic

@onready var quit_dialog: ConfirmationDialog = $QuitDialog

var _last_focused_button: Button = null


func _ready() -> void:
	btn_manager.pressed.connect(_on_manager_pressed)
	btn_options.pressed.connect(_on_options_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

	options_menu.menu_closed.connect(_return_to_main_menu)

	quit_dialog.confirmed.connect(_on_quit_confirmed)
	quit_dialog.visibility_changed.connect(_on_quit_visibility_changed)

	_style_menu_buttons()
	_start_menu_music()
	btn_manager.grab_focus()


func _on_manager_pressed() -> void:
	# Entry point is the creation/slot screen, not the hub: it decides whether
	# to load an existing slot or start a new career, and only then hands off
	# to ManagerModeRoot with CareerManager already populated.
	get_tree().change_scene_to_file("res://ui/manager_mode/ManagerCreationScreen.tscn")


func _on_options_pressed() -> void:
	_last_focused_button = btn_options
	menu_list.hide()
	options_menu.open()


func _on_quit_pressed() -> void:
	_last_focused_button = btn_quit
	quit_dialog.popup_centered()


func _on_quit_confirmed() -> void:
	get_tree().quit()


func _on_quit_visibility_changed() -> void:
	if not quit_dialog.visible and is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()


func _return_to_main_menu() -> void:
	options_menu.hide()
	menu_list.show()
	if is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()
	else:
		btn_manager.grab_focus()


## Every button left here is a real, focusable destination — the pivot removed
## the styled-but-locked "Coming Soon" pattern along with the Player Career
## placeholder that used it.
func _style_menu_buttons() -> void:
	for button: Button in [btn_manager, btn_options, btn_quit]:
		button.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
		button.add_theme_color_override("font_color", TEXT_COLOR)
		button.add_theme_color_override("font_hover_color", ACCENT_COLOR)
		button.add_theme_color_override("font_pressed_color", ACCENT_COLOR)
		button.add_theme_color_override("font_focus_color", ACCENT_COLOR)
		button.add_theme_stylebox_override("normal", _make_stylebox(Color(0.0, 0.0, 0.0, 0.0), 0))
		button.add_theme_stylebox_override("hover", _make_stylebox(Color(0.24, 0.86, 0.41, 0.06), 4))
		button.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.24, 0.86, 0.41, 0.1), 4))
		button.add_theme_stylebox_override("focus", _make_stylebox(Color(0.24, 0.86, 0.41, 0.06), 4))


## OptionsMenu is an overlay shown/hidden inside this same scene (see class doc
## above), so this single player already covers both the main menu list and the
## options screen with no extra wiring.
func _start_menu_music() -> void:
	var stream: AudioStream = menu_music.stream
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	menu_music.play()


func _make_stylebox(bg_color: Color, left_border: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg_color
	box.border_width_left = left_border
	box.border_color = ACCENT_COLOR
	box.content_margin_left = 32.0
	box.content_margin_right = 32.0
	box.content_margin_top = 10.0
	box.content_margin_bottom = 10.0
	return box
