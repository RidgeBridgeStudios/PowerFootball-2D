extends CanvasLayer

const PLUS_ENABLED := "application/boot_splash+/general/enabled"
const PLUS_RUN_IN_EDITOR := "application/boot_splash+/general/run_in_editor_playtest"
const PLUS_WAIT_FOR_SCENE_LOAD := "application/boot_splash+/general/wait_for_scene_load"
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

var progress_fill: ColorRect
var screen_root: Control
var instant_cover: ColorRect
var background_image_node: TextureRect
var audio_player: AudioStreamPlayer
var logo_node: Control
var started_msec := 0


func _enter_tree() -> void:
	if not _should_run():
		return
	layer = 4096
	instant_cover = ColorRect.new()
	instant_cover.name = "BootSplashPlusInstantCover"
	instant_cover.color = ProjectSettings.get_setting(PLUS_BG_COLOR, Color(0.14, 0.14, 0.14, 1.0))
	instant_cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(instant_cover)


func _ready() -> void:
	if not _should_run():
		queue_free()
		return

	layer = 4096
	started_msec = Time.get_ticks_msec()
	_build_screen()
	_fade_in_screen()
	_play_sound()
	await _wait_for_scene_load()
	await _wait_minimum_time()
	await _fade_and_remove()


func _should_run() -> bool:
	if not ProjectSettings.get_setting(PLUS_ENABLED, true):
		return false
	if OS.has_feature("editor") and not ProjectSettings.get_setting(PLUS_RUN_IN_EDITOR, true):
		return false
	return true


func _build_screen() -> void:
	screen_root = Control.new()
	screen_root.name = "BootSplashPlusScreen"
	screen_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(screen_root)

	var background: ColorRect
	if instant_cover:
		remove_child(instant_cover)
		background = instant_cover
		instant_cover = null
	else:
		background = ColorRect.new()
		background.color = ProjectSettings.get_setting(PLUS_BG_COLOR, Color(0.14, 0.14, 0.14, 1.0))
		background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_root.add_child(background)

	var background_path := String(ProjectSettings.get_setting(PLUS_BG_IMAGE, "")).strip_edges()
	if int(ProjectSettings.get_setting(PLUS_BG_MODE, 0)) == 1 and _is_resource_file(background_path):
		_add_texture(screen_root, background_path, int(ProjectSettings.get_setting(PLUS_BG_FIT, 0)), true)
	call_deferred("_animate_background")

	var darken_amount: float = clampf(float(ProjectSettings.get_setting(PLUS_BG_DARKEN_AMOUNT, 0.0)), 0.0, 1.0)
	if darken_amount > 0.0:
		var darken := ColorRect.new()
		darken.color = Color(0, 0, 0, darken_amount)
		darken.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen_root.add_child(darken)

	var overlay_color: Color = ProjectSettings.get_setting(PLUS_OVERLAY_COLOR, Color(0, 0, 0, 0))
	if overlay_color.a > 0.0:
		var overlay := ColorRect.new()
		overlay.color = overlay_color
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		screen_root.add_child(overlay)

	var logo_type: int = int(ProjectSettings.get_setting(PLUS_LOGO_TYPE, 0))
	var logo_path: String = String(ProjectSettings.get_setting(PLUS_LOGO_IMAGE, "")).strip_edges()
	if logo_type == 0 and _is_resource_file(logo_path):
		_add_logo(screen_root, logo_path)
	elif ProjectSettings.get_setting(PLUS_SHOW_FALLBACK_LOGO, true):
		_add_fallback_logo(screen_root)
	call_deferred("_animate_logo")

	if ProjectSettings.get_setting(PLUS_SHOW_PROGRESS_BAR, true):
		_add_progress_bar(screen_root)


func _add_texture(parent: Control, path: String, fit_index: int, full_rect: bool) -> void:
	if not _is_resource_file(path):
		return

	var texture := ResourceLoader.load(path)
	if not texture is Texture2D:
		push_warning("Boot Splash+: could not load texture: %s" % path)
		return

	var rect := TextureRect.new()
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = _fit_to_stretch_mode(fit_index)
	if full_rect:
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		background_image_node = rect
		_apply_background_blur(rect)
	parent.add_child(rect)


