##
## PlayerBrain
##
## CPU decision matrix. Instead of a static if-else ladder, the brain builds a
## contextual vector (pressure, distance to ball, stamina) and passes it through
## personality biases — vision, composure, aggression — so two defenders with
## different attributes read the same situation differently, and a tired player
## under a heavy press makes unforced errors.
##
## The brain writes exactly two fields on HeavyPlayerController — movement_intent
## (a direction to seek) and wants_sprint (a desired speed scale) — and never
## touches velocity, acceleration, or the resolved is_sprinting directly. All
## physical integration (turning penalties, accel/friction curves, stamina
## gating of sprint, move_and_slide()) belongs to the controller; a wrong
## tactical read here can only ever surface as a mishit pass or a bad run, not
## as broken player physics. CPU players are bound by exactly the same weight
## model as the human one for that reason.
##
## Scheduling: the decision block is time-sliced on a 15-frame stagger keyed to
## player_index, so the 22 brains spread their evaluations across the interval
## rather than all thinking on the same tick. Steering still runs every physics
## frame, so staggering costs nothing in responsiveness. At the engine's fixed
## 60Hz physics tick this realizes a 250ms tactical slice per player (see
## TACTICAL_SLICE_SECONDS) — heavy utility scoring runs once a slice, and the
## chosen action is held (current_action, plus whichever _cached_* target it
## resolved to) until the next slice. _validate_action_plan() runs every frame
## regardless of slice boundary and can abort a queued Pass mid-slice if its
## lane closes before the kick fires.
##
## Spatial reads: nothing here scans the scene tree. Every teammate/opponent
## query indexes MatchWorldModel, which refreshes once per frame at
## process_priority -100, ahead of this node's 0.
##
## Depends on: Pseudo3DBall, HeavyPlayerController (as parent node), MoodSystem
## (read via player.get_mood() to bias vision/composure/aggression at the
## decision site — mood never touches the exported attributes themselves),
## PitchBoundary (bound via bind_boundary(), used for goalkeeper positioning),
## MatchWorldModel (autoload spatial cache), UtilityMath (static helpers).
##
## Signals consumed:
##   GameEvents.formation_anchors_changed(team, new_anchors)
##     Raised by ManagerDirector._apply_formation() whenever a team's shape is
##     (re)applied — at bind time, at every kickoff, and on a mid-match
##     tactical shift. new_anchors maps player_index (int) to a world-space
##     Vector2. _on_formation_changed() adopts this player's entry and refreshes
##     the cached off-ball target so the new shape is steered to on the very
##     next frame rather than at the next decision tick.
##
## Exposes: bind_ball(), bind_boundary(), refresh_spawn_position(),
##          evaluate_tactical_action(), calculate_pressure_index(),
##          get_target_position(), ball
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
## Seconds between decision re-evaluations.
## Deprecated: superseded by the UPDATE_INTERVAL frame stagger.
## Retained for .tscn backwards-compatibility only — ManagerDirector still
## writes it from manager pressing intensity, and removing the export would
## drop that value out of every serialised scene.
@export var decision_interval: float = 0.25:
	set(value):
		decision_interval = value
		# Map the legacy seconds value back onto pressing intensity so a
		# ManagerDirector write still drives AI update speed. 0.0 → setter
		# input clamps to 25 frames, 0.25 → 15 frames, anything larger → 7.
		set_pressing_intensity(clampf(value / 0.25, 0.0, 1.0))
## True for the goalkeeper — swaps evaluate_tactical_action() for a simple
## stay-near-goal/chase-goal-area rule instead of the outfield decision tree.
@export var is_goalkeeper: bool = false
## This player's slot in MatchWorldModel. Assigned by
## HeavyPlayerController._register_with_world_model() at spawn; it is both the
## index used for every spatial read and the phase offset of the frame stagger.
@export var player_index: int = 0

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

## Minimum ball-velocity-to-goal alignment (dot product) for the goalkeeper's
## per-frame dive trigger to treat the ball as a shot on target. 0.55 admits
## shots within ~56° of straight at goal — angled near/far-post efforts —
## without triggering dives on clearances only vaguely goalward.
const GOALIE_DIVE_DOT_THRESHOLD: float = 0.55
## Ball speed above which an aligned ground shot counts as a dive threat; an
## airborne ball qualifies regardless of speed.
const GOALIE_DIVE_SPEED_THRESHOLD: float = 200.0
## Seconds a committed dive holds before the keeper returns to patrol.
const GOALIE_DIVE_DURATION: float = 0.5
## Knockback impulse applied to an opponent caught in the crowd-knockdown
## hitbox during a dive.
const GOALIE_KNOCKDOWN_IMPULSE: float = 220.0

## Physics frames between decision re-evaluations. Combined with player_index as
## a phase offset, this spreads 22 brains over 15 frames — at most two think on
## any given tick instead of all of them.
const UPDATE_INTERVAL: int = 15

## Documents the wall-clock cadence UPDATE_INTERVAL realizes at the engine's
## fixed 60Hz physics tick — the "250ms tactical slice" the AI research report
## calls for. Frames remain the source of truth for scheduling per
## ai-architect.md's mandated ShouldUpdate(i,f) = ((i+f) % N == 0) stagger;
## this constant is not read anywhere and exists purely so the 0.25s figure is
## named in code rather than only in comments.
const TACTICAL_SLICE_SECONDS: float = UPDATE_INTERVAL / 60.0

