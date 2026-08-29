##
## PlayerBrain
##
## CPU decision matrix. Instead of a static if-else ladder, the brain builds a
## contextual vector (pressure, distance to ball, stamina) and passes it through
## personality biases — vision, composure, aggression — so two defenders with
## different attributes read the same situation differently, and a tired player
## under a heavy press makes unforced errors.
##
## The brain writes steering into HeavyPlayerController.movement_intent; it never
## touches velocity directly, so CPU players are bound by exactly the same weight
## model as the human one.
##
## Depends on: Pseudo3DBall, HeavyPlayerController (as parent node), MoodSystem
## (read via player.get_mood() to bias vision/composure/aggression at the
## decision site — mood never touches the exported attributes themselves),
## PitchBoundary (bound via bind_boundary(), used for goalkeeper positioning).
## Exposes: evaluate_tactical_action(), calculate_pressure_index(), ball
##

class_name PlayerBrain
extends Node

## Awareness of teammates and passing lanes.
@export_range(0.0, 1.0) var vision_attribute: float = 0.75
## Resistance to panicking under pressure.
@export_range(0.0, 1.0) var composure_attribute: float = 0.60
## Willingness to dive into tackles and shoot from distance.
@export_range(0.0, 1.0) var aggression_attribute: float = 0.80
## Base position this player holds when the ball is elsewhere, in world space.
@export var formation_anchor: Vector2 = Vector2.ZERO
## How far the anchor drifts toward the ball, 0.0-1.0 (team compactness).
@export_range(0.0, 1.0) var formation_ball_weight: float = 0.35
## Seconds between decision re-evaluations. Human-scale latency, and cheap.
@export var decision_interval: float = 0.25
## True for the goalkeeper — swaps evaluate_tactical_action() for a simple
## stay-near-goal/chase-goal-area rule instead of the outfield decision tree.
@export var is_goalkeeper: bool = false

enum Role { OUTFIELD_ATTACKER, OUTFIELD_MIDFIELDER, OUTFIELD_DEFENDER, GOALKEEPER }

## Snapshot of situational inputs computed once per decision tick and shared
## across all scorer functions. Avoids recomputing the same distances and
## teammate counts multiple times inside a single evaluation.
class UtilityContext:
	var pressure: float              ## 0-1, from calculate_pressure_index()
	var eff_vision: float            ## composure/mood-adjusted vision
	var eff_composure: float
	var eff_aggression: float
	var dist_to_ball: float          ## pixels, player → ball
	var dist_to_goal: float          ## pixels, player → opponent goal centre
	var stamina_ratio: float         ## 0-1
	var team_has_ball: bool
	var is_possessor: bool           ## player is ball.possessor
	var open_teammate_exists: bool   ## _find_best_pass_target() != null
	var chase_is_legal: bool         ## _should_chase_ball() returned true
	var sprint_locked: bool

@export var role: Role = Role.OUTFIELD_MIDFIELDER

## Radius inside which an opponent contributes to the pressure index.
const PRESSURE_RADIUS: float = 180.0
## Distance at which the brain commits to chasing the ball rather than holding shape.
const CHASE_RADIUS: float = 220.0
## Arrival radius — inside this the player eases off instead of oscillating.
const ARRIVE_RADIUS: float = 24.0
## How close the ball must be to the keeper's own goal centre before they chase it.
const GOALKEEPER_CHASE_RADIUS: float = 200.0

var player: HeavyPlayerController = null
var ball: Pseudo3DBall = null
var pitch_boundary: PitchBoundary = null
var current_action: StringName = &"MaintainFormation"

var _decision_cooldown: float = 0.0
## Off-ball target cached from the last decision tick. _find_open_space_target()
## does get_tree().get_nodes_in_group() scans that must stay on the decision
## interval (every decision_interval seconds), not the physics frame rate —
## get_target_position() is called from _steer_for_action() every physics
## frame, so it reads this cache instead of recomputing it each frame.
var _cached_space_target: Vector2 = Vector2.ZERO
## Teammate targeted by the last "Pass" decision. Cleared once the pass is
## struck or the decision changes away from passing.
var _cached_pass_target: HeavyPlayerController = null
## Predicted ball-intercept point cached from the last decision tick, used
## while chasing/clearing so steering doesn't recompute the trajectory every
## physics frame.
var _cached_intercept: Vector2 = Vector2.ZERO


