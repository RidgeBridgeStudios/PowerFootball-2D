class_name MatchEvent
extends SimEvent

var opponent: String = ""
var home_match: bool = true

func _init(p_date: Dictionary = {}, p_opponent: String = "Opponent FC", p_home: bool = true, p_title: String = "", p_desc: String = "") -> void:
	var t: String = p_title if not p_title.is_empty() else ("Matchday vs " + p_opponent)
	var d: String = p_desc if not p_desc.is_empty() else ("League fixture against " + p_opponent)
	super(p_date, Priority.Type.BLOCKING, t, d)
	opponent = p_opponent
	home_match = p_home

func get_screen() -> PackedScene:
	return null

func serialize() -> Dictionary:
	var data: Dictionary = super.serialize()
	data["opponent"] = opponent
	data["home_match"] = home_match
	return data

func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	opponent = data.get("opponent", "")
	home_match = data.get("home_match", true)
