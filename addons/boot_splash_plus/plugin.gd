@tool
extends EditorPlugin

const AUTOLOAD_NAME := "BootSplashPlus"
const AUTOLOAD_PATH := "res://addons/boot_splash_plus/boot_splash_plus_runtime.gd"

const PLUS_ENABLED := "application/boot_splash+/general/enabled"
const PLUS_RUN_IN_EDITOR := "application/boot_splash+/general/run_in_editor_playtest"
const PLUS_WAIT_FOR_SCENE_LOAD := "application/boot_splash+/general/wait_for_scene_load"
const PLUS_DISABLE_NATIVE_SPLASH := "application/boot_splash+/native_splash/disable_native_boot_splash_not_completely"
const PLUS_SCENE_LOADER_ENABLED := "application/boot_splash+/scene_loader/use_as_main_scene"
const PLUS_SCENE_LOADER_TARGET := "application/boot_splash+/scene_loader/target_scene"
const PLUS_MIN_TIME := "application/boot_splash+/timing/minimum_display_time_seconds"
const PLUS_FADE_IN_TIME := "application/boot_splash+/timing/fade_in_time"
const PLUS_FADE_TIME := "application/boot_splash+/timing/fade_out_time"
const PLUS_BG_MODE := "application/boot_splash+/background/mode"
const PLUS_BG_COLOR := "application/boot_splash+/background/color"
const PLUS_BG_IMAGE := "application/boot_splash+/background/image"
const PLUS_BG_FIT := "application/boot_splash+/background/fit"
const PLUS_BG_ANIMATION := "application/boot_splash+/background/animation"
const PLUS_BG_ANIMATION_DURATION := "application/boot_splash+/background/animation_duration"
const PLUS_BG_BLUR_AMOUNT := "application/boot_splash+/background/blur_amount"
const PLUS_BG_DARKEN_AMOUNT := "application/boot_splash+/background/darken_amount"
const PLUS_OVERLAY_COLOR := "application/boot_splash+/background/overlay_color"
const PLUS_LOGO_TYPE := "application/boot_splash+/logo/logo_type"
const PLUS_LOGO_TEXT := "application/boot_splash+/logo/text"
const PLUS_LOGO_IMAGE := "application/boot_splash+/logo/image"
const PLUS_LOGO_SIZE := "application/boot_splash+/logo/size_percent"
const PLUS_LOGO_POSITION := "application/boot_splash+/logo/position"
const PLUS_LOGO_OPACITY := "application/boot_splash+/logo/opacity"
const PLUS_SHOW_FALLBACK_LOGO := "application/boot_splash+/logo/show_fallback_logo"
const PLUS_LOGO_ANIMATION := "application/boot_splash+/logo/animation"
const PLUS_LOGO_ANIMATION_DURATION := "application/boot_splash+/logo/animation_duration"
const PLUS_SHOW_PROGRESS_BAR := "application/boot_splash+/progress_bar/show"
const PLUS_PROGRESS_BAR_POSITION := "application/boot_splash+/progress_bar/position"
const PLUS_PROGRESS_BAR_WIDTH := "application/boot_splash+/progress_bar/width_percent"
const PLUS_PROGRESS_BAR_HEIGHT := "application/boot_splash+/progress_bar/height_px"
const PLUS_PROGRESS_BAR_STYLE := "application/boot_splash+/progress_bar/style"
const PLUS_PROGRESS_BAR_COLOR := "application/boot_splash+/progress_bar/color"
const PLUS_PROGRESS_BAR_BACKGROUND_COLOR := "application/boot_splash+/progress_bar/background_color"
const PLUS_SOUND := "application/boot_splash+/sound/file"
const PLUS_SOUND_VOLUME_DB := "application/boot_splash+/sound/volume_db"
const PLUS_SOUND_PITCH_SCALE := "application/boot_splash+/sound/pitch_scale"
const PLUS_SOUND_DELAY := "application/boot_splash+/sound/delay_seconds"
const PLUS_SOUND_FADE_IN := "application/boot_splash+/sound/fade_in"
const PLUS_SOUND_FADE_IN_TIME := "application/boot_splash+/sound/fade_in_time"
const PLUS_SOUND_FADE_OUT := "application/boot_splash+/sound/fade_out"
const PLUS_SOUND_FADE_OUT_TIME := "application/boot_splash+/sound/fade_out_time"


