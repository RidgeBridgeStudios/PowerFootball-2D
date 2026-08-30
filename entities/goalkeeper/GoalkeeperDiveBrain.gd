##
## GoalkeeperDiveBrain
##
## Pure decision logic for choosing which way a goalkeeper dives when a shot is
## struck. No node, no scene tree, no signal wiring — instantiate once per match
## and pass the same instance to decide_dive() on every shot.
##
## The direction is a one-way commitment: the returned Vector2 is the lateral
## dive axis (x is always 0.0 — a keeper dives along the goal line's Y axis),
## and the caller hands it to GoalkeeperDiveState, which then owns the physical
## motion. There is no mid-air correction, so the error term here — a reflex
## roll that flips the direction the wrong way — is final.
##
## Depends on: HeavyPlayerController, Pseudo3DBall, PlayerData.
## Exposes: initialise(), decide_dive().
##

class_name GoalkeeperDiveBrain
extends RefCounted

## Seeded once per match via initialise(); lives on the instance so
## decide_dive() never allocates a generator on a hot path.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func initialise(seed_value: int) -> void:
	_rng.seed = seed_value


## Decides the lateral dive direction for `keeper` facing `shot_velocity`, or
## Vector2.ZERO when the shot cannot be projected onto the keeper's goal line / plane
## (no horizontal component, or aimed dead-centre at the keeper so standing/catching is
## appropriate). The direction's Y is reflex-flipped a fraction of the time,
## modelling a keeper going the wrong way under pressure.
func decide_dive(
	keeper: HeavyPlayerController,
	ball: Pseudo3DBall,
	shot_velocity: Vector2,
	goal_line_x: float
) -> Vector2:
	# No horizontal component — the crossing point never reaches the line.
	if is_zero_approx(shot_velocity.x):
		return Vector2.ZERO

	# Calculate time to keeper's X plane and time to goal line
	var t_keeper: float = (keeper.global_position.x - ball.global_position.x) / shot_velocity.x
	var t_goal: float = (goal_line_x - ball.global_position.x) / shot_velocity.x

	# If shot is moving away from both keeper and goal, ignore
	if t_goal < 0.0 and t_keeper < 0.0:
		return Vector2.ZERO

	# Project crossing Y at keeper's plane if forward, else at goal line
	var t_proj: float = t_keeper if t_keeper > 0.0 else t_goal
	var predicted_y: float = ball.global_position.y + shot_velocity.y * t_proj

	# Dead-centre: ball coming straight at keeper — standing up/catching is the right call
	if absf(predicted_y - keeper.global_position.y) < 25.0:
		return Vector2.ZERO

	var diff_y: float = predicted_y - keeper.global_position.y
	var raw_dir: Vector2 = Vector2(0.0, signf(diff_y))
	if is_zero_approx(raw_dir.y):
		raw_dir.y = 1.0

	# Reflex-scaled wrong-way probability. Weak reflexes flip the dive often;
	# elite keepers almost never do.
	var reflexes: float = 0.6
	var player_data: PlayerData = keeper.get_meta(&"player_data", null) as PlayerData
	if player_data != null:
		reflexes = player_data.reflexes
	var error_chance: float = clampf(1.0 - reflexes, 0.05, 0.60)
	if _rng.randf() < error_chance:
		raw_dir.y = -raw_dir.y

	return raw_dir
