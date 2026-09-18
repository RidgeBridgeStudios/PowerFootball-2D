class_name Jukebox
extends VBoxContainer

##
## Jukebox
##
## Reusable UI component that lists available music tracks from MusicLibrary.
## Dynamically populates checkboxes for each track and maintains an internal
## active playlist of AudioStream resources.
##

signal playlist_changed(active_playlist: Array[AudioStream])

var _active_playlist: Array[AudioStream] = []


func _ready() -> void:
	add_theme_constant_override(&"separation", 6)
	_populate_tracks()


func _populate_tracks() -> void:
	for i: int in range(MusicLibrary.TRACKS.size()):
		var track: Dictionary = MusicLibrary.TRACKS[i]
		var track_name: String = str(track.get("name", "Unknown Track"))
		var stream: AudioStream = track.get("stream", null) as AudioStream
		var checkbox := CheckBox.new()
		checkbox.text = track_name
		if i == 0 and stream != null:
			checkbox.set_pressed_no_signal(true)
			_active_playlist.append(stream)
		checkbox.toggled.connect(_on_track_toggled.bind(stream))
		add_child(checkbox)


func _on_track_toggled(button_pressed: bool, stream: AudioStream) -> void:
	if stream == null:
		return
	if button_pressed:
		if not _active_playlist.has(stream):
			_active_playlist.append(stream)
	else:
		_active_playlist.erase(stream)
	_log_active_playlist()
	playlist_changed.emit(_active_playlist)


## Placeholder method logging the active playlist.
## AudioHost natively manages single streamed buses (PlayMusic / PlayStream).
## Once multi-track playlist queuing or shuffle is integrated with AudioHost,
## the playback trigger should be adapted here.
func _log_active_playlist() -> void:
	var track_paths: Array[String] = []
	for s: AudioStream in _active_playlist:
		if s != null:
			track_paths.append(s.resource_path)
	print("[Jukebox] Active playlist (%d tracks): %s" % [
		_active_playlist.size(),
		", ".join(track_paths) if not track_paths.is_empty() else "Empty"
	])


func get_active_playlist() -> Array[AudioStream]:
	return _active_playlist