func _enter_tree() -> void:
	_register_project_settings()
	_cleanup_old_settings()
	_apply_native_splash_settings()
	_sync_autoload()


func _exit_tree() -> void:
	if ProjectSettings.has_setting("autoload/%s" % AUTOLOAD_NAME):
		remove_autoload_singleton(AUTOLOAD_NAME)


func _register_project_settings() -> void:
	_register_setting(PLUS_ENABLED, TYPE_BOOL, _migrated_values(["application/boot_splash+/enabled", "application/boot_splash/plus:_preview_in_playtest"], true))
	_register_setting(PLUS_RUN_IN_EDITOR, TYPE_BOOL, _migrated_value("application/boot_splash+/run_in_editor_playtest", true))
	_register_setting(PLUS_WAIT_FOR_SCENE_LOAD, TYPE_BOOL, _migrated_value("application/boot_splash+/wait_for_scene_load", true))
	_register_setting(PLUS_DISABLE_NATIVE_SPLASH, TYPE_BOOL, _migrated_values(["application/boot_splash+/native_splash/disable_native_boot_splash", "application/boot_splash+/disable_native_boot_splash"], true))
	_register_setting(PLUS_SCENE_LOADER_ENABLED, TYPE_BOOL, _migrated_value("application/boot_splash+/use_scene_loader", false))
	_register_setting(PLUS_SCENE_LOADER_TARGET, TYPE_STRING, _migrated_value("application/boot_splash+/target_scene", ""), PROPERTY_HINT_FILE, "*.tscn,*.scn")
	_register_setting(PLUS_MIN_TIME, TYPE_FLOAT, _minimum_seconds_default(), PROPERTY_HINT_RANGE, "0,60,0.1,or_greater")
	_register_setting(PLUS_FADE_IN_TIME, TYPE_FLOAT, _migrated_value("application/boot_splash+/fade_in_time", 0.0), PROPERTY_HINT_RANGE, "0,5,0.05,or_greater")
	_register_setting(PLUS_FADE_TIME, TYPE_FLOAT, _migrated_value("application/boot_splash+/fade_out_time", 0.25), PROPERTY_HINT_RANGE, "0,5,0.05,or_greater")
	_register_setting(PLUS_BG_MODE, TYPE_INT, _migrated_values(["application/boot_splash+/background_mode", "application/boot_splash/plus:_background_mode"], 0), PROPERTY_HINT_ENUM, "Color,Image")
	_register_setting(PLUS_BG_COLOR, TYPE_COLOR, _migrated_value("application/boot_splash+/background_color", ProjectSettings.get_setting("application/boot_splash/bg_color", Color(0.14, 0.14, 0.14, 1.0))))
	_register_setting(PLUS_BG_IMAGE, TYPE_STRING, _migrated_values(["application/boot_splash+/background_image", "application/boot_splash/plus:_background_image"], ""), PROPERTY_HINT_FILE, "*.png,*.webp,*.jpg,*.jpeg")
	_register_setting(PLUS_BG_FIT, TYPE_INT, _migrated_values(["application/boot_splash+/background_fit", "application/boot_splash/plus:_background_fit"], 0), PROPERTY_HINT_ENUM, "Cover,Contain,Stretch,Tile")
	_register_setting(PLUS_BG_ANIMATION, TYPE_INT, _migrated_value("application/boot_splash+/background_animation", 0), PROPERTY_HINT_ENUM, "None,Slow Zoom In,Slow Zoom Out,Slow Pan")
	_register_setting(PLUS_BG_ANIMATION_DURATION, TYPE_FLOAT, _migrated_value("application/boot_splash+/background_animation_duration", 4.0), PROPERTY_HINT_RANGE, "0.5,30,0.1,or_greater")
	_register_setting(PLUS_BG_BLUR_AMOUNT, TYPE_FLOAT, _migrated_value("application/boot_splash+/background_blur_amount", 0.0), PROPERTY_HINT_RANGE, "0,8,0.5")
	_register_setting(PLUS_BG_DARKEN_AMOUNT, TYPE_FLOAT, _migrated_value("application/boot_splash+/background_darken_amount", 0.0), PROPERTY_HINT_RANGE, "0,1,0.05")
	_register_setting(PLUS_OVERLAY_COLOR, TYPE_COLOR, _migrated_values(["application/boot_splash+/overlay_color", "application/boot_splash/plus:_overlay_color"], Color(0, 0, 0, 0)))
	_register_setting(PLUS_LOGO_TYPE, TYPE_INT, _migrated_value("application/boot_splash+/logo_type", 0), PROPERTY_HINT_ENUM, "Logo,Text")
	_register_setting(PLUS_LOGO_TEXT, TYPE_STRING, _migrated_value("application/boot_splash+/logo_text", "Boot Splash+"))
	_register_setting(PLUS_LOGO_IMAGE, TYPE_STRING, _migrated_values(["application/boot_splash+/logo_image", "application/boot_splash/plus:_logo_image"], ""), PROPERTY_HINT_FILE, "*.png,*.webp,*.jpg,*.jpeg,*.svg")
	_register_setting(PLUS_LOGO_SIZE, TYPE_FLOAT, _migrated_values(["application/boot_splash+/logo_size_percent", "application/boot_splash/plus:_logo_size_percent"], 35.0), PROPERTY_HINT_RANGE, "5,90,1")
	_register_setting(PLUS_LOGO_POSITION, TYPE_INT, _migrated_values(["application/boot_splash+/logo_position", "application/boot_splash/plus:_logo_position"], 0), PROPERTY_HINT_ENUM, "Center,Top,Bottom")
	_register_setting(PLUS_LOGO_OPACITY, TYPE_FLOAT, _migrated_value("application/boot_splash+/logo_opacity", 1.0), PROPERTY_HINT_RANGE, "0,1,0.05")
	_register_setting(PLUS_SHOW_FALLBACK_LOGO, TYPE_BOOL, _migrated_values(["application/boot_splash+/show_fallback_logo", "application/boot_splash/plus:_show_fallback_logo"], true))
	_register_setting(PLUS_LOGO_ANIMATION, TYPE_INT, _migrated_value("application/boot_splash+/logo_animation", 0), PROPERTY_HINT_ENUM, "None,Fade In,Fade In Out,Pulse,Scale In,Slight Float")
	_register_setting(PLUS_LOGO_ANIMATION_DURATION, TYPE_FLOAT, _migrated_value("application/boot_splash+/logo_animation_duration", 0.8), PROPERTY_HINT_RANGE, "0.1,10,0.1,or_greater")
	_register_setting(PLUS_SHOW_PROGRESS_BAR, TYPE_BOOL, _migrated_values(["application/boot_splash+/show_progress_bar", "application/boot_splash/plus:_show_progress_bar"], true))
	_register_setting(PLUS_PROGRESS_BAR_POSITION, TYPE_INT, _migrated_value("application/boot_splash+/progress_bar_position", 0), PROPERTY_HINT_ENUM, "Lower Middle,Bottom,More Bottom,Center,Top")
	_register_setting(PLUS_PROGRESS_BAR_WIDTH, TYPE_FLOAT, _migrated_value("application/boot_splash+/progress_bar_width_percent", 46.0), PROPERTY_HINT_RANGE, "5,100,1")
	_register_setting(PLUS_PROGRESS_BAR_HEIGHT, TYPE_INT, _migrated_value("application/boot_splash+/progress_bar_height_px", 10), PROPERTY_HINT_RANGE, "1,100,1,or_greater")
	_register_setting(PLUS_PROGRESS_BAR_STYLE, TYPE_INT, _migrated_value("application/boot_splash+/progress_bar_style", 0), PROPERTY_HINT_ENUM, "Fill,Pulse,Blink")
	_register_setting(PLUS_PROGRESS_BAR_COLOR, TYPE_COLOR, _migrated_values(["application/boot_splash+/progress_bar_color", "application/boot_splash/plus:_progress_bar_color"], Color(0.25, 0.55, 1.0, 1.0)))
	_register_setting(PLUS_PROGRESS_BAR_BACKGROUND_COLOR, TYPE_COLOR, _migrated_values(["application/boot_splash+/progress_bar_background_color", "application/boot_splash/plus:_progress_bar_background_color"], Color(1, 1, 1, 0.22)))
	_register_setting(PLUS_SOUND, TYPE_STRING, _migrated_value("application/boot_splash+/sound", ""), PROPERTY_HINT_FILE, "*.wav,*.ogg,*.mp3")
	_register_setting(PLUS_SOUND_VOLUME_DB, TYPE_FLOAT, _migrated_value("application/boot_splash+/sound_volume_db", 0.0), PROPERTY_HINT_RANGE, "-80,24,0.5")
	_register_setting(PLUS_SOUND_PITCH_SCALE, TYPE_FLOAT, _migrated_value("application/boot_splash+/sound_pitch_scale", 1.0), PROPERTY_HINT_RANGE, "0.25,4,0.05,or_greater")
	_register_setting(PLUS_SOUND_DELAY, TYPE_FLOAT, _migrated_value("application/boot_splash+/sound_delay_seconds", 0.0), PROPERTY_HINT_RANGE, "0,10,0.1,or_greater")
	_register_setting(PLUS_SOUND_FADE_IN, TYPE_BOOL, _migrated_value("application/boot_splash+/fade_in_sound", true))
	_register_setting(PLUS_SOUND_FADE_IN_TIME, TYPE_FLOAT, _migrated_value("application/boot_splash+/sound_fade_in_time", 0.5), PROPERTY_HINT_RANGE, "0,10,0.1,or_greater")
	_register_setting(PLUS_SOUND_FADE_OUT, TYPE_BOOL, _migrated_value("application/boot_splash+/fade_out_sound", true))
	_register_setting(PLUS_SOUND_FADE_OUT_TIME, TYPE_FLOAT, _migrated_value("application/boot_splash+/sound_fade_out_time", 0.5), PROPERTY_HINT_RANGE, "0,10,0.1,or_greater")
	_apply_setting_order()