## Running decision interval, adjusted by set_pressing_intensity(). Starts at
## the UPDATE_INTERVAL default and is the value the stagger gate actually reads.
var _effective_update_interval: int = UPDATE_INTERVAL

## Seconds a designated pass receiver commits to running onto the ball, ignoring
## its own decision tree. Without it the receiver re-evaluates mid-flight and
## can turn away from a pass that was played to where it was going.
const PASS_LOCK_DURATION: float = 0.35

## Minimum clearance, in pixels, an opponent must leave either side of a passing
## lane before that lane counts as open.
const PASS_LANE_CLEARANCE: float = 45.0

## Reaction time fed to UtilityMath.calculate_intercept_point() — the beat
## between reading the ball's line and actually setting off after it.
const INTERCEPT_REACTION_TIME: float = 0.08

var player: HeavyPlayerController = null
var ball: Pseudo3DBall = null
var pitch_boundary: PitchBoundary = null
var current_action: StringName = &"MaintainFormation"

## Counts down while a committed GoalieDive is in progress.
var _goalie_dive_timer: float = 0.0

## Deprecated alongside decision_interval: the runtime no longer decrements or
## reads this. Kept only so any external reference still resolves.
var _decision_cooldown: float = 0.0

## Maps a 0.0–1.0 pressing intensity onto a per-decision frame interval:
## 0.0 → 25 frames (lazy), 0.5 → 15 frames (default), 1.0 → 7 frames (high
## press). The result is clamped to [5, 30] before being stored.
func set_pressing_intensity(intensity: float) -> void:
	_effective_update_interval = clampi(roundi(lerpf(25.0, 7.0, intensity)), 5, 30)

## Physics frames elapsed. Increments every frame regardless of whether this
## frame is a decision frame.
var _frame_counter: int = 0

## Counts down while this player is committed to a pass played to them.
var _pass_lock_timer: float = 0.0

## The player who initiated the pass that set the lock. If ball possession
## changes away from this player before the lock expires, the pass never
## happened and the lock is cancelled immediately.
var _pass_lock_passer: HeavyPlayerController = null

## The team that last touched the ball as of the previous physics frame.
## Used to detect possession changes and force an immediate re-evaluation.
var _last_possession_team: int = -1

## Off-ball target cached from the last decision tick. _find_open_space_target()
## walks the whole world model, which must stay on the decision stagger rather
## than the physics frame rate — get_target_position() is called from
## _steer_for_action() every physics frame, so it reads this cache instead of
## recomputing it each frame.
var _cached_space_target: Vector2 = Vector2.ZERO
## Teammate targeted by the last "Pass" decision. Cleared once the pass is
## struck or the decision changes away from passing.
var _cached_pass_target: HeavyPlayerController = null
## Predicted ball-intercept point cached from the last decision tick, used
## while chasing/clearing so steering doesn't recompute the intercept every
## physics frame.
var _cached_intercept: Vector2 = Vector2.ZERO
## Teammate-repulsion vector cached from the last decision tick. Up to 14
## frames stale, which is imperceptible for an off-ball player drifting into
## space and saves a full roster walk every frame.
var _cached_separation: Vector2 = Vector2.ZERO

## Reused across decision ticks so evaluate_tactical_action() never allocates a
## generator. Reseeded per tick to keep the noise deterministic per player.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Scratch list handed to evaluate_tactical_action(). Refilled in place each
## decision tick rather than reallocated. Only _find_nearby_opponents() writes
## it, and only one call is live at a time.
var _opponents_buffer: Array[Node2D] = []


func _ready() -> void:
	# Between MatchWorldModel (-100), which refreshes the spatial cache, and
	# HeavyPlayerController (100), which consumes the steering this produces.
	process_priority = 0

	player = get_parent() as HeavyPlayerController
	if formation_anchor == Vector2.ZERO and player != null:
		formation_anchor = player.global_position
	_cached_space_target = formation_anchor
	_last_possession_team = -1

	GameEvents.formation_anchors_changed.connect(_on_formation_changed)


## The pitch calls this after spawning so the brain knows which ball to track.
func bind_ball(match_ball: Pseudo3DBall) -> void:
	ball = match_ball


## The pitch calls this after spawning so a goalkeeper's brain can measure
## distance to its own goal centre.
func bind_boundary(b: PitchBoundary) -> void:
	pitch_boundary = b


## Removed: previously refreshed a cached goalkeeper goal-line X for future
## consumers (rushes, GK swaps). That cache (_spawn_x) is dead state — written
## but never read — and has been deleted. Live patrol/dive logic derives the
## line from pitch_boundary at the point of use, so no refresh is needed.
## Kept as a no-op so the PitchScene call site and the Exposes header above stay
## valid while the dead cache is gone. TODO(Phase-2): remove this function and
## its call site in PitchScene.gd when the GK rush/swap consumer is implemented
## or abandoned.
func refresh_spawn_position() -> void:
	pass