func _add_logo(parent: Control, path: String) -> void:
	if not _is_resource_file(path):
		return

	var texture := ResourceLoader.load(path)
	if not texture is Texture2D:
		push_warning("Boot Splash+: could not load logo texture: %s" % path)
		return

	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(holder)

	var rect := TextureRect.new()
	logo_node = rect
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.modulate.a = clampf(float(ProjectSettings.get_setting(PLUS_LOGO_OPACITY, 1.0)), 0.0, 1.0)
	var size_percent := float(ProjectSettings.get_setting(PLUS_LOGO_SIZE, 35.0)) / 100.0
	rect.anchor_left = 0.5 - size_percent * 0.5
	rect.anchor_right = 0.5 + size_percent * 0.5
	rect.anchor_top = 0.35
	rect.anchor_bottom = 0.65
	match int(ProjectSettings.get_setting(PLUS_LOGO_POSITION, 0)):
		1:
			rect.anchor_top = 0.12
			rect.anchor_bottom = 0.42
		2:
			rect.anchor_top = 0.58
			rect.anchor_bottom = 0.88
	holder.add_child(rect)


func _add_fallback_logo(parent: Control) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(holder)

	var label := Label.new()
	logo_node = label
	label.modulate.a = clampf(float(ProjectSettings.get_setting(PLUS_LOGO_OPACITY, 1.0)), 0.0, 1.0)
	label.text = String(ProjectSettings.get_setting(PLUS_LOGO_TEXT, "Boot Splash+"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 56)
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	holder.add_child(label)


func _add_progress_bar(parent: Control) -> void:
	var width_percent: float = clampf(float(ProjectSettings.get_setting(PLUS_PROGRESS_BAR_WIDTH, 46.0)), 5.0, 100.0) / 100.0
	var half_width: float = width_percent * 0.5
	var left: float = 0.5 - half_width
	var right: float = 0.5 + half_width
	var y_anchor: float = _progress_bar_y_anchor()
	var height_px: int = max(1, int(ProjectSettings.get_setting(PLUS_PROGRESS_BAR_HEIGHT, 10)))

	var bg := ColorRect.new()
	bg.color = ProjectSettings.get_setting(PLUS_PROGRESS_BAR_BACKGROUND_COLOR, Color(1, 1, 1, 0.22))
	bg.anchor_left = left
	bg.anchor_right = right
	bg.anchor_top = y_anchor
	bg.anchor_bottom = y_anchor
	bg.offset_bottom = height_px
	parent.add_child(bg)

	progress_fill = ColorRect.new()
	progress_fill.color = ProjectSettings.get_setting(PLUS_PROGRESS_BAR_COLOR, Color(0.25, 0.55, 1.0, 1.0))
	progress_fill.anchor_left = left
	progress_fill.anchor_right = left
	progress_fill.anchor_top = y_anchor
	progress_fill.anchor_bottom = y_anchor
	progress_fill.offset_bottom = height_px
	parent.add_child(progress_fill)

	match int(ProjectSettings.get_setting(PLUS_PROGRESS_BAR_STYLE, 0)):
		1:
			_animate_progress_pulse()
		2:
			_animate_progress_blink()
		_:
			var tween := create_tween()
			tween.tween_method(_set_progress, 0.0, 1.0, max(0.2, float(ProjectSettings.get_setting(PLUS_MIN_TIME, 1.5))))


func _play_sound() -> void:
	var sound_path := String(ProjectSettings.get_setting(PLUS_SOUND, "")).strip_edges()
	if not _is_resource_file(sound_path):
		return

	var delay: float = maxf(0.0, float(ProjectSettings.get_setting(PLUS_SOUND_DELAY, 0.0)))
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout

	var stream := ResourceLoader.load(sound_path)
	if not stream is AudioStream:
		push_warning("Boot Splash+: could not load sound: %s" % sound_path)
		return

	audio_player = AudioStreamPlayer.new()
	audio_player.stream = stream
	audio_player.volume_db = float(ProjectSettings.get_setting(PLUS_SOUND_VOLUME_DB, 0.0))
	audio_player.pitch_scale = float(ProjectSettings.get_setting(PLUS_SOUND_PITCH_SCALE, 1.0))
	add_child(audio_player)

	var target_volume := audio_player.volume_db
	if ProjectSettings.get_setting(PLUS_SOUND_FADE_IN, true):
		audio_player.volume_db = -80.0
		audio_player.play()
		var tween := create_tween()
		tween.tween_property(audio_player, "volume_db", target_volume, float(ProjectSettings.get_setting(PLUS_SOUND_FADE_IN_TIME, 0.5)))
	else:
		audio_player.play()


func _fade_in_screen() -> void:
	var fade_time: float = maxf(0.0, float(ProjectSettings.get_setting(PLUS_FADE_IN_TIME, 0.0)))
	if fade_time <= 0.0 or not screen_root:
		return

	screen_root.modulate.a = 0.0
	create_tween().tween_property(screen_root, "modulate:a", 1.0, fade_time)


func _animate_background() -> void:
	if not background_image_node:
		return

	var animation: int = int(ProjectSettings.get_setting(PLUS_BG_ANIMATION, 0))
	if animation == 0:
		return

	var duration: float = maxf(0.5, float(ProjectSettings.get_setting(PLUS_BG_ANIMATION_DURATION, 4.0)))
	background_image_node.pivot_offset = background_image_node.size * 0.5

	match animation:
		1:
			background_image_node.scale = Vector2.ONE
			create_tween().tween_property(background_image_node, "scale", Vector2(1.08, 1.08), duration)
		2:
			background_image_node.scale = Vector2(1.08, 1.08)
			create_tween().tween_property(background_image_node, "scale", Vector2.ONE, duration)
		3:
			background_image_node.position.x = -12.0
			create_tween().tween_property(background_image_node, "position:x", 12.0, duration)


func _apply_background_blur(rect: TextureRect) -> void:
	var blur_amount: float = clampf(float(ProjectSettings.get_setting(PLUS_BG_BLUR_AMOUNT, 0.0)), 0.0, 8.0)
	if blur_amount <= 0.0:
		return

	var shader := Shader.new()
	shader.code = """
shader_type canvas_item;
uniform float blur_amount = 0.0;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur_amount;
	vec4 color = texture(TEXTURE, UV) * 0.36;
	color += texture(TEXTURE, UV + vec2(px.x, 0.0)) * 0.16;
	color += texture(TEXTURE, UV - vec2(px.x, 0.0)) * 0.16;
	color += texture(TEXTURE, UV + vec2(0.0, px.y)) * 0.16;
	color += texture(TEXTURE, UV - vec2(0.0, px.y)) * 0.16;
	COLOR = color;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("blur_amount", blur_amount)
	rect.material = material


func _animate_logo() -> void:
	if not logo_node:
		return

	var animation: int = int(ProjectSettings.get_setting(PLUS_LOGO_ANIMATION, 0))
	if animation == 0:
		return

	var duration: float = maxf(0.1, float(ProjectSettings.get_setting(PLUS_LOGO_ANIMATION_DURATION, 0.8)))
	var opacity: float = clampf(float(ProjectSettings.get_setting(PLUS_LOGO_OPACITY, 1.0)), 0.0, 1.0)
	logo_node.pivot_offset = logo_node.size * 0.5

	match animation:
		1:
			logo_node.modulate.a = 0.0
			create_tween().tween_property(logo_node, "modulate:a", opacity, duration)
		2:
			logo_node.modulate.a = 0.0
			var tween := create_tween().set_loops()
			tween.tween_property(logo_node, "modulate:a", opacity, duration)
			tween.tween_property(logo_node, "modulate:a", opacity * 0.25, duration)
		3:
			var tween := create_tween().set_loops()
			tween.tween_property(logo_node, "scale", Vector2(1.05, 1.05), duration * 0.5)
			tween.tween_property(logo_node, "scale", Vector2.ONE, duration * 0.5)
		4:
			logo_node.scale = Vector2(0.8, 0.8)
			create_tween().tween_property(logo_node, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		5:
			var tween := create_tween().set_loops()
			tween.tween_property(logo_node, "position:y", logo_node.position.y - 8.0, duration * 0.5)
			tween.tween_property(logo_node, "position:y", logo_node.position.y + 8.0, duration * 0.5)


func _animate_progress_pulse() -> void:
	if not progress_fill:
		return
	_set_progress(1.0)
	var tween := create_tween().set_loops()
	tween.tween_property(progress_fill, "modulate:a", 0.35, 0.45)
	tween.tween_property(progress_fill, "modulate:a", 1.0, 0.45)


func _animate_progress_blink() -> void:
	if not progress_fill:
		return
	_set_progress(1.0)
	var tween := create_tween().set_loops()
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void: progress_fill.visible = false)
	tween.tween_interval(0.35)
	tween.tween_callback(func() -> void: progress_fill.visible = true)


func _fit_to_stretch_mode(fit_index: int) -> TextureRect.StretchMode:
	match fit_index:
		1:
			return TextureRect.STRETCH_KEEP_ASPECT_CENTERED as TextureRect.StretchMode
		2:
			return TextureRect.STRETCH_SCALE as TextureRect.StretchMode
		3:
			return TextureRect.STRETCH_TILE as TextureRect.StretchMode
	return TextureRect.STRETCH_KEEP_ASPECT_COVERED as TextureRect.StretchMode


func _set_progress(value: float) -> void:
	if not progress_fill:
		return
	var width_percent: float = clampf(float(ProjectSettings.get_setting(PLUS_PROGRESS_BAR_WIDTH, 46.0)), 5.0, 100.0) / 100.0
	var left: float = 0.5 - width_percent * 0.5
	var right: float = 0.5 + width_percent * 0.5
	progress_fill.anchor_right = lerp(left, right, clamp(value, 0.0, 1.0))


func _progress_bar_y_anchor() -> float:
	match int(ProjectSettings.get_setting(PLUS_PROGRESS_BAR_POSITION, 0)):
		1:
			return 0.88
		2:
			return 0.96
		3:
			return 0.5
		4:
			return 0.18
	return 0.72


func _wait_minimum_time() -> void:
	var minimum_ms: int = int(float(ProjectSettings.get_setting(PLUS_MIN_TIME, 1.5)) * 1000.0)
	var elapsed: int = Time.get_ticks_msec() - started_msec
	var remaining: int = int(max(0, minimum_ms - elapsed))
	if remaining > 0:
		await get_tree().create_timer(float(remaining) / 1000.0).timeout


func _fade_and_remove() -> void:
	var fade_time := float(ProjectSettings.get_setting(PLUS_FADE_TIME, 0.25))
	await _fade_out_sound()
	if fade_time > 0.0 and screen_root:
		var tween := create_tween()
		tween.tween_property(screen_root, "modulate:a", 0.0, fade_time)
		await tween.finished
	queue_free()


func _fade_out_sound() -> void:
	if not audio_player or not audio_player.playing:
		return
	if not ProjectSettings.get_setting(PLUS_SOUND_FADE_OUT, true):
		audio_player.stop()
		return

	var fade_time := float(ProjectSettings.get_setting(PLUS_SOUND_FADE_OUT_TIME, 0.5))
	if fade_time <= 0.0:
		audio_player.stop()
		return

	var tween := create_tween()
	tween.tween_property(audio_player, "volume_db", -80.0, fade_time)
	await tween.finished
	if audio_player:
		audio_player.stop()


func _is_resource_file(path: String) -> bool:
	if path.is_empty() or path == "res://" or path == "user://":
		return false
	if path.begins_with("uid://"):
		return true
	if path.ends_with("/") or path.ends_with("\\"):
		return false
	if path.get_extension().is_empty():
		return false
	return path.begins_with("res://") or path.begins_with("user://")


func _wait_for_scene_load() -> void:
	if not ProjectSettings.get_setting(PLUS_WAIT_FOR_SCENE_LOAD, true):
		return

	while get_tree().current_scene == null:
		await get_tree().process_frame
	await get_tree().process_frame