func _ready() -> void:
	player = get_parent() as HeavyPlayerController
	if formation_anchor == Vector2.ZERO and player != null:
		formation_anchor = player.global_position


## The pitch calls this after spawning so the brain knows which ball to track.
func bind_ball(match_ball: Pseudo3DBall) -> void:
	ball = match_ball


## The pitch calls this after spawning so a goalkeeper's brain can measure
## distance to its own goal centre.
func bind_boundary(b: PitchBoundary) -> void:
	pitch_boundary = b


func _physics_process(delta: float) -> void:
	if player == null or ball == null or player.is_user_controlled:
		return
	if not GameManager.is_in_play():
		player.movement_intent = Vector2.ZERO
		return

	_decision_cooldown -= delta
	if _decision_cooldown <= 0.0:
		_decision_cooldown = decision_interval
		current_action = evaluate_tactical_action(_find_nearby_opponents())
		_cached_space_target = _find_open_space_target()
		if current_action == &"ChaseBall" or current_action == &"PanicClear":
			_cached_intercept = _predict_intercept_position()

	player.movement_intent = _steer_for_action()


## Builds the UtilityContext snapshot for one decision tick.
func _build_context(defenders_nearby: Array[Node2D]) -> UtilityContext:
	var ctx := UtilityContext.new()

	ctx.pressure = calculate_pressure_index(defenders_nearby)

	# Read base attributes, then layer mood on top. Mood never mutates the
	# exported attributes — it is applied only at the decision site so the
	# Inspector always shows the base talent regardless of in-match state.
	var mood_node: MoodSystem = player.get_mood() if player != null else null
	ctx.eff_vision      = clampf(vision_attribute      + (mood_node.get_vision_delta()      if mood_node != null else 0.0), 0.0, 1.0)
	ctx.eff_composure   = clampf(composure_attribute   + (mood_node.get_composure_delta()   if mood_node != null else 0.0), 0.0, 1.0)
	ctx.eff_aggression  = clampf(aggression_attribute  + (mood_node.get_aggression_delta()  if mood_node != null else 0.0), 0.0, 1.0)

	ctx.dist_to_ball = player.global_position.distance_to(ball.global_position) if ball != null else INF
	ctx.stamina_ratio = player.get_stamina_ratio()
	ctx.team_has_ball = _team_has_ball()
	ctx.is_possessor  = ball != null and ball.possessor == player
	ctx.sprint_locked = player.sprint_locked

	# Forward direction toward the opponent goal. Team A attacks toward +X.
	if pitch_boundary != null:
		var opp_team: int = 1 - player.team
		ctx.dist_to_goal = player.global_position.distance_to(
			pitch_boundary.get_goal_centre(opp_team))
	else:
		ctx.dist_to_goal = 800.0

	# These are cached results of existing methods — call them here so every
	# scorer sees the same answer rather than running independent tree scans.
	ctx.chase_is_legal         = _should_chase_ball()
	ctx.open_teammate_exists   = _find_best_pass_target() != null

	return ctx


## Score for choosing Pass.
## Peaks when: possessor, high vision, open teammate, composure keeps
## panic from overriding it.  Falls when stamina is low (hurried passes).
func _score_pass(ctx: UtilityContext) -> float:
	if not ctx.is_possessor or not ctx.open_teammate_exists:
		return 0.0
	var base: float = 0.60
	# High vision = more likely to spot and execute the pass.
	base += ctx.eff_vision * 0.25
	# Under pressure, composure decides whether to pass or panic.
	base += ctx.eff_composure * 0.10 * (1.0 - ctx.pressure)
	# Low stamina hurries decisions — a tired player passes sooner.
	base += (1.0 - ctx.stamina_ratio) * 0.10
	return clampf(base, 0.0, 1.0)