## False for a goalkeeper once the ball is within 50px of their own goal's
## scoring X line — prevents "catching" a shot that has already beaten them.
## Always true for outfield players. Call this at the possession-assignment
## site (wherever ball.set_possessor() is invoked), never from the decision
## tick — carrying eligibility must be checked at the moment it matters.
func can_carry_ball() -> bool:
	if not is_goalkeeper or player == null or pitch_boundary == null or ball == null:
		return true
	var goal_x: float = pitch_boundary.get_goal_centre(player.team).x
	return absf(ball.global_position.x - goal_x) > 50.0


## Re-applies a substitute's personality attributes onto this already-bound
## brain. formation_anchor, role and is_goalkeeper are left untouched — the
## incoming player inherits this slot's tactical identity exactly as-is.
func apply_player_data(p: PlayerData) -> void:
	vision_attribute = p.vision
	composure_attribute = p.composure
	aggression_attribute = p.aggression
	formation_ball_weight = p.formation_ball_weight


## Adopts a new formation anchor pushed by this team's ManagerDirector.
## new_anchors maps player_index (int) → world-space Vector2.
func _on_formation_changed(team_id: int, new_anchors: Dictionary) -> void:
	if player == null or player.team != team_id:
		return
	if not new_anchors.has(player_index):
		return

	formation_anchor = new_anchors[player_index]
	# Steer to the new shape on the next frame rather than waiting out the
	# remainder of the stagger interval.
	_cached_space_target = formation_anchor


func _physics_process(delta: float) -> void:
	if player == null or ball == null or player.is_user_controlled:
		return
	if not GameManager.is_in_play():
		player.movement_intent = Vector2.ZERO
		return

	# Detect possession changes and force an immediate re-evaluation this frame
	# rather than waiting for the stagger interval — eliminates the 250ms
	# "standing around" moment after every turnover.
	if ball != null:
		var current_possession_team: int = ball.last_touched_by.team if ball.last_touched_by != null else -1
		if current_possession_team != _last_possession_team:
			_last_possession_team = current_possession_team
			# Reset the frame counter so this player evaluates on its next tick.
			# Subtracting player_index ensures the evaluation lands on a frame
			# where ((_frame_counter + player_index) % _effective_update_interval == 0).
			_frame_counter = _effective_update_interval - player_index - 1

	# Goalkeeper dive reaction cannot wait for the 15-frame decision stagger —
	# a shot crosses the six-yard box in a handful of physics frames — so it is
	# evaluated fresh every frame here, ahead of the stagger gate below.
	if is_goalkeeper:
		_check_goalkeeper_dive_trigger(delta)

	# Receiver lock: a player a pass was just played to runs onto it and does
	# not re-decide mid-flight. Checked before the frame counter so the lock is
	# never skipped by landing on a decision frame.
	if _pass_lock_timer > 0.0:
		# Interrupt the lock if the passer lost the ball before the kick fired —
		# e.g. a tackle won possession first, or the passer entered a TackleState.
		# Committing to a run onto a ball that was never kicked strands the
		# receiver out of formation while an opponent breaks away.
		if ball != null and ball.possessor != _pass_lock_passer:
			_pass_lock_timer = 0.0
			_pass_lock_passer = null
		else:
			_pass_lock_timer -= delta
			if _pass_lock_timer <= 0.0:
				_pass_lock_passer = null
			player.movement_intent = _steer_toward_ball_direct()
		return

	# Mid-slice validation: cheap, runs every frame regardless of whether this
	# is a decision tick, and only does real work while a Pass is queued — an
	# opponent can step into the lane in the ~250ms between slices, and the
	# receiver can be sent off before the kick fires.
	_validate_action_plan()

	_frame_counter += 1

	if (_frame_counter + player_index) % _effective_update_interval == 0:
		if is_goalkeeper:
			# GoaliePatrol is the only decision-tree action a keeper ever
			# picks; a committed dive must not be clobbered by this re-affirm.
			if current_action != &"GoalieDive":
				current_action = evaluate_tactical_action(_find_nearby_opponents())
		else:
			current_action = evaluate_tactical_action(_find_nearby_opponents())
			_cached_space_target = _find_open_space_target()
			_cached_separation = _separation_force()
			if current_action == &"ChaseBall" or current_action == &"PanicClear":
				_cached_intercept = _predict_intercept_position()

	player.movement_intent = _steer_for_action()


## Straight run at the ball, used while the receiver lock is held. Deliberately
## simpler than _steer_for_action(): no separation, no formation spring — the
## whole point of the lock is that nothing pulls the receiver off the ball.
func _steer_toward_ball_direct() -> Vector2:
	if ball == null or player == null:
		return Vector2.ZERO
	var offset: Vector2 = ball.global_position - player.global_position
	if offset.length() < ARRIVE_RADIUS:
		return Vector2.ZERO
	return offset.normalized()


## Checks the plan chosen at the last tactical slice against the current world
## state and aborts it if it has gone stale. Only Pass needs this: ChaseBall,
## PanicClear, AttemptDribble and AttemptShoot all re-read the ball's live
## position every frame via get_target_position()/_steer_for_action(), so they
## never hold a stale target. A queued Pass is the one action that commits to
## a specific teammate and lane at the slice tick and then waits — sometimes
## several frames — for the ball to be in foot range before it actually fires.
func _validate_action_plan() -> void:
	if current_action != &"Pass" or _cached_pass_target == null:
		return
	if not _is_pass_plan_still_valid():
		_abort_action_plan()