func _apply_setting_order() -> void:
	var native_paths: Array[String] = [
		"application/boot_splash/bg_color",
		"application/boot_splash/fullsize",
		"application/boot_splash/image",
		"application/boot_splash/minimum_display_time",
		"application/boot_splash/show_image",
		"application/boot_splash/use_filter",
	]
	var base_order: int = 0
	for native_path in native_paths:
		if ProjectSettings.has_setting(native_path):
			base_order = maxi(base_order, int(ProjectSettings.get_order(native_path)) + 1)

	var ordered_paths: Array[String] = [
		PLUS_ENABLED,
		PLUS_RUN_IN_EDITOR,
		PLUS_WAIT_FOR_SCENE_LOAD,
		PLUS_SCENE_LOADER_ENABLED,
		PLUS_SCENE_LOADER_TARGET,
		PLUS_DISABLE_NATIVE_SPLASH,
		PLUS_MIN_TIME,
		PLUS_FADE_IN_TIME,
		PLUS_FADE_TIME,
		PLUS_BG_MODE,
		PLUS_BG_COLOR,
		PLUS_BG_IMAGE,
		PLUS_BG_FIT,
		PLUS_BG_ANIMATION,
		PLUS_BG_ANIMATION_DURATION,
		PLUS_BG_BLUR_AMOUNT,
		PLUS_BG_DARKEN_AMOUNT,
		PLUS_OVERLAY_COLOR,
		PLUS_LOGO_TYPE,
		PLUS_LOGO_TEXT,
		PLUS_LOGO_IMAGE,
		PLUS_LOGO_SIZE,
		PLUS_LOGO_POSITION,
		PLUS_LOGO_OPACITY,
		PLUS_SHOW_FALLBACK_LOGO,
		PLUS_LOGO_ANIMATION,
		PLUS_LOGO_ANIMATION_DURATION,
		PLUS_SHOW_PROGRESS_BAR,
		PLUS_PROGRESS_BAR_POSITION,
		PLUS_PROGRESS_BAR_WIDTH,
		PLUS_PROGRESS_BAR_HEIGHT,
		PLUS_PROGRESS_BAR_STYLE,
		PLUS_PROGRESS_BAR_COLOR,
		PLUS_PROGRESS_BAR_BACKGROUND_COLOR,
		PLUS_SOUND,
		PLUS_SOUND_VOLUME_DB,
		PLUS_SOUND_PITCH_SCALE,
		PLUS_SOUND_DELAY,
		PLUS_SOUND_FADE_IN,
		PLUS_SOUND_FADE_IN_TIME,
		PLUS_SOUND_FADE_OUT,
		PLUS_SOUND_FADE_OUT_TIME,
	]

	var index: int = 0
	while index < ordered_paths.size():
		ProjectSettings.set_order(ordered_paths[index], base_order + index)
		index += 1