## Score for chasing the ball.
## Legal only when _should_chase_ball() approved it.  Closer + aggressive
## players score higher; a tired sprint-locked player scores much lower.
func _score_chase(ctx: UtilityContext) -> float:
	if not ctx.chase_is_legal:
		return 0.0
	# Normalise distance — 0 px = 1.0, CHASE_RADIUS = 0.0.
	var prox: float = clampf(1.0 - ctx.dist_to_ball / CHASE_RADIUS, 0.0, 1.0)
	var base: float = prox * 0.55
	base += ctx.eff_aggression * 0.30
	# Sprint-locked players can still chase but don't score as highly —
	# they are more likely to lose a footrace.
	if ctx.sprint_locked:
		base *= 0.65
	return clampf(base, 0.0, 1.0)


## Score for finding space (off-ball intelligent run).
## High vision unlocks this; only fires when team has the ball.
func _score_find_space(ctx: UtilityContext) -> float:
	if ctx.is_possessor:
		return 0.0
	# Only make attacking runs when team has possession.
	if not ctx.team_has_ball:
		return 0.0
	var base: float = ctx.eff_vision * 0.60
	# Fresh legs make runs more dangerous.
	base += ctx.stamina_ratio * 0.20
	# Attackers who are already in a threatening position score lower —
	# they don't need to make another run.
	var goal_prox: float = clampf(1.0 - ctx.dist_to_goal / 600.0, 0.0, 1.0)
	base -= goal_prox * 0.15
	return clampf(base, 0.0, 1.0)


## Score for attempting a dribble (carrying the ball forward).
## Aggressive players attempt it; the score collapses under heavy pressure
## unless composure is very high.
func _score_dribble(ctx: UtilityContext) -> float:
	if not ctx.is_possessor:
		return 0.0
	var base: float = ctx.eff_aggression * 0.55
	# Pressure kills dribble desirability unless composure keeps it alive.
	base -= ctx.pressure * (1.0 - ctx.eff_composure) * 0.50
	# Stamina matters — a tired player should not try to beat their marker.
	base *= ctx.stamina_ratio
	return clampf(base, 0.0, 1.0)


## Score for maintaining formation (conservative option).
## Acts as the floor: always available, but outscored whenever anything
## more purposeful is viable.  Rises when team lacks the ball and player
## is far from anchor — getting back into shape.
func _score_maintain_formation(ctx: UtilityContext) -> float:
	# Base desirability: modest but non-zero — always an option.
	var base: float = 0.20
	if not ctx.team_has_ball:
		# Defensive discipline: get back into shape when out of possession.
		if player != null:
			var anchor_dist: float = player.global_position.distance_to(formation_anchor)
			var anchor_urgency: float = clampf(anchor_dist / CHASE_RADIUS, 0.0, 1.0)
			base += anchor_urgency * 0.35
	return clampf(base, 0.0, 1.0)


