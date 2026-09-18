extends "res://addons/boot_splash_plus/boot_splash_plus_runtime.gd"

const PLUS_SCENE_LOADER_TARGET := "application/boot_splash+/scene_loader/target_scene"


func _ready() -> void:
	if not _should_run():
		queue_free()
		return

	layer = 4096
	started_msec = Time.get_ticks_msec()
	_build_screen()
	_fade_in_screen()
	_play_sound()

	var target_scene: String = String(ProjectSettings.get_setting(PLUS_SCENE_LOADER_TARGET, "")).strip_edges()
	if not _is_resource_file(target_scene):
		push_error("Boot Splash+: Scene Loader target scene is empty or invalid.")
		await _wait_minimum_time()
		await _fade_and_remove()
		return

	var load_error: Error = ResourceLoader.load_threaded_request(target_scene) as Error
	if load_error != OK:
		push_error("Boot Splash+: could not start loading target scene: %s" % target_scene)
		await _wait_minimum_time()
		await _fade_and_remove()
		return

	await _wait_for_threaded_scene(target_scene)
	await _wait_minimum_time()
	await _fade_out_sound()
	await _fade_screen_root()

	var loaded_scene: Resource = ResourceLoader.load_threaded_get(target_scene)
	if loaded_scene is PackedScene:
		get_tree().change_scene_to_packed(loaded_scene)
	else:
		push_error("Boot Splash+: target scene did not load as a PackedScene: %s" % target_scene)
		queue_free()


func _wait_for_threaded_scene(target_scene: String) -> void:
	var progress: Array = []
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(target_scene, progress) as ResourceLoader.ThreadLoadStatus
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if progress.size() > 0:
			_set_progress(float(progress[0]))
		await get_tree().process_frame
		progress.clear()
		status = ResourceLoader.load_threaded_get_status(target_scene, progress) as ResourceLoader.ThreadLoadStatus

	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_set_progress(1.0)
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("Boot Splash+: target scene failed to load: %s" % target_scene)


func _fade_screen_root() -> void:
	var fade_time: float = maxf(0.0, float(ProjectSettings.get_setting(PLUS_FADE_TIME, 0.25)))
	if fade_time > 0.0 and screen_root:
		var tween: Tween = create_tween()
		tween.tween_property(screen_root, "modulate:a", 0.0, fade_time)
		await tween.finished