func _cleanup_old_settings() -> void:
	var old_paths: Array[String] = [
		"application/boot_splash+/native_splash/disable_native_boot_splash",
		"application/boot_splash+/disable_native_boot_splash",
	]
	var changed: bool = false
	for old_path in old_paths:
		if ProjectSettings.has_setting(old_path):
			ProjectSettings.clear(old_path)
			changed = true

	if changed:
		ProjectSettings.save()

func _sync_autoload() -> void:
	var autoload_path := "autoload/%s" % AUTOLOAD_NAME
	if bool(ProjectSettings.get_setting(PLUS_SCENE_LOADER_ENABLED, false)):
		if ProjectSettings.has_setting(autoload_path):
			remove_autoload_singleton(AUTOLOAD_NAME)
		return

	if not ProjectSettings.has_setting(autoload_path):
		add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)

func _apply_native_splash_settings() -> void:
	if not bool(ProjectSettings.get_setting(PLUS_DISABLE_NATIVE_SPLASH, true)):
		return

	var changed: bool = false
	if bool(ProjectSettings.get_setting("application/boot_splash/show_image", true)):
		ProjectSettings.set_setting("application/boot_splash/show_image", false)
		changed = true

	if changed:
		ProjectSettings.save()


func _register_setting(path: String, type: int, default_value: Variant, hint := PROPERTY_HINT_NONE, hint_string := "") -> void:
	if not ProjectSettings.has_setting(path):
		ProjectSettings.set_setting(path, default_value)
	ProjectSettings.set_initial_value(path, default_value)

	var property_info: Dictionary = {
		"name": path,
		"type": type,
		"hint": hint,
		"hint_string": hint_string,
	}
	var description: String = _setting_description(path)
	if not description.is_empty():
		property_info["description"] = description
	ProjectSettings.add_property_info(property_info)