## Turns the contextual vector into an action name. Returned names are
## deliberately tactical rather than mechanical — the steering layer decides how
## to execute them.
func evaluate_tactical_action(defenders_nearby: Array[Node2D]) -> StringName:
	if is_goalkeeper:
		if pitch_boundary != null and ball != null and player != null:
			# Priority 1: intercept a shot heading for goal.
			var intercept: Vector2 = _find_goalkeeper_intercept()
			if intercept != Vector2.ZERO:
				_cached_intercept = intercept
				return &"ChaseBall"

			# Priority 2: basic chase if ball is close to goal.
			var goal_centre: Vector2 = pitch_boundary.get_goal_centre(player.team)
			if ball.global_position.distance_to(goal_centre) < GOALKEEPER_CHASE_RADIUS:
				_cached_intercept = ball.global_position
				return &"ChaseBall"

			# Priority 3: positional — stand between ball and goal centre.
			var to_ball: Vector2 = (ball.global_position - goal_centre).normalized()
			_cached_space_target = goal_centre + to_ball * 60.0
		return &"MaintainFormation"

	var ctx: UtilityContext = _build_context(defenders_nearby)

	if ctx.pressure > 0.85 and ctx.eff_composure < 0.45:
		return &"PanicClear"

	# --- Utility scoring ---
	# Hard guards above have already filtered out PanicClear.
	# Now build a scored candidate list — the highest score wins.
	# Ties are broken by the order of the array (pass > chase > space > dribble > formation).

	# Cache the pass target now so _score_pass() and _steer_for_action()
	# both see the same answer without a second tree scan.
	var pass_target: HeavyPlayerController = _find_best_pass_target()
	if pass_target != null:
		_cached_pass_target = pass_target

	var candidates: Array[Dictionary] = [
		{ &"action": &"Pass",              "score": _score_pass(ctx)              },
		{ &"action": &"ChaseBall",         "score": _score_chase(ctx)             },
		{ &"action": &"FindSpace",         "score": _score_find_space(ctx)        },
		{ &"action": &"AttemptDribble",    "score": _score_dribble(ctx)           },
		{ &"action": &"MaintainFormation", "score": _score_maintain_formation(ctx)},
	]

	# Add a small noise term so two players in identical situations make
	# slightly different choices — they won't always run to the same spot.
	# Noise is seeded from the player's unique node path so it is
	# deterministic per player but different between players.
	var noise_seed: int = player.get_instance_id() + GameManager.get_match_tick()
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	for c: Dictionary in candidates:
		c["score"] = clampf(c["score"] + rng.randf_range(-0.04, 0.04), 0.0, 1.0)

	var best_action: StringName = &"MaintainFormation"
	var best_score: float = -1.0
	for c: Dictionary in candidates:
		if c["score"] > best_score:
			best_score = c["score"]
			best_action = c[&"action"]

	return best_action


## Scores every same-team, non-GK, non-self teammate by openness (distance
## from the nearest opponent) and forward positioning. Returns null if nothing
## scores above the minimum openness threshold.
func _find_best_pass_target() -> HeavyPlayerController:
	if ball == null or player == null:
		return null

	var attack_dir: Vector2 = Vector2(1.0, 0.0) if player.team == GameManager.TEAM_A else Vector2(-1.0, 0.0)
	var ball_pos: Vector2 = ball.global_position
	var all_opponents: Array[Node2D] = _find_nearby_opponents()

	# Recompute effective composure locally (same pattern as evaluate_tactical_action).
	var mood_node: MoodSystem = player.get_mood() if player != null else null
	var eff_composure: float = composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0)
	eff_composure = clampf(eff_composure, 0.0, 1.0)

	var best_target: HeavyPlayerController = null
	var best_score: float = 60.0  # Minimum openness threshold in pixels

	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var candidate := node as HeavyPlayerController
		if candidate == null or candidate == player or candidate.team != player.team:
			continue
		var candidate_brain := candidate.get_node_or_null("PlayerBrain") as PlayerBrain
		if candidate_brain != null and candidate_brain.is_goalkeeper:
			continue

		var to_candidate: Vector2 = candidate.global_position - ball_pos
		var forward_dot: float = to_candidate.normalized().dot(attack_dir)
		# No backward passes unless composure is high (safety valve under pressure).
		if forward_dot < -0.2 and eff_composure < 0.55:
			continue

		var min_opp_dist: float = INF
		for opp: Node2D in all_opponents:
			var d: float = candidate.global_position.distance_to(opp.global_position)
			if d < min_opp_dist:
				min_opp_dist = d

		var forward_bonus: float = clampf(forward_dot, 0.0, 1.0) * 40.0
		var score: float = min_opp_dist + forward_bonus
		if score > best_score:
			best_score = score
			best_target = candidate

	return best_target