## True if the queued pass is still safe to hit: the receiver is alive, still
## registered in the world model (a red card nulls its slot without freeing
## the node), still a teammate, and the lane between the ball and them is
## still clear of opponents. Re-checks only the one already-cached candidate —
## cheap enough to run every frame, unlike _find_best_pass_target()'s full
## roster scan for the best candidate.
func _is_pass_plan_still_valid() -> bool:
	if not is_instance_valid(_cached_pass_target):
		return false
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or ball == null or player == null:
		return false
	if not world.is_slot_live(_cached_pass_target.world_index):
		return false
	if _cached_pass_target.team != player.team:
		return false

	var ball_pos: Vector2 = ball.global_position
	var target_pos: Vector2 = _cached_pass_target.global_position
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		if not is_instance_valid(world.player_nodes[i]):
			continue
		if world.player_teams[i] == player.team:
			continue
		if UtilityMath.is_lane_blocked(ball_pos, target_pos, world.player_positions[i], PASS_LANE_CLEARANCE):
			return false
	return true


## Clean abort path for a stale plan: drop back to the conservative default
## and pull this player's next slice forward to the very next frame instead of
## waiting out the remainder of _effective_update_interval, so the abort reads
## as an instant change of mind rather than a freeze. There is no controller
## intent to unwind — the kick that would have committed the receiver's
## pass-lock (see _steer_for_action()'s Pass-execution block) never fired, so
## the receiver was never touched and nothing downstream needs cleanup beyond
## this brain's own cached target.
func _abort_action_plan() -> void:
	_cached_pass_target = null
	current_action = &"MaintainFormation"
	_frame_counter = _effective_update_interval - player_index - 1


## Runs every physics frame for a goalkeeper — not gated by UPDATE_INTERVAL —
## so a shot is reacted to within a frame or two rather than up to 15 frames
## late. While a dive is already committed this instead counts down its
## recovery and hands control back to GoaliePatrol once it expires.
func _check_goalkeeper_dive_trigger(delta: float) -> void:
	if pitch_boundary == null or ball == null or player == null:
		return

	if current_action == &"GoalieDive":
		_goalie_dive_timer -= delta
		if _goalie_dive_timer <= 0.0:
			current_action = &"GoaliePatrol"
		return

	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(player.team)
	var to_goal: Vector2 = goal_centre - ball.global_position
	var ball_vel: Vector2 = ball.velocity
	if to_goal.is_zero_approx() or ball_vel.is_zero_approx():
		return

	var facing_goal: float = ball_vel.normalized().dot(to_goal.normalized())
	if facing_goal <= GOALIE_DIVE_DOT_THRESHOLD:
		return

	var is_shot_threat: bool = ball_vel.length() > GOALIE_DIVE_SPEED_THRESHOLD or ball.is_airborne()
	if not is_shot_threat:
		return

	# Y-intercept of the ball's current velocity line with the keeper's own
	# goal line (the same X the patrol derives live from the boundary) — a
	# straight-line projection, not a multi-step trajectory walk.
	if is_zero_approx(ball_vel.x):
		return
	var time_to_line: float = (goal_centre.x - ball.global_position.x) / ball_vel.x
	# 120ms tolerance: a keeper can still palm a ball that has barely crossed
	# the line, so a strictly negative time_to_line must not kill the dive.
	if time_to_line < -0.12:
		return

	_cached_intercept = Vector2(goal_centre.x, ball.global_position.y + ball_vel.y * time_to_line)
	current_action = &"GoalieDive"
	_goalie_dive_timer = GOALIE_DIVE_DURATION


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
	# scorer sees the same answer rather than running independent scans.
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

	# A defender who is not yet turned toward the ball should not immediately
	# lunge — the tackle will miss and may be a foul.
	if ball != null and player != null:
		var facing_dot: float = player.get_facing_dot(ball.global_position)
		# Penalty ramps from 0 at dot >= 0.64 (within 50° cone) to 0.45 at
		# dot = -1.0 (fully back-facing) — capped low enough that a defender
		# still closes down a nearby ball rather than standing off it.
		var back_penalty: float = clampf((0.64 - facing_dot) / 1.64, 0.0, 1.0) * 0.45
		base = clampf(base - back_penalty, 0.0, 1.0)

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

	# If a facing opponent is within the pressure radius, dribbling into them
	# risks a clean tackle. Test is "is the OPPONENT facing US" — the same
	# check TackleState.MIN_FACING_DOT (0.42) applies to the tackler, mirrored
	# here so a set defender scores as a threat before the tackle even starts.
	if player != null:
		var world: MatchWorldModel = MatchWorldModel.instance
		if world != null:
			for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
				var other: HeavyPlayerController = world.player_nodes[i]
				if not is_instance_valid(other) or other == player:
					continue
				if world.player_teams[i] == player.team:
					continue
				var dist: float = player.global_position.distance_to(world.player_positions[i])
				if dist < PRESSURE_RADIUS:
					# get_facing_dot() is read live off the node rather than
					# from the cache: the world model stores position and
					# velocity, not heading, and facing lags velocity through a
					# turn — which is exactly the case this check is about.
					# 0.42 mirrors TackleState.MIN_FACING_DOT — keep in sync.
					if other.get_facing_dot(player.global_position) >= 0.42:
						base *= 0.40  # Opponent is set up to tackle — don't dribble in
						break

	return clampf(base, 0.0, 1.0)


