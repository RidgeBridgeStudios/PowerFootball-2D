##
## FormationRegistry
##
## Maps formation name strings to their 11 relative pitch positions
## (normalised 0-1 Vector2, [0, y] = own goal line, [1, y] = opponent goal).
## Position index 0 = GK, 1-4 = defence L->R, 5-7 = midfield L->R,
## 8-10 = attack L->R (adjusts per formation).
## Used by FormationDiagram to draw dots on a mini-pitch. This is a UI-facing
## registry, distinct from FormationLibrary's world-pixel gameplay anchors —
## it additionally covers "4-1-4-1" and "4-4-2 Diamond", which FormationLibrary
## does not.
##
## Depends on: nothing.
## Exposes: all_formations(), positions_for(formation).
##

class_name FormationRegistry
extends RefCounted

static func all_formations() -> Array[String]:
	return ["4-4-2", "4-3-3", "4-2-3-1", "4-4-2 Diamond", "4-1-4-1", "3-5-2", "5-3-2"]


## Returns 11 normalised Vector2 positions for a formation, arranged as
## [GK, LB, CB, CB, RB, LM/LCM, CM, RM/RCM, LW/LAM, AM/CF, ST/RW].
## Columns: GK=0.05, Def=0.22, Mid=0.50, Att=0.74. Rows spread across [0.1, 0.9].
static func positions_for(formation: String) -> Array[Vector2]:
	match formation:
		"4-4-2":
			return [
				Vector2(0.05, 0.50),
				Vector2(0.22, 0.20), Vector2(0.22, 0.37),
				Vector2(0.22, 0.63), Vector2(0.22, 0.80),
				Vector2(0.50, 0.15), Vector2(0.50, 0.38),
				Vector2(0.50, 0.62), Vector2(0.50, 0.85),
				Vector2(0.74, 0.35), Vector2(0.74, 0.65),
			]
		"4-3-3":
			return [
				Vector2(0.05, 0.50),
				Vector2(0.22, 0.18), Vector2(0.22, 0.38),
				Vector2(0.22, 0.62), Vector2(0.22, 0.82),
				Vector2(0.50, 0.25), Vector2(0.50, 0.50), Vector2(0.50, 0.75),
				Vector2(0.74, 0.18), Vector2(0.74, 0.50), Vector2(0.74, 0.82),
			]
		"4-2-3-1":
			return [
				Vector2(0.05, 0.50),
				Vector2(0.22, 0.18), Vector2(0.22, 0.38),
				Vector2(0.22, 0.62), Vector2(0.22, 0.82),
				Vector2(0.42, 0.35), Vector2(0.42, 0.65),
				Vector2(0.60, 0.18), Vector2(0.60, 0.50), Vector2(0.60, 0.82),
				Vector2(0.78, 0.50),
			]
		"4-4-2 Diamond":
			return [
				Vector2(0.05, 0.50),
				Vector2(0.22, 0.18), Vector2(0.22, 0.38),
				Vector2(0.22, 0.62), Vector2(0.22, 0.82),
				Vector2(0.45, 0.50),
				Vector2(0.55, 0.25), Vector2(0.55, 0.75),
				Vector2(0.65, 0.50),
				Vector2(0.76, 0.35), Vector2(0.76, 0.65),
			]
		"4-1-4-1":
			return [
				Vector2(0.05, 0.50),
				Vector2(0.22, 0.18), Vector2(0.22, 0.38),
				Vector2(0.22, 0.62), Vector2(0.22, 0.82),
				Vector2(0.38, 0.50),
				Vector2(0.55, 0.15), Vector2(0.55, 0.38),
				Vector2(0.55, 0.62), Vector2(0.55, 0.85),
				Vector2(0.78, 0.50),
			]
		"3-5-2":
			return [
				Vector2(0.05, 0.50),
				Vector2(0.22, 0.25), Vector2(0.22, 0.50), Vector2(0.22, 0.75),
				Vector2(0.50, 0.10), Vector2(0.50, 0.30), Vector2(0.50, 0.50),
				Vector2(0.50, 0.70), Vector2(0.50, 0.90),
				Vector2(0.74, 0.35), Vector2(0.74, 0.65),
			]
		"5-3-2":
			return [
				Vector2(0.05, 0.50),
				Vector2(0.22, 0.10), Vector2(0.22, 0.30), Vector2(0.22, 0.50),
				Vector2(0.22, 0.70), Vector2(0.22, 0.90),
				Vector2(0.50, 0.25), Vector2(0.50, 0.50), Vector2(0.50, 0.75),
				Vector2(0.74, 0.35), Vector2(0.74, 0.65),
			]
		_:
			return positions_for("4-4-2")