## Predicts where a fast or airborne ball will cross the goalkeeper's own
## goal mouth, and returns that point if the keeper can reach it in time.
## Returns Vector2.ZERO if the ball isn't a shot threat or no reachable
## crossing point exists.
func _find_goalkeeper_intercept() -> Vector2:
	if ball == null or player == null or pitch_boundary == null:
		return Vector2.ZERO

	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(player.team)

	# Only react to fast or airborne balls.
	if not ball.is_airborne() and ball.velocity.length() < 200.0:
		return Vector2.ZERO

	var trajectory: Array[Vector2] = ball.predict_trajectory(
		ball.velocity, ball.velocity_z, 60, 0.05)

	const GOAL_HALF_WIDTH: float = 200.0
	var my_speed: float = player.get_current_top_speed()

	for i: int in range(trajectory.size()):
		var point: Vector2 = trajectory[i]
		if absf(point.x - goal_centre.x) > 80.0:
			continue
		if absf(point.y - goal_centre.y) > GOAL_HALF_WIDTH:
			continue
		var time_to_point: float = float(i + 1) * 0.05
		var dist_to_point: float = player.global_position.distance_to(point)
		if dist_to_point <= my_speed * time_to_point + 40.0:
			return point

	return Vector2.ZERO


## Returns true only if this player is the most appropriate chaser on the team.
## "Most appropriate" means: among all teammates, this player is one of the
## role's budgeted closest to the ball, AND within that role's max chase
## distance. This prevents all outfield players from simultaneously deciding
## to chase.
func _should_chase_ball() -> bool:
	if ball == null or player == null:
		return false

	# Role-based chase budget: how many players of this role are allowed to
	# chase the ball at once. Defenders only send 1 if they are the closest;
	# attackers can send up to 2 (striker + a supporting wide player).
	var budget: int
	match role:
		Role.OUTFIELD_ATTACKER: budget = 2
		Role.OUTFIELD_MIDFIELDER: budget = 1
		Role.OUTFIELD_DEFENDER: budget = 1
		_: return false  # Goalkeeper handled separately

	# Maximum distance from the ball at which this player will ever chase,
	# regardless of being closest. Keeps shape when play is far away.
	var max_dist: float
	match role:
		Role.OUTFIELD_ATTACKER: max_dist = 380.0
		Role.OUTFIELD_MIDFIELDER: max_dist = 320.0
		Role.OUTFIELD_DEFENDER: max_dist = 260.0
		_: return false

	var my_dist: float = player.global_position.distance_to(ball.global_position)
	if my_dist > max_dist:
		return false

	# Count how many same-role same-team players are closer to the ball than me.
	# If fewer than `budget` are closer, I am within the allowed chasers.
	var closer_count: int = 0
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as HeavyPlayerController
		if other == null or other == player or other.team != player.team:
			continue
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain == null or other_brain.role != role:
			continue
		if other.global_position.distance_to(ball.global_position) < my_dist:
			closer_count += 1
		if closer_count >= budget:
			return false

	return true


## 0.0-1.0 crowding score from opponents within PRESSURE_RADIUS.
func calculate_pressure_index(defenders: Array[Node2D]) -> float:
	if player == null:
		return 0.0

	var total_pressure: float = 0.0
	for defender: Node2D in defenders:
		var distance: float = player.global_position.distance_to(defender.global_position)
		if distance < PRESSURE_RADIUS:
			total_pressure += 1.0 - (distance / PRESSURE_RADIUS)

	return clampf(total_pressure, 0.0, 1.0)


## Where the brain wants to be, given the action and the ball's position.
## Off-ball players (anything other than chasing/dribbling) use role-specific
## space-finding rather than drifting the whole shape toward the ball.
func get_target_position() -> Vector2:
	if ball == null:
		return formation_anchor

	match current_action:
		&"ChaseBall", &"PanicClear", &"AttemptDribble":
			# Prefer chasing the ball carrier rather than the raw ball position.
			# Carrier is whoever last touched the ball and is an opponent.
			var carrier: HeavyPlayerController = _get_ball_carrier()
			if carrier != null:
				return carrier.global_position
			return ball.global_position
		&"Pass":
			if _cached_pass_target != null and is_instance_valid(_cached_pass_target):
				return _cached_pass_target.global_position + _cached_pass_target.velocity * 0.3
			return ball.global_position
		_:
			return _cached_space_target


