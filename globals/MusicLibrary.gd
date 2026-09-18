class_name MusicLibrary
extends RefCounted

## Global Music Library containing track definitions for the Jukebox.
## Each track dictionary contains a "name" (String) and "stream" (AudioStream).

const TRACKS: Array[Dictionary] = [
	{
		"name": "Menu Theme",
		"stream": preload("res://audio/menu_theme.wav"),
	},
	{
		"name": "Track 1 - Menu Beats",
		"stream": preload("res://audio/music/track_1.ogg"),
	},
	{
		"name": "Track 2 - Victory Groove",
		"stream": preload("res://audio/music/track_2.ogg"),
	},
	{
		"name": "Track 3 - Stadium Pulse",
		"stream": preload("res://audio/music/track_3.ogg"),
	},
]
