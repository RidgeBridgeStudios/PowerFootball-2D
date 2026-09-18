class_name InjuryEvent
extends SimEvent

var player_name: String = ""
var injury_type: String = ""
var days_out: int = 0

func _init(p_date: Dictionary = {}, p_player_name: String = "Player", p_injury: String = "Hamstring Strain", p_days: int = 14) -> void:
	var t: String = "Injury: " + p_player_name
	var d: String = "%s has sustained a %s and will be sidelined for ~%d days." % [p_player_name, p_injury, p_days]
	super(p_date, Priority.Type.URGENT, t, d)
	player_name = p_player_name
	injury_type = p_injury
	days_out = p_days

func serialize() -> Dictionary:
	var data: Dictionary = super.serialize()
	data["player_name"] = player_name
	data["injury_type"] = injury_type
	data["days_out"] = days_out
	return data

func deserialize(data: Dictionary) -> void:
	super.deserialize(data)
	player_name = data.get("player_name", "")
	injury_type = data.get("injury_type", "")
	days_out = data.get("days_out", 0)