## Walks the ball's predicted trajectory and returns the first point this
## player can reach in time, given their current top speed. Falls back to the
## trajectory's final point, or the ball's current position if no trajectory
## is available.
func _predict_intercept_position() -> Vector2:
	if ball == null or player == null:
		return ball.global_position if ball != null else player.global_position

	var my_speed: float = player.get_current_top_speed()
	var trajectory: Array[Vector2] = ball.predict_trajectory(
		ball.velocity, ball.velocity_z, 30, 0.05)

	for i: int in range(trajectory.size()):
		var point: Vector2 = trajectory[i]
		var time_to_point: float = float(i + 1) * 0.05
		var dist_to_point: float = player.global_position.distance_to(point)
		if dist_to_point <= my_speed * time_to_point + 20.0:
			return point

	if trajectory.size() > 0:
		return trajectory[-1]
	return ball.global_position


## Returns true if a teammate (or this player) last touched the ball.
func _team_has_ball() -> bool:
	if ball == null:
		return false
	var toucher: HeavyPlayerController = ball.last_touched_by
	if toucher == null:
		return false
	return toucher.team == player.team


## Returns the world-space position this player should move to when NOT chasing
## the ball. The result is role-specific and possession-aware:
##   - When team HAS ball: attackers run channels, mids hold a passing angle
##   - When team DOES NOT have ball: attackers drop off, mids track the ball
##     laterally, defenders mark the nearest threat or hold the line
func _find_open_space_target() -> Vector2:
	if ball == null or player == null:
		return formation_anchor

	var ball_pos: Vector2 = ball.global_position
	var has_ball: bool = _team_has_ball()

	match role:

		Role.OUTFIELD_ATTACKER:
			if has_ball:
				# Find the widest open lane by sampling positions at the
				# opponent's defensive third depth and picking the one furthest
				# from any defender.
				return _find_channel_run_target(ball_pos)
			else:
				# Defending: drop toward own half but not all the way back.
				# Maintain a threatening position so the team can counter.
				var drop_target: Vector2 = formation_anchor
				drop_target = drop_target.lerp(ball_pos, 0.20)
				return drop_target

		Role.OUTFIELD_MIDFIELDER:
			if has_ball:
				# Hold a passing angle: position in a triangle relative to the
				# ball carrier, at a perpendicular offset so there is always a
				# safe outlet pass available.
				return _find_passing_triangle_position(ball_pos)
			else:
				# Defensive shape: hold the formation anchor but track the
				# ball's lateral position (press the space it is going to).
				# Reuses formation_ball_weight so the manager's tempo/trait
				# tuning still shapes how far the midfield presses across.
				var defend_pos: Vector2 = formation_anchor
				defend_pos.x = lerpf(defend_pos.x, ball_pos.x, formation_ball_weight)
				return defend_pos

		Role.OUTFIELD_DEFENDER:
			if has_ball:
				# When team has the ball, hold the defensive line — do NOT
				# drift forward. Compress slightly to offer a safe back-pass.
				var safe_pos: Vector2 = formation_anchor
				safe_pos = safe_pos.lerp(ball_pos, 0.08)
				return safe_pos
			else:
				# Mark the nearest opposing attacker who is in a dangerous
				# position (forward of the ball). If no threat, hold the line.
				var threat: HeavyPlayerController = _find_nearest_threatening_opponent()
				if threat != null:
					# Position between the threat and our own goal — not on top
					# of them, but cutting the passing lane.
					var goal_centre: Vector2 = formation_anchor  # anchor IS the defensive line
					return threat.global_position.lerp(goal_centre, 0.45)
				return formation_anchor

		_:
			return formation_anchor