func _setting_description(path: String) -> String:
	match path:
		PLUS_ENABLED:
			return "Enables or disables the Boot Splash+ loading screen."
		PLUS_RUN_IN_EDITOR:
			return "Shows Boot Splash+ when running the project from the editor."
		PLUS_WAIT_FOR_SCENE_LOAD:
			return "Keeps the splash visible until the first scene has entered the tree."
		PLUS_DISABLE_NATIVE_SPLASH:
			return "Disables Godot's native splash image, but cannot remove the earliest engine loading stage."
		PLUS_SCENE_LOADER_ENABLED:
			return "Use the included Boot Splash+ loader scene as the project main scene. Default is off."
		PLUS_SCENE_LOADER_TARGET:
			return "Scene loaded after the Boot Splash+ loader scene finishes."
		PLUS_MIN_TIME:
			return "Minimum time, in seconds, that Boot Splash+ remains visible."
		PLUS_FADE_IN_TIME:
			return "Time, in seconds, for the splash screen to fade in."
		PLUS_FADE_TIME:
			return "Time, in seconds, for the splash screen to fade out."
		PLUS_BG_MODE:
			return "Choose whether the splash background uses a solid color or an image."
		PLUS_BG_COLOR:
			return "Solid background color used by the splash screen."
		PLUS_BG_IMAGE:
			return "Image used as the splash background when Background Mode is Image."
		PLUS_BG_FIT:
			return "Controls how the background image fits the game window."
		PLUS_BG_ANIMATION:
			return "Optional motion effect for the background image."
		PLUS_BG_ANIMATION_DURATION:
			return "Duration, in seconds, of the background animation."
		PLUS_BG_BLUR_AMOUNT:
			return "Blur amount applied to the background image."
		PLUS_BG_DARKEN_AMOUNT:
			return "Darkens the background to improve logo and progress bar visibility."
		PLUS_OVERLAY_COLOR:
			return "Optional color overlay drawn above the background."
		PLUS_LOGO_TYPE:
			return "Choose whether the splash center uses a logo image or text."
		PLUS_LOGO_TEXT:
			return "Text shown when Logo Type is Text or no valid logo image is available."
		PLUS_LOGO_IMAGE:
			return "Logo image shown when Logo Type is Logo."
		PLUS_LOGO_SIZE:
			return "Logo width as a percentage of the screen."
		PLUS_LOGO_POSITION:
			return "Vertical placement of the logo or fallback text."
		PLUS_LOGO_OPACITY:
			return "Opacity of the logo or fallback text."
		PLUS_SHOW_FALLBACK_LOGO:
			return "Shows fallback text when no valid logo image can be displayed."
		PLUS_LOGO_ANIMATION:
			return "Optional animation applied to the logo or fallback text."
		PLUS_LOGO_ANIMATION_DURATION:
			return "Duration, in seconds, of the logo animation."
		PLUS_SHOW_PROGRESS_BAR:
			return "Shows or hides the splash progress bar."
		PLUS_PROGRESS_BAR_POSITION:
			return "Placement of the progress bar on the screen."
		PLUS_PROGRESS_BAR_WIDTH:
			return "Progress bar width as a percentage of the screen."
		PLUS_PROGRESS_BAR_HEIGHT:
			return "Progress bar height in pixels."
		PLUS_PROGRESS_BAR_STYLE:
			return "Visual behavior of the progress bar."
		PLUS_PROGRESS_BAR_COLOR:
			return "Filled color of the progress bar."
		PLUS_PROGRESS_BAR_BACKGROUND_COLOR:
			return "Background color behind the progress bar fill."
		PLUS_SOUND:
			return "Audio file played while the splash screen is visible."
		PLUS_SOUND_VOLUME_DB:
			return "Splash sound volume in decibels."
		PLUS_SOUND_PITCH_SCALE:
			return "Playback pitch multiplier for the splash sound."
		PLUS_SOUND_DELAY:
			return "Delay, in seconds, before the splash sound starts."
		PLUS_SOUND_FADE_IN:
			return "Fades the splash sound in when it starts."
		PLUS_SOUND_FADE_IN_TIME:
			return "Time, in seconds, for the splash sound fade in."
		PLUS_SOUND_FADE_OUT:
			return "Fades the splash sound out before the splash ends."
		PLUS_SOUND_FADE_OUT_TIME:
			return "Time, in seconds, for the splash sound fade out."
	return ""

func _migrated_value(old_path: String, default_value: Variant) -> Variant:
	if ProjectSettings.has_setting(old_path):
		return ProjectSettings.get_setting(old_path, default_value)
	return default_value

func _migrated_values(old_paths: Array, default_value: Variant) -> Variant:
	for old_path in old_paths:
		if ProjectSettings.has_setting(old_path):
			return ProjectSettings.get_setting(old_path, default_value)
	return default_value


func _minimum_seconds_default() -> float:
	if ProjectSettings.has_setting("application/boot_splash+/minimum_display_time_seconds"):
		return float(ProjectSettings.get_setting("application/boot_splash+/minimum_display_time_seconds", 1.5))
	if ProjectSettings.has_setting("application/boot_splash+/minimum_display_time"):
		return float(ProjectSettings.get_setting("application/boot_splash+/minimum_display_time", 1500)) / 1000.0
	return 1.5
