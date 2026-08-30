##
## PlayerRoleConfig
##
## Data resource representing a single outfield role's tuning parameters.
## Replaces hardcoded per-role constants scattered across PlayerBrain.gd with
## inspector-editable values loaded via @export. One .tres file per role
## (CB, CDM, CM, ST) lives in res://shared/roles/ and is assigned to each
## player entity through HeavyPlayerController.role_config.
##


class_name PlayerRoleConfig
extends Resource


## Short identifier shown in the Inspector and logs (e.g. "CB", "ST").
@export var role_name: String = ""


## Off-ball anchor blend alpha — 0.0 = freely drifts to open space,
## 1.0 = rigidly holds the formation anchor. Replaces ROLE_SPACE_ALPHA.
@export_range(0.0, 1.0) var anchor_weight: float = 0.55


## Maximum pixel radius from the formation anchor at which this role will
## chase the ball. Replaces the max_dist literals in _should_chase_ball().
@export var max_chase_distance: float = 300.0


## Pass utility weights — individual @export floats so each is editable
## in the Inspector separately. Do NOT collapse into a Dictionary field.
@export_range(0.0, 1.0) var w_dist: float = 0.25   # distance weight
@export_range(0.0, 1.0) var w_angle: float = 0.20  # facing angle weight
@export_range(0.0, 1.0) var w_press: float = 0.30  # receiver pressure weight
@export_range(0.0, 1.0) var w_adv: float = 0.25    # forward advancement weight


## Normalized pitch zone, –0.5..0.5 space (0,0 = centre spot).
@export var pitch_bounds: Rect2 = Rect2(-0.5, -0.5, 1.0, 1.0)


## Returns pass weights as a Dictionary for PassUtilityScorer consumption.
func get_pass_weights() -> Dictionary:
	return { "dist": w_dist, "angle": w_angle, "press": w_press, "adv": w_adv }