## Samples 5 lateral positions at the opponent's defensive third and returns
## the one with the most open space (furthest average distance from defenders).
func _find_channel_run_target(ball_pos: Vector2) -> Vector2:
	if pitch_boundary == null or player == null:
		return formation_anchor

	var bounds: Rect2 = pitch_boundary.get_pitch_rect()
	# Target depth: push toward the opponent's goal on the X axis (goals sit
	# at the pitch's left/right ends — see PitchBoundary.get_goal_centre()).
	# Team 0 (TEAM_A) defends the left goal and attacks toward +X; TEAM_B
	# defends the right goal and attacks toward -X.
	var attack_x: float
	if player.team == GameManager.TEAM_A:
		attack_x = lerpf(ball_pos.x, bounds.end.x - 80.0, 0.55)
	else:
		attack_x = lerpf(ball_pos.x, bounds.position.x + 80.0, 0.55)

	# Sample 5 Y positions across the pitch width (touchline to touchline),
	# biased toward the flanks.
	var pitch_top: float = bounds.position.y + 40.0
	var pitch_bottom: float = bounds.end.y - 40.0
	var candidates: Array[Vector2] = []
	for i: int in range(5):
		var t: float = float(i) / 4.0
		candidates.append(Vector2(attack_x, lerpf(pitch_top, pitch_bottom, t)))

	# Score each candidate by distance from all opponents.
	var best_pos: Vector2 = formation_anchor
	var best_score: float = -INF
	var opponents: Array[Node2D] = _find_nearby_opponents()

	for candidate: Vector2 in candidates:
		var min_opp_dist: float = INF
		for opp: Node2D in opponents:
			var d: float = candidate.distance_to(opp.global_position)
			if d < min_opp_dist:
				min_opp_dist = d
		# Also penalise positions where a teammate is already standing nearby.
		var teammate_penalty: float = 0.0
		for node: Node in get_tree().get_nodes_in_group(&"players"):
			var mate := node as HeavyPlayerController
			if mate == null or mate == player or mate.team != player.team:
				continue
			var td: float = candidate.distance_to(mate.global_position)
			if td < 80.0:
				teammate_penalty += (80.0 - td)  # Penalise overlap
		var score: float = min_opp_dist - teammate_penalty * 0.5
		if score > best_score:
			best_score = score
			best_pos = candidate

	return best_pos


## Returns a position in a passing triangle: offset laterally and slightly
## behind the ball so the midfielder is always available for a short outlet.
func _find_passing_triangle_position(ball_pos: Vector2) -> Vector2:
	if player == null:
		return formation_anchor

	# Perpendicular offset from the ball: the pitch's width runs along Y (the
	# goals sit on the X ends), so "wide" is a Y offset, picking whichever
	# touchline side this player's anchor already favours.
	var anchor_side: float = signf(formation_anchor.y - ball_pos.y)
	if anchor_side == 0.0:
		anchor_side = 1.0

	var offset_y: float = anchor_side * 140.0
	# "Behind" the ball means toward our own goal along the X (attack) axis.
	var offset_x: float = -60.0 if player.team == GameManager.TEAM_A else 60.0

	var triangle_pos: Vector2 = ball_pos + Vector2(offset_x, offset_y)

	# Clamp to pitch bounds.
	if pitch_boundary != null:
		var bounds: Rect2 = pitch_boundary.get_pitch_rect()
		triangle_pos.x = clampf(triangle_pos.x, bounds.position.x + 30.0, bounds.end.x - 30.0)
		triangle_pos.y = clampf(triangle_pos.y, bounds.position.y + 30.0, bounds.end.y - 30.0)

	return triangle_pos


## Returns the nearest opponent who is in a threatening forward position
## (ahead of the defensive line, between the defender and goal).
func _find_nearest_threatening_opponent() -> HeavyPlayerController:
	if player == null or pitch_boundary == null:
		return null

	var centre_x: float = pitch_boundary.get_centre_spot().x
	var best: HeavyPlayerController = null
	var best_dist: float = 300.0  # Only mark opponents within this radius

	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as HeavyPlayerController
		if other == null or other.team == player.team:
			continue

		# Only threatening if they are between us and our goal.
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain != null and other_brain.role == PlayerBrain.Role.OUTFIELD_ATTACKER:
			var d: float = player.global_position.distance_to(other.global_position)
			# Threatening if they have pushed into our defensive half (goals
			# sit on the X ends — see PitchBoundary.get_goal_centre()).
			var toward_goal: bool
			if player.team == GameManager.TEAM_A:
				toward_goal = other.global_position.x < centre_x
			else:
				toward_goal = other.global_position.x > centre_x
			if toward_goal and d < best_dist:
				best_dist = d
				best = other

	return best