## Score for attempting a shot on goal.
## Only legal when the player owns the ball and is within shooting range.
## Aggression drives the base desire; proximity and pressure add urgency.
func _score_shoot(ctx: UtilityContext) -> float:
	if not ctx.is_possessor:
		return 0.0
	if ctx.dist_to_goal > 320.0:
		return 0.0
	var base: float = ctx.eff_aggression * 0.70
	# The closer to goal, the harder the shot is to ignore.
	var prox_bonus: float = clampf(1.0 - ctx.dist_to_goal / 320.0, 0.0, 1.0) * 0.30
	# Under pressure, get the shot off before being tackled.
	var pressure_urgency: float = ctx.pressure * ctx.eff_aggression * 0.15
	return clampf(base + prox_bonus + pressure_urgency, 0.0, 1.0)


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
		# GoaliePatrol is the sole decision-tree action for a keeper — the
		# per-frame dive trigger in _check_goalkeeper_dive_trigger() is what
		# ever moves them off it, into GoalieDive.
		return &"GoaliePatrol"

	var ctx: UtilityContext = _build_context(defenders_nearby)

	if ctx.pressure > 0.85 and ctx.eff_composure < 0.45:
		return &"PanicClear"

	# --- Utility scoring ---
	# Hard guards above have already filtered out PanicClear.
	# Now build a scored candidate list — the highest score wins.
	# Ties are broken by the order of the array (pass > chase > space > dribble > formation).

	# Cache the pass target now so _score_pass() and _steer_for_action()
	# both see the same answer without a second roster walk.
	var pass_target: HeavyPlayerController = _find_best_pass_target()
	if pass_target != null:
		_cached_pass_target = pass_target

	var candidates: Array[Dictionary] = [
		{ &"action": &"Pass",              "score": _score_pass(ctx)              },
		{ &"action": &"ChaseBall",         "score": _score_chase(ctx)             },
		{ &"action": &"FindSpace",         "score": _score_find_space(ctx)        },
		{ &"action": &"AttemptDribble",    "score": _score_dribble(ctx)           },
		{ &"action": &"AttemptShoot",      "score": _score_shoot(ctx)             },
		{ &"action": &"MaintainFormation", "score": _score_maintain_formation(ctx)},
	]

	# Add a small noise term so two players in identical situations make
	# slightly different choices — they won't always run to the same spot.
	# Noise is seeded from the player's instance id so it is deterministic per
	# player but different between players; the match tick varies it per tick.
	# The generator itself is a class member, reseeded rather than reallocated.
	var noise_seed: int = player.get_instance_id() + GameManager.get_match_tick()
	_rng.seed = noise_seed
	for c: Dictionary in candidates:
		c["score"] = clampf(c["score"] + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)

	var best_action: StringName = &"MaintainFormation"
	var best_score: float = -1.0
	for c: Dictionary in candidates:
		if c["score"] > best_score:
			best_score = c["score"]
			best_action = c[&"action"]

	return best_action


## Scores every same-team, non-GK, non-self teammate by openness (distance
## from the nearest opponent) and forward positioning, rejecting any candidate
## whose passing lane an opponent is standing in. Returns null if nothing
## scores above the minimum openness threshold.
func _find_best_pass_target() -> HeavyPlayerController:
	if ball == null or player == null:
		return null
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return null

	var attack_dir: Vector2 = Vector2(1.0, 0.0) if player.team == GameManager.TEAM_A else Vector2(-1.0, 0.0)
	var ball_pos: Vector2 = ball.global_position

	# Recompute effective composure locally (same pattern as evaluate_tactical_action).
	var mood_node: MoodSystem = player.get_mood() if player != null else null
	var eff_composure: float = composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0)
	eff_composure = clampf(eff_composure, 0.0, 1.0)

	var best_target: HeavyPlayerController = null
	var best_score: float = 60.0  # Minimum openness threshold in pixels

	for c: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var candidate: HeavyPlayerController = world.player_nodes[c]
		if not is_instance_valid(candidate) or candidate == player:
			continue
		if world.player_teams[c] != player.team:
			continue
		var candidate_brain := candidate.get_node_or_null("PlayerBrain") as PlayerBrain
		if candidate_brain != null and candidate_brain.is_goalkeeper:
			continue

		var candidate_pos: Vector2 = world.player_positions[c]
		var to_candidate: Vector2 = candidate_pos - ball_pos
		var forward_dot: float = to_candidate.normalized().dot(attack_dir)
		# No backward passes unless composure is high (safety valve under pressure).
		if forward_dot < -0.2 and eff_composure < 0.55:
			continue

		# Lane check: an opponent standing in the passing lane makes the pass an
		# interception, however open the receiver looks.
		var lane_clear: bool = true
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			if not is_instance_valid(world.player_nodes[i]):
				continue
			if world.player_teams[i] == player.team:
				continue
			if UtilityMath.is_lane_blocked(
					ball_pos,
					candidate_pos,
					world.player_positions[i],
					PASS_LANE_CLEARANCE):
				lane_clear = false
				break
		if not lane_clear:
			continue

		# Openness, straight off the world model — no second roster walk.
		var min_opp_dist: float = world.nearest_opponent_dist_to(candidate_pos, player.team)

		var forward_bonus: float = clampf(forward_dot, 0.0, 1.0) * 40.0
		var score: float = min_opp_dist + forward_bonus
		if score > best_score:
			best_score = score
			best_target = candidate

	return best_target


