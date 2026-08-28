##
## MainMenu
##
## Entry point of the game (res://ui/MainMenu.tscn is run/main_scene). Owns the
## six top-level menu buttons and the small always-on-top popups (coming soon,
## quit confirmation); KickOffMenu and OptionsMenu are separate scenes instanced
## as children and shown/hidden as overlays rather than swapped scenes, so the
## menu list underneath never has to reload state.
##
## Depends on: GameManager, KickOffMenu, OptionsMenu.
## Exposes: nothing — this is a scene root, not a service other scripts call into.
##

extends Control

const MENU_FONT_SIZE: int = 22
const ACCENT_COLOR: Color = Color(0.24, 0.86, 0.41)
const TEXT_COLOR: Color = Color(0.909804, 0.941176, 0.913725)

@onready var menu_list: VBoxContainer = $MenuList
@onready var btn_kickoff: Button = $MenuList/KickOffButton
@onready var btn_practice: Button = $MenuList/PracticeButton
@onready var btn_manager: Button = $MenuList/ManagerButton
@onready var btn_career: Button = $MenuList/CareerButton
@onready var btn_options: Button = $MenuList/OptionsButton
@onready var btn_quit: Button = $MenuList/QuitButton

@onready var kickoff_menu: Control = $KickOffMenu
@onready var options_menu: Control = $OptionsMenu

@onready var coming_soon_dialog: AcceptDialog = $ComingSoonDialog
@onready var quit_dialog: ConfirmationDialog = $QuitDialog

var _last_focused_button: Button = null


func _ready() -> void:
	btn_kickoff.pressed.connect(_on_kickoff_pressed)
	btn_practice.pressed.connect(_on_practice_pressed)
	btn_manager.pressed.connect(_on_manager_pressed)
	btn_career.pressed.connect(_on_career_pressed)
	btn_options.pressed.connect(_on_options_pressed)
	btn_quit.pressed.connect(_on_quit_pressed)

	kickoff_menu.menu_closed.connect(_return_to_main_menu)
	options_menu.menu_closed.connect(_return_to_main_menu)

	coming_soon_dialog.visibility_changed.connect(_on_coming_soon_visibility_changed)
	quit_dialog.confirmed.connect(_on_quit_confirmed)
	quit_dialog.visibility_changed.connect(_on_quit_visibility_changed)

	_style_menu_buttons()
	btn_kickoff.grab_focus()


func _on_kickoff_pressed() -> void:
	_last_focused_button = btn_kickoff
	menu_list.hide()
	kickoff_menu.open()


func _on_practice_pressed() -> void:
	GameManager.match_duration = 300.0
	GameManager.set_meta(&"practice_mode", true)
	get_tree().change_scene_to_file("res://pitch/PitchScene.tscn")


func _on_manager_pressed() -> void:
	_show_coming_soon(btn_manager, "Manager Mode — Coming Soon")


func _on_career_pressed() -> void:
	_show_coming_soon(btn_career, "Player Career — Coming Soon")


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


func _show_coming_soon(source_button: Button, message: String) -> void:
	_last_focused_button = source_button
	coming_soon_dialog.dialog_text = message
	coming_soon_dialog.popup_centered()


func _on_coming_soon_visibility_changed() -> void:
	if not coming_soon_dialog.visible and is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()


func _return_to_main_menu() -> void:
	kickoff_menu.hide()
	options_menu.hide()
	menu_list.show()
	if is_instance_valid(_last_focused_button):
		_last_focused_button.grab_focus()
	else:
		btn_kickoff.grab_focus()


## Manager Mode and Player Career stay real, focusable, clickable buttons.
## Button.disabled would also swallow the "pressed" signal this needs to show
## the Coming Soon popup, so the locked look is styling only (dimmed alpha +
## the 🔒 already baked into the button text in MainMenu.tscn) rather than the
## engine's disabled state.
func _style_menu_buttons() -> void:
	for button: Button in [btn_kickoff, btn_practice, btn_manager, btn_career, btn_options, btn_quit]:
		button.add_theme_font_size_override("font_size", MENU_FONT_SIZE)
		button.add_theme_color_override("font_color", TEXT_COLOR)
		button.add_theme_color_override("font_hover_color", ACCENT_COLOR)
		button.add_theme_color_override("font_pressed_color", ACCENT_COLOR)
		button.add_theme_color_override("font_focus_color", ACCENT_COLOR)
		button.add_theme_stylebox_override("normal", _make_stylebox(Color(0.0, 0.0, 0.0, 0.0), 0))
		button.add_theme_stylebox_override("hover", _make_stylebox(Color(0.24, 0.86, 0.41, 0.06), 4))
		button.add_theme_stylebox_override("pressed", _make_stylebox(Color(0.24, 0.86, 0.41, 0.1), 4))
		button.add_theme_stylebox_override("focus", _make_stylebox(Color(0.24, 0.86, 0.41, 0.06), 4))

	btn_manager.modulate.a = 0.4
	btn_career.modulate.a = 0.4


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