## Repels this player from teammates within sep_radius so off-ball players
## don't stack on top of each other.
func _separation_force(sep_radius: float = 90.0) -> Vector2:
	if player == null:
		return Vector2.ZERO
	var force: Vector2 = Vector2.ZERO
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as HeavyPlayerController
		if other == null or other == player or other.team != player.team:
			continue
		var offset: Vector2 = player.global_position - other.global_position
		var dist: float = offset.length()
		if dist > 0.0 and dist < sep_radius:
			force += offset.normalized() * (1.0 - dist / sep_radius)
	return force


func _get_ball_carrier() -> HeavyPlayerController:
	if ball == null:
		return null
	var toucher: HeavyPlayerController = ball.last_touched_by
	if toucher != null and toucher.team != player.team:
		return toucher
	return null


## Blends three forces into the final movement_intent: a seek toward the
## current action's target, separation from teammates (off-ball only, so
## chasers aren't pushed off the intercept line), and a gentle formation
## spring when far from the anchor.
func _steer_for_action() -> Vector2:
	# --- Pass execution (Task 1 preserved) ---
	if current_action == &"Pass" and _cached_pass_target != null and is_instance_valid(_cached_pass_target):
		if player.global_position.distance_to(ball.global_position) < 80.0 and player.get_ball_in_foot_range() != null:
			var lead_pos: Vector2 = _cached_pass_target.global_position + _cached_pass_target.velocity * 0.3
			var aim: Vector2 = (lead_pos - ball.global_position).normalized()
			ball.apply_kick(aim * 260.0, 0.0, player)
			_cached_pass_target = null
			current_action = &"MaintainFormation"

	# --- Seek target selection ---
	var seek_target: Vector2
	match current_action:
		&"ChaseBall", &"PanicClear":
			seek_target = _cached_intercept if _cached_intercept != Vector2.ZERO else ball.global_position
		&"Pass":
			if _cached_pass_target != null and is_instance_valid(_cached_pass_target):
				seek_target = _cached_pass_target.global_position + _cached_pass_target.velocity * 0.3
			else:
				seek_target = ball.global_position
		_:
			seek_target = _cached_space_target

	# --- Three-force blend ---
	var offset: Vector2 = seek_target - player.global_position
	var distance: float = offset.length()

	if distance <= ARRIVE_RADIUS:
		return Vector2.ZERO

	# 1. Seek force
	var deflection: float = clampf(distance / (ARRIVE_RADIUS * 4.0), 0.35, 1.0)
	var seek_force: Vector2 = offset.normalized() * deflection

	# 2. Separation — only off-ball so chasers aren't pushed off the intercept line
	var sep_force: Vector2 = Vector2.ZERO
	if current_action != &"ChaseBall" and current_action != &"PanicClear":
		sep_force = _separation_force() * 0.40

	# 3. Formation spring — gentle pull back when very far from anchor
	var spring_force: Vector2 = Vector2.ZERO
	if player.brain != null:
		var anchor_offset: Vector2 = player.brain.formation_anchor - player.global_position
		if anchor_offset.length() > CHASE_RADIUS * 1.5:
			spring_force = anchor_offset.normalized() * 0.15

	player.is_sprinting = current_action == &"ChaseBall" and distance > CHASE_RADIUS * 0.5
	return (seek_force + sep_force + spring_force).limit_length(1.0)


func _find_nearby_opponents() -> Array[Node2D]:
	var opponents: Array[Node2D] = []
	for node: Node in get_tree().get_nodes_in_group(&"players"):
		var other := node as HeavyPlayerController
		if other != null and other != player and other.team != player.team:
			opponents.append(other)
	return opponents