## Returns true only if this player is the most appropriate chaser on the team.
## "Most appropriate" means: among all teammates, this player is one of the
## role's budgeted closest to the ball, AND within that role's max chase
## distance. This prevents all outfield players from simultaneously deciding
## to chase.
func _should_chase_ball() -> bool:
	if ball == null or player == null:
		return false
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
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

	var ball_pos: Vector2 = ball.global_position
	var my_dist: float = player.global_position.distance_to(ball_pos)
	if my_dist > max_dist:
		return false

	# Count how many same-role same-team players are closer to the ball than me.
	# If fewer than `budget` are closer, I am within the allowed chasers.
	var closer_count: int = 0
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] != player.team:
			continue
		# Role lives on the brain, which the world model deliberately does not
		# cache — it caches spatial state, not behaviour.
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain == null or other_brain.role != role:
			continue
		if world.player_positions[i].distance_to(ball_pos) < my_dist:
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

	if is_goalkeeper:
		match current_action:
			&"GoalieDive":
				return _cached_intercept if _cached_intercept != Vector2.ZERO else _goalie_patrol_target()
			_:
				return _goalie_patrol_target()

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
		&"AttemptShoot":
			return ball.global_position if ball != null else formation_anchor
		_:
			return _cached_space_target


## Closed-form intercept: where this player and the decelerating ball can first
## meet, given the player's current top speed.
##
## Replaces the old 30-step trajectory walk. Pseudo3DBall sheds
## `pitch_friction * FRICTION_SCALE` px/s of ground speed per second — the
## exported coefficient alone is not the deceleration, so the combined scalar is
## what the solver needs.
func _predict_intercept_position() -> Vector2:
	if ball == null or player == null:
		return ball.global_position if ball != null else player.global_position

	return UtilityMath.calculate_intercept_point(
		player.global_position,
		player.get_current_top_speed(),
		ball.global_position,
		ball.velocity,
		ball.pitch_friction * Pseudo3DBall.FRICTION_SCALE,
		INTERCEPT_REACTION_TIME
	)


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

	# The shape breathes toward the ball by the team's compactness setting.
	# Every anchor read inside this function uses the drifted anchor; the
	# exported formation_anchor itself is never modified here.
	#
	# TUNING NOTE: three branches below then lerp toward the ball a second time
	# (the midfield's lateral press, the attacker's drop-off, the defender's
	# compression). Those pulls now compound with this one, so effective
	# ball-tracking is stronger than before the dynamic anchor existed — for a
	# midfielder at formation_ball_weight 0.3, roughly 0.51 rather than 0.30 on
	# the X axis. That is the intended direction, but the per-branch constants
	# were tuned against a static anchor and are worth a pass on the pitch.
	var dynamic_anchor: Vector2 = formation_anchor.lerp(ball_pos, formation_ball_weight)

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
				var drop_target: Vector2 = dynamic_anchor
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
				var defend_pos: Vector2 = dynamic_anchor
				defend_pos.x = lerpf(defend_pos.x, ball_pos.x, formation_ball_weight)
				return defend_pos

		Role.OUTFIELD_DEFENDER:
			if has_ball:
				# When team has the ball, hold the defensive line — do NOT
				# drift forward. Compress slightly to offer a safe back-pass.
				var safe_pos: Vector2 = dynamic_anchor
				safe_pos = safe_pos.lerp(ball_pos, 0.08)
				return safe_pos
			else:
				# Mark the nearest opposing attacker who is in a dangerous
				# position (forward of the ball). If no threat, hold the line.
				var threat: HeavyPlayerController = _find_nearest_threatening_opponent()
				if threat != null:
					# Position between the threat and our own goal — not on top
					# of them, but cutting the passing lane.
					var goal_centre: Vector2 = dynamic_anchor  # anchor IS the defensive line
					return threat.global_position.lerp(goal_centre, 0.45)
				return dynamic_anchor

		_:
			return dynamic_anchor


## Samples 5 lateral positions at the opponent's defensive third and returns
## the one with the most open space (furthest average distance from defenders).
func _find_channel_run_target(ball_pos: Vector2) -> Vector2:
	if pitch_boundary == null or player == null:
		return formation_anchor
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
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
	# biased toward the flanks. Five is kept rather than trimmed to three: the
	# samples are what distinguish a near-post run from a far-post one, and
	# collapsing them loses the wide channels this function exists to find.
	var pitch_top: float = bounds.position.y + 40.0
	var pitch_bottom: float = bounds.end.y - 40.0

	var best_pos: Vector2 = formation_anchor
	var best_score: float = -INF

	for s: int in range(5):
		var t: float = float(s) / 4.0
		var candidate: Vector2 = Vector2(attack_x, lerpf(pitch_top, pitch_bottom, t))

		# Openness, straight off the world model.
		var min_opp_dist: float = world.nearest_opponent_dist_to(candidate, player.team)

		# Also penalise positions where a teammate is already standing nearby.
		var teammate_penalty: float = 0.0
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			var mate: HeavyPlayerController = world.player_nodes[i]
			if not is_instance_valid(mate) or mate == player:
				continue
			if world.player_teams[i] != player.team:
				continue
			var td: float = candidate.distance_to(world.player_positions[i])
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
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return null

	var centre_x: float = pitch_boundary.get_centre_spot().x
	var best: HeavyPlayerController = null
	var best_dist: float = 300.0  # Only mark opponents within this radius

	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] == player.team:
			continue

		# Only threatening if they are between us and our goal.
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain != null and other_brain.role == PlayerBrain.Role.OUTFIELD_ATTACKER:
			var other_pos: Vector2 = world.player_positions[i]
			var d: float = player.global_position.distance_to(other_pos)
			# Threatening if they have pushed into our defensive half (goals
			# sit on the X ends — see PitchBoundary.get_goal_centre()).
			var toward_goal: bool
			if player.team == GameManager.TEAM_A:
				toward_goal = other_pos.x < centre_x
			else:
				toward_goal = other_pos.x > centre_x
			if toward_goal and d < best_dist:
				best_dist = d
				best = other

	return best


