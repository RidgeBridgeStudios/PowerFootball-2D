##
## FormationLibrary
##
## Pure static utility — no instance needed, call FormationLibrary.get_formation()
## directly. Provides canonical formation layouts as an Array[Dictionary], one
## entry per player (11 total including the goalkeeper at index 0). Each entry
## has exactly two keys: "role" (String) and "anchor_offset" (Vector2), an
## offset from the pitch centre in pixels for Team A (attacking right).
## ManagerDirector mirrors both axes of anchor_offset for Team B.
##
## Coordinate system: pitch is 1920x1080px, origin at the pitch centre.
## Positive X = right, positive Y = down.
##
## Depends on: nothing.
## Exposes: get_formation(name).
##

class_name FormationLibrary
extends RefCounted


static func get_formation(name: String) -> Array[Dictionary]:
	match name:
		"4-4-2":
			return _442()
		"4-3-3":
			return _433()
		"3-5-2":
			return _352()
		"4-2-3-1":
			return _4231()
		"4-4-2 Diamond":
			return _442_diamond()
		"4-1-4-1":
			return _4141()
		"5-3-2":
			return _532()
		_:
			push_warning("FormationLibrary: unknown formation '%s', defaulting to 4-4-2." % name)
			return _442()


static func _slot(role: String, offset: Vector2) -> Dictionary:
	return {"role": role, "anchor_offset": offset}


static func _442() -> Array[Dictionary]:
	return [
		_slot("GK", Vector2(-750.0, 0.0)),
		_slot("CB", Vector2(-550.0, -120.0)),
		_slot("CB", Vector2(-550.0, 120.0)),
		_slot("LB", Vector2(-520.0, -320.0)),
		_slot("RB", Vector2(-520.0, 320.0)),
		_slot("CM", Vector2(-150.0, -100.0)),
		_slot("CM", Vector2(-150.0, 100.0)),
		_slot("LW", Vector2(-100.0, -340.0)),
		_slot("RW", Vector2(-100.0, 340.0)),
		_slot("ST", Vector2(500.0, -80.0)),
		_slot("ST", Vector2(500.0, 80.0)),
	]


static func _433() -> Array[Dictionary]:
	return [
		_slot("GK", Vector2(-750.0, 0.0)),
		_slot("CB", Vector2(-550.0, -120.0)),
		_slot("CB", Vector2(-550.0, 120.0)),
		_slot("LB", Vector2(-520.0, -320.0)),
		_slot("RB", Vector2(-520.0, 320.0)),
		_slot("DM", Vector2(-250.0, 0.0)),
		_slot("CM", Vector2(-50.0, -150.0)),
		_slot("CM", Vector2(-50.0, 150.0)),
		_slot("LW", Vector2(400.0, -340.0)),
		_slot("RW", Vector2(400.0, 340.0)),
		_slot("ST", Vector2(650.0, 0.0)),
	]


static func _352() -> Array[Dictionary]:
	return [
		_slot("GK", Vector2(-750.0, 0.0)),
		_slot("CB", Vector2(-550.0, -180.0)),
		_slot("CB", Vector2(-550.0, 0.0)),
		_slot("CB", Vector2(-550.0, 180.0)),
		_slot("DM", Vector2(-250.0, -100.0)),
		_slot("DM", Vector2(-250.0, 100.0)),
		_slot("CM", Vector2(-100.0, 0.0)),
		_slot("LW", Vector2(100.0, -340.0)),
		_slot("RW", Vector2(100.0, 340.0)),
		_slot("ST", Vector2(550.0, -80.0)),
		_slot("ST", Vector2(550.0, 80.0)),
	]


## The 4-2-3-1's three advanced midfielders (left/centre/right attacking mid)
## share the canonical "AM" role — they differ by anchor position, not role
## string, since the role set is fixed.
static func _4231() -> Array[Dictionary]:
	return [
		_slot("GK", Vector2(-750.0, 0.0)),
		_slot("CB", Vector2(-550.0, -120.0)),
		_slot("CB", Vector2(-550.0, 120.0)),
		_slot("LB", Vector2(-520.0, -320.0)),
		_slot("RB", Vector2(-520.0, 320.0)),
		_slot("DM", Vector2(-300.0, -100.0)),
		_slot("DM", Vector2(-300.0, 100.0)),
		_slot("AM", Vector2(200.0, -280.0)),
		_slot("AM", Vector2(250.0, 0.0)),
		_slot("AM", Vector2(200.0, 280.0)),
		_slot("ST", Vector2(650.0, 0.0)),
	]


## The 5-3-2's wing-backs share the canonical "LB"/"RB" role — the widest
## defensive slot on each flank, pushed further up the pitch than a back-four
## full-back to reflect the wing-back brief.
static func _532() -> Array[Dictionary]:
	return [
		_slot("GK", Vector2(-750.0, 0.0)),
		_slot("CB", Vector2(-580.0, -180.0)),
		_slot("CB", Vector2(-580.0, 0.0)),
		_slot("CB", Vector2(-580.0, 180.0)),
		_slot("LB", Vector2(-450.0, -340.0)),
		_slot("RB", Vector2(-450.0, 340.0)),
		_slot("CM", Vector2(-150.0, -120.0)),
		_slot("CM", Vector2(-150.0, 0.0)),
		_slot("CM", Vector2(-150.0, 120.0)),
		_slot("ST", Vector2(550.0, -80.0)),
		_slot("ST", Vector2(550.0, 80.0)),
	]


static func _442_diamond() -> Array[Dictionary]:
	return [
		_slot("GK", Vector2(-750.0, 0.0)),
		_slot("CB", Vector2(-550.0, -120.0)),
		_slot("CB", Vector2(-550.0, 120.0)),
		_slot("LB", Vector2(-520.0, -320.0)),
		_slot("RB", Vector2(-520.0, 320.0)),
		_slot("DM", Vector2(-250.0, 0.0)),
		_slot("LM", Vector2(-50.0, -280.0)),
		_slot("RM", Vector2(-50.0, 280.0)),
		_slot("AM", Vector2(220.0, 0.0)),
		_slot("ST", Vector2(550.0, -80.0)),
		_slot("ST", Vector2(550.0, 80.0)),
	]


static func _4141() -> Array[Dictionary]:
	return [
		_slot("GK", Vector2(-750.0, 0.0)),
		_slot("CB", Vector2(-550.0, -120.0)),
		_slot("CB", Vector2(-550.0, 120.0)),
		_slot("LB", Vector2(-520.0, -320.0)),
		_slot("RB", Vector2(-520.0, 320.0)),
		_slot("DM", Vector2(-300.0, 0.0)),
		_slot("LM", Vector2(0.0, -340.0)),
		_slot("CM", Vector2(-50.0, -110.0)),
		_slot("CM", Vector2(-50.0, 110.0)),
		_slot("RM", Vector2(0.0, 340.0)),
		_slot("ST", Vector2(600.0, 0.0)),
	]