## Repels this player from teammates within sep_radius so off-ball players
## don't stack on top of each other.
func _separation_force(sep_radius: float = 55.0) -> Vector2:
	if player == null:
		return Vector2.ZERO
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return Vector2.ZERO

	var force: Vector2 = Vector2.ZERO
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] != player.team:
			continue
		var offset: Vector2 = player.global_position - world.player_positions[i]
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
	if is_goalkeeper:
		return _steer_goalkeeper()

	# --- Pass execution ---
	if current_action == &"Pass" and _cached_pass_target != null and is_instance_valid(_cached_pass_target):
		if player.global_position.distance_to(ball.global_position) < 80.0 and player.get_ball_in_foot_range() != null:
			var lead_pos: Vector2 = _cached_pass_target.global_position + _cached_pass_target.velocity * 0.3
			var aim: Vector2 = (lead_pos - ball.global_position).normalized()
			ball.apply_kick(aim * 260.0, 0.0, player)

			# Commit the receiver to the ball for a beat. Without this the
			# receiver's own decision tick can turn it away from a pass played
			# into the space ahead of it.
			var target_brain: PlayerBrain = \
				_cached_pass_target.get_node_or_null("PlayerBrain") as PlayerBrain
			if target_brain != null:
				target_brain._pass_lock_timer = PASS_LOCK_DURATION
				target_brain._pass_lock_passer = ball.possessor

			_cached_pass_target = null
			current_action = &"MaintainFormation"

	# --- Panic clear execution ---
	# Boot it toward the nearest touchline rather than upfield — a panicked
	# clearance under heavy pressure is about getting rid of the ball safely,
	# not building an attack.
	if current_action == &"PanicClear" and pitch_boundary != null \
			and player.global_position.distance_to(ball.global_position) < 80.0 \
			and player.get_ball_in_foot_range() != null:
		var clear_dir: Vector2 = Vector2(0.0, signf(player.global_position.y - pitch_boundary.get_centre_spot().y))
		if is_zero_approx(clear_dir.y):
			clear_dir.y = 1.0
		ball.apply_kick(clear_dir * 300.0, 0.0, player)
		current_action = &"MaintainFormation"

	# --- Shoot execution ---
	if current_action == &"AttemptShoot" and pitch_boundary != null \
			and player.global_position.distance_to(ball.global_position) < 80.0 \
			and player.get_ball_in_foot_range() != null:
		var opp_team: int = 1 - player.team
		var goal_centre: Vector2 = pitch_boundary.get_goal_centre(opp_team)
		# Add slight randomness based on composure — low composure = wilder shot.
		var mood_node: MoodSystem = player.get_mood() if player != null else null
		var eff_composure: float = clampf(composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0), 0.0, 1.0)
		var spread: float = (1.0 - eff_composure) * 55.0  # pixels of Y scatter at low composure
		var aim_y: float = goal_centre.y + _rng.randf_range(-spread, spread)
		var aim_target: Vector2 = Vector2(goal_centre.x, aim_y)
		var aim_dir: Vector2 = (aim_target - ball.global_position).normalized()
		# Shot power scales with how close to goal: max 520px/s, min 380px/s.
		var dist_ratio: float = clampf(1.0 - player.global_position.distance_to(goal_centre) / 320.0, 0.0, 1.0)
		var shot_power: float = lerpf(380.0, 520.0, dist_ratio)
		ball.apply_kick(aim_dir * shot_power, 0.0, player)
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
		&"AttemptShoot":
			# Move toward the ball to get it in foot range.
			seek_target = ball.global_position if ball != null else player.global_position
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

	# 2. Separation — only off-ball so chasers aren't pushed off the intercept
	# line. Read from the decision-tick cache rather than recomputed here.
	var sep_force: Vector2 = Vector2.ZERO
	if current_action != &"ChaseBall" and current_action != &"PanicClear":
		sep_force = _cached_separation * 0.40

	# 3. Formation spring — gentle pull back when very far from anchor
	var spring_force: Vector2 = Vector2.ZERO
	var anchor_offset: Vector2 = formation_anchor - player.global_position
	if anchor_offset.length() > CHASE_RADIUS * 1.5:
		spring_force = anchor_offset.normalized() * 0.15

	# 4. Assist force — pulls attackers/midfielders finding space into a
	# forward passing lane ahead of the ball carrier, mirrored to whichever
	# side of the ball this player already favours.
	var assist_force: Vector2 = _assist_force()

	# Sprint is expressed as intent, not the resolved is_sprinting — the
	# controller alone decides whether stamina actually allows it.
	player.wants_sprint = current_action == &"ChaseBall" and distance > CHASE_RADIUS * 0.5
	return (seek_force + sep_force + spring_force + assist_force).limit_length(1.0)


## Pulls a non-chasing attacker/midfielder into a forward outlet lane 120px
## ahead of the ball carrier while FindSpace is active — the spec's fourth
## steering force, distinct from the passing-triangle/channel-run targets
## _find_open_space_target() already computes for the decision-tick cache.
func _assist_force() -> Vector2:
	if current_action != &"FindSpace":
		return Vector2.ZERO
	if role != Role.OUTFIELD_ATTACKER and role != Role.OUTFIELD_MIDFIELDER:
		return Vector2.ZERO
	if ball == null or player == null:
		return Vector2.ZERO

	var attack_dir: Vector2 = Vector2(1.0, 0.0) if player.team == GameManager.TEAM_A else Vector2(-1.0, 0.0)
	var lateral_offset: float = player.global_position.y - ball.global_position.y
	var assist_target: Vector2 = ball.global_position + attack_dir * 120.0 + Vector2(0.0, lateral_offset)

	var to_assist: Vector2 = assist_target - player.global_position
	if to_assist.is_zero_approx():
		return Vector2.ZERO
	return to_assist.normalized() * 0.25


## Goal-line lock steering: patrol slides along Y between the posts, tracking
## the ball, while X stays on the goal line derived from pitch_boundary except
## during a committed dive. Replaces the outfield seek/separation/spring blend
## entirely — a keeper's movement model is fundamentally different from an
## outfield player's.
func _steer_goalkeeper() -> Vector2:
	if player == null or ball == null:
		return Vector2.ZERO

	if current_action == &"GoalieDive":
		_set_crowd_knockdown_enabled(true)
		var dive_offset: Vector2 = _cached_intercept - player.global_position
		if dive_offset.length() <= ARRIVE_RADIUS:
			player.wants_sprint = false
			return Vector2.ZERO
		player.wants_sprint = true
		return dive_offset.normalized()

	_set_crowd_knockdown_enabled(false)
	player.wants_sprint = false

	var target: Vector2 = _goalie_patrol_target()
	var offset: Vector2 = target - player.global_position
	var distance: float = offset.length()
	if distance < 0.01:
		return Vector2.ZERO

	# Proximity deceleration cushion — full pace beyond 10px of the target,
	# linearly decaying to a stop inside it, so the keeper settles onto the
	# line without jitter or overshoot.
	var proximity_factor: float = clampf(distance / 10.0, 0.0, 1.0)
	return offset.normalized() * proximity_factor


## World-space patrol point: locked to the goal-line X derived live from
## pitch_boundary, sliding along Y between the goal posts to track the ball.
## Shared by _steer_goalkeeper() and get_target_position() so the two never
## drift out of sync. Deriving the line here instead of trusting a cached
## spawn X makes the patrol correct from the very first frame and lets it
## follow the keeper's goal automatically across end swaps.
func _goalie_patrol_target() -> Vector2:
	if pitch_boundary == null or player == null or ball == null:
		return formation_anchor
	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(player.team)
	var half_mouth: float = pitch_boundary.goal_mouth_height * 0.5
	return Vector2(goal_centre.x, clampf(ball.global_position.y, goal_centre.y - half_mouth, goal_centre.y + half_mouth))


## Enables/disables the goalkeeper's crowd-knockdown hitbox for the duration
## of a dive. PermanentDamageEmitterArea does not exist in any player scene in
## this repo yet, so this is a no-op guard until that node is added.
func _set_crowd_knockdown_enabled(enabled: bool) -> void:
	if player == null:
		return
	var area := player.get_node_or_null("PermanentDamageEmitterArea") as Area2D
	if area == null:
		return
	if enabled and not area.body_entered.is_connected(_on_crowd_knockdown_body_entered):
		area.body_entered.connect(_on_crowd_knockdown_body_entered)
	area.monitoring = enabled
	area.monitorable = enabled


## No Hurt state exists in this codebase yet (see entities/player/PlayerState.gd
## for the full transition_to() set), so this reuses the existing external-
## impulse knockback — the same mechanism tackles and collisions already use —
## as the closest available stand-in for "knocked down".
func _on_crowd_knockdown_body_entered(body: Node2D) -> void:
	var opponent := body as HeavyPlayerController
	if opponent == null or player == null or opponent.team == player.team:
		return
	var away: Vector2 = opponent.global_position - player.global_position
	if away.is_zero_approx():
		away = Vector2.RIGHT
	opponent.apply_external_impulse(away.normalized() * GOALIE_KNOCKDOWN_IMPULSE)


## Every opponent currently on the pitch, as Node2D so callers that take a
## generic list keep working. Refills a member buffer rather than allocating —
## the returned Array is overwritten by the next call.
func _find_nearby_opponents() -> Array[Node2D]:
	_opponents_buffer.clear()
	if player == null:
		return _opponents_buffer
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return _opponents_buffer

	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] != player.team:
			_opponents_buffer.append(other)
	return _opponents_buffer
