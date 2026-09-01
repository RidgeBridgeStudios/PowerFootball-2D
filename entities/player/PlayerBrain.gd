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
## TrustSystem (read via player.get_trust_system() — biases which teammate
## _find_best_pass_target() picks; registered against at the moment a CPU
## pass is struck, resolved later by DribbleState),
## PitchBoundary (bound via bind_boundary(), used for goalkeeper positioning
## and, since _find_open_space_target() reads pitch_boundary.get_centre_spot()/
## pitch_size, for phase-shifted formation anchors too),
## MatchWorldModel (autoload spatial cache, including defensive_line_x — the
## shared per-team back-line depth the OUTFIELD_DEFENDER branch of
## _find_open_space_target() blends into its hold-shape target — and
## press_trigger_active/press_trigger_carrier, the pressing trigger detector's
## output, read by _score_chase() via _press_trigger_chase_bonus() to favour
## ChaseBall the moment the world model flags a football-relevant reason to
## close down; this brain never re-derives any of those trigger conditions
## itself, it only reacts to the flag), UtilityMath
## (static helpers), FormationAnchorMath (static — team-phase-aware anchor drift).
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

## Pressing-duty assignment for OUTFIELD_DEFENDER while MatchWorldModel's
## pressing trigger is active — see _resolve_defensive_duty(). Deliberately
## small: one defender presses, nearby cover blocks a lane, everyone else
## falls back to the pre-existing hold-the-line/mark-the-threat behaviour
## _find_open_space_target() already had. NONE outside a live trigger.
enum DefensiveDuty {
	NONE,          ## No active trigger, or this role does not take a duty.
	TRIGGER_PRESS, ## The one defender closest to the trigger carrier — closes down.
	COVER_SUPPORT, ##
	COVER_SHADOW,  ## A nearby defender not pressing — cuts a likely passing lane instead.
	MARKING,       ## Reserved fallback label — currently folded into RETREAT's target.
	RETREAT,       ## Too far from the trigger to be relevant — hold the defensive line.
}

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

## Distance inside which a ChaseBall-committed defender's lunge has a
## realistic chance of reaching foot-sensor range (15px, HeavyPlayer.tscn)
## before TackleState's own WINDUP+WINDOW elapses. Order-of-magnitude matched
## to TackleState.FOUL_CONTACT_RADIUS (40.0) and ShotLockState.
## CLOSE_ENOUGH_DIST (32.0) — both existing "close enough to commit" radii.
const TACKLE_ATTEMPT_RANGE: float = 36.0

## Minimum gap between CPU-initiated tackle attempts by the same brain.
## TackleState's own WINDUP(0.08)+WINDOW(0.2)+RECOVERY(0.45)=0.73s already
## locks the FSM out of re-entering TACKLE, but current_action is not reset
## when TackleState is entered (nothing in TackleState.gd touches it), so
## _should_attempt_tackle() would otherwise keep re-evaluating true every
## physics tick for the whole tackle. On a miss, ball.possessor is untouched —
## so without this, a defender whose distance/facing still qualify the
## instant RECOVERY ends (routine — a miss typically leaves the tackler still
## close to and facing the dribbler) would re-lunge immediately, every
## RECOVERY cycle. Re-armed every tick the trigger condition holds (including
## through the tackle animation itself, since current_action stays stale), so
## this is a floor measured from the LAST qualifying tick, not the first
## attempt — intentionally conservative. See AGENTS_ERRATA.md
## (cpu-players-never-gated-into-tackle-state).
const TACKLE_ATTEMPT_COOLDOWN: float = 1.5

## Additive bonus to _score_chase() while MatchWorldModel's pressing trigger
## detector has flagged a football-relevant reason to close down right now
## (a backward/square pass into pressure, the carrier facing their own goal,
## pinned on the touchline, or a heavy touch) and that trigger concerns the
## opponent currently on the ball. Small enough that a legitimately better
## option (a covering defender holding the line instead of diving in) can
## still outscore it — this nudges the chase/hold-shape balance, it does not
## override it.
const PRESS_TRIGGER_CHASE_BONUS: float = 0.18

## Extra additive bonus to _score_chase() for the single OUTFIELD_DEFENDER
## _resolve_defensive_duty() has actually assigned TRIGGER_PRESS this tick, on
## top of PRESS_TRIGGER_CHASE_BONUS above. Large enough that the coordinated
## presser decisively wins the chase/hold-shape comparison rather than merely
## nudging it -- the whole point of naming one presser is that they commit.
const DUTY_TRIGGER_PRESS_CHASE_BONUS: float = 0.30

## Distance from the pressing trigger's carrier inside which a non-pressing
## OUTFIELD_DEFENDER is close enough to matter as support -- see
## _resolve_defensive_duty(). Beyond this the defender is too far from the
## pressing situation to usefully shadow a lane and just holds the back line
## (DefensiveDuty.MARKING / RETREAT -- the pre-existing default behaviour).
const COVER_SHADOW_RADIUS: float = 320.0
## How far along the lane between the trigger carrier and this defender's own
## nearest marked threat (see _find_nearest_threatening_opponent()) the
## cover-shadow position sits. 0.0 sits on the carrier, 1.0 sits on the
## threat; 0.5 is the lane midpoint, which reads on screen as "cutting the
## pass" rather than either "guarding the ball" or "marking the man".
const COVER_SHADOW_LANE_RATIO: float = 0.5

## --- Greedy marking assignment ----------------------------------------------
## _find_nearest_threatening_opponent() used to be purely local: every
## defender independently picked its own nearest OUTFIELD_ATTACKER, with no
## coordination, so several defenders could (and in practice did — see the
## crowding-space-creation-diagnostics investigation) converge on the same
## dangerous attacker while another went completely unmarked. This section
## adds a team-wide greedy bipartite pass — attackers processed highest-threat
## first, each getting the lowest-cost still-unassigned defender — that
## _find_nearest_threatening_opponent() now prefers when available. Not an
## optimal (Hungarian) solver: ai-architect.md forbids an O(N^3) solver with
## runtime matrix allocation here, so this is deliberately the cheaper greedy
## approximation instead, O(A^2 + A*D) <= 11*11+11*11 fixed comparisons.
const MAX_MARKING_SLOTS: int = 11
const NO_MARK_INDEX: int = -1
## Recompute cadence in GameManager match ticks — matches the cadence of the
## decision tick this is only ever triggered from (see
## _maybe_recompute_team_marking()), so this does not itself add a faster
## polling loop.
const MARKING_REASSIGN_INTERVAL_TICKS: int = 15

## Indexed by world_index (0..TOTAL_PLAYERS-1); NO_MARK_INDEX if unassigned.
## Shared across every PlayerBrain instance on purpose — the assignment is a
## team-wide result, not a per-player one, and no per-instance array could
## hold it. Sized for MatchWorldModel.TOTAL_PLAYERS (22) once at class load,
## never resized after.
static var _marking_assignment: PackedInt32Array = PackedInt32Array([
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
	-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
])
## Match tick _marking_assignment was last recomputed for, per team.
static var _marking_last_tick: PackedInt32Array = PackedInt32Array([-1, -1])

## Fixed-size scratch for _recompute_team_marking(), reused in place every
## call so the O(A^2 + A*D) pass never allocates. MAX_MARKING_SLOTS covers the
## worst case of a full outfield contingent (10) with room to spare.
static var _mark_defender_idx: PackedInt32Array = PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0])
static var _mark_defender_used: PackedByteArray = PackedByteArray([0,0,0,0,0,0,0,0,0,0,0])
static var _mark_attacker_idx: PackedInt32Array = PackedInt32Array([0,0,0,0,0,0,0,0,0,0,0])
static var _mark_attacker_threat: PackedFloat32Array = PackedFloat32Array([0,0,0,0,0,0,0,0,0,0,0])
static var _mark_attacker_used: PackedByteArray = PackedByteArray([0,0,0,0,0,0,0,0,0,0,0])

## How strongly a defender's default "hold shape" X target is pulled toward
## MatchWorldModel.defensive_line_x[team] — the shared band depth — versus
## this player's own dynamic formation anchor. 0.0 would ignore the shared
## line entirely; 1.0 would make every defender's anchor identical to the
## team's line depth regardless of the manager's per-role anchor tuning.
## Blended rather than substituted, and only applied to the "hold the line"
## default target — a defender marking a genuine nearby threat (see
## _find_nearest_threatening_opponent()) is still allowed off the line.
const DEFENSIVE_LINE_DEPTH_WEIGHT: float = 0.55

## Radius inside which two same-team defenders repel each other along the
## pitch-width (Y) axis only — the "lateral spacing" half of the defensive
## line controller, distinct from the omnidirectional _separation_force()
## every off-ball player already gets. Kept X-blind so it never fights
## DEFENSIVE_LINE_DEPTH_WEIGHT's pull on the same axis.
const DEFENSIVE_LINE_SEPARATION_RADIUS: float = 90.0
## Steering weight applied to the lateral separation force in _steer_for_action().
const DEFENSIVE_LINE_SEPARATION_WEIGHT: float = 0.35

## Seconds the team phase reads TRANSITION after a possession change, before
## settling into IN_POSSESSION/OUT_OF_POSSESSION. Long enough to cover the
## scramble right after a turnover; short enough not to blur into the next
## phase read. Feeds FormationAnchorMath.get_dynamic_anchor_position().
const TRANSITION_DURATION: float = 1.5
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
const GOALIE_DIVE_DURATION: float = 0.55
## Knockback impulse applied to an opponent caught in the crowd-knockdown
## hitbox during a dive.
const GOALIE_KNOCKDOWN_IMPULSE: float = 220.0

## Safety insets from the pitch boundary edges to keep outfield players inside playable bounds.
const PITCH_TOUCHLINE_SAFETY_MARGIN: float = 35.0
const PITCH_ENDLINE_SAFETY_MARGIN: float = 45.0

## How far beyond the RAW pitch rect (PitchBoundary.get_pitch_rect(), not the
## PITCH_TOUCHLINE/ENDLINE_SAFETY_MARGIN-inset get_playable_rect()) a ball is
## still considered chaseable in _should_chase_ball()'s out-of-play gate.
## Deliberately generous relative to SetPieceCoordinator.THROW_IN_INSET
## (24px) — a throw-in ball legitimately rests just past the true touchline
## while waiting to be released, and needs a nearby player to still be able
## to close it down once it lands loose in that zone. See AGENTS_ERRATA.md
## (throw-in-ball-outside-chase-legality-rect).
const CHASE_OUT_OF_BOUNDS_TOLERANCE: float = 45.0

## "La Pausa" standstill-breaker: a possessor who has held the ball this long
## with no open teammate and would otherwise settle on MaintainFormation gets
## forced into AttemptDribble/PanicClear instead — see evaluate_tactical_action().
const LA_PAUSA_HOLD_SECONDS: float = 1.0
## Same "is this option worth anything at all" bar the existing max_offensive
## <= 0.05 floor below uses, reused here so AttemptDribble is only chosen over
## PanicClear when dribbling is genuinely viable, not just nonzero.
const LA_PAUSA_MIN_DRIBBLE_SCORE: float = 0.05

## Goalkeeper arc clamping distance off the goal line (in pixels).
const GOALIE_ARC_MIN_DIST: float = 40.0
const GOALIE_ARC_MAX_DIST: float = 90.0

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

## Seconds over which _steer_for_action() eases from the direction a player
## was actually moving in into a freshly chosen one, whenever current_action
## changes value (a turnover flipping ChaseBall -> MaintainFormation, a pass
## landing and flipping Pass -> MaintainFormation, etc). Sized against
## PASS_LOCK_DURATION/UPDATE_INTERVAL's own cadence: long enough to mask the
## instant re-decision a possession change forces (see _last_possession_team
## below) as a believable deceleration-and-redirect rather than a snap, short
## enough that a player never reads as sluggish to respond. Outfield-only —
## the goalkeeper's patrol/dive steering is a different model with its own
## proximity damping and is deliberately left unblended.
const INTENT_BLEND_DURATION: float = 0.35

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
## This tick's pressing-duty assignment (OUTFIELD_DEFENDER only) — see
## DefensiveDuty and _resolve_defensive_duty(). Recomputed alongside
## current_action at every decision tick; NONE the rest of the time.
var current_duty: DefensiveDuty = DefensiveDuty.NONE

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

## Counts down from TRANSITION_DURATION after every possession change; while
## positive, _current_team_phase() reads TRANSITION regardless of who has
## the ball.
var _transition_timer: float = 0.0

## Counts down after each CPU-initiated tackle attempt; see
## PlayerBrain.TACKLE_ATTEMPT_COOLDOWN and _should_attempt_tackle().
var _tackle_cooldown: float = 0.0

## Off-ball target cached from the last decision tick. _find_open_space_target()
## walks the whole world model, which must stay on the decision stagger rather
## than the physics frame rate — get_target_position() is called from
## _steer_for_action() every physics frame, so it reads this cache instead of
## recomputing it each frame.
var _cached_space_target: Vector2 = Vector2.ZERO
## Teammate targeted by the last "Pass" decision. Cleared once the pass is
## struck or the decision changes away from passing.
var _cached_pass_target: HeavyPlayerController = null
## Final (post-trust, post-isolation) score _find_best_pass_target() gave
## _cached_pass_target, so _score_pass() can react to "how good is this pass"
## rather than only "does one exist." Stale once _cached_pass_target is
## cleared, but never read except alongside a non-null _cached_pass_target.
var _cached_pass_score: float = 0.0
## Predicted ball-intercept point cached from the last decision tick, used
## while chasing/clearing so steering doesn't recompute the intercept every
## physics frame.
var _cached_intercept: Vector2 = Vector2.ZERO
## Teammate-repulsion vector cached from the last decision tick. Up to 14
## frames stale, which is imperceptible for an off-ball player drifting into
## space and saves a full roster walk every frame.
var _cached_separation: Vector2 = Vector2.ZERO
## Defender-only lateral (Y-axis) repulsion from nearby same-team defenders,
## cached from the last decision tick alongside _cached_separation. See
## _defensive_line_lateral_separation().
var _cached_defensive_lateral: Vector2 = Vector2.ZERO

## current_action as observed at the top of the previous _steer_for_action()
## call. Comparing against the live current_action each frame is how a
## tactical-intent change is detected — see INTENT_BLEND_DURATION.
var _blend_prev_action: StringName = &""
## The direction this player was actually steering in at the moment the most
## recent transition was detected — what _apply_intent_blend() eases FROM.
var _blend_from_intent: Vector2 = Vector2.ZERO
## Counts down from INTENT_BLEND_DURATION after a detected transition; zero
## means "no blend in progress, return the freshly computed direction as-is".
var _blend_timer: float = 0.0

## Reused across decision ticks so evaluate_tactical_action() never allocates a
## generator. Reseeded per tick to keep the noise deterministic per player.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Reusable context instance to eliminate heap allocations on hot decision paths.
var _ctx: UtilityContext = UtilityContext.new()

## Scratch list handed to evaluate_tactical_action(). Refilled in place each
## decision tick rather than reallocated. Only _find_nearby_opponents() writes
## it, and only one call is live at a time.
var _opponents_buffer: Array[Node2D] = []
var _off_ball_candidates: Array[Vector2] = []
var _opp_y_coords: Array[float] = []


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


## Playable pitch rectangle inset by safety margins so players never steer out of bounds.
func get_playable_rect() -> Rect2:
	if pitch_boundary != null:
		var r: Rect2 = pitch_boundary.get_pitch_rect()
		return Rect2(
			r.position.x + PITCH_ENDLINE_SAFETY_MARGIN,
			r.position.y + PITCH_TOUCHLINE_SAFETY_MARGIN,
			maxf(r.size.x - PITCH_ENDLINE_SAFETY_MARGIN * 2.0, 10.0),
			maxf(r.size.y - PITCH_TOUCHLINE_SAFETY_MARGIN * 2.0, 10.0)
		)
	return Rect2(-755.0, -415.0, 1510.0, 830.0)


## Clamps `pos` strictly inside the playable pitch rectangle.
func clamp_to_playable_area(pos: Vector2) -> Vector2:
	var rect: Rect2 = get_playable_rect()
	return Vector2(
		clampf(pos.x, rect.position.x, rect.end.x),
		clampf(pos.y, rect.position.y, rect.end.y)
	)


## Validates and clamps an outfield chase target inside playable bounds.
func validate_chase_intent(target: Vector2) -> Vector2:
	return clamp_to_playable_area(target)


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
	var is_throw_in_taker: bool = false
	if player.state_factory != null and player.state_factory.current_state_name == &"ThrowIn":
		is_throw_in_taker = true

	if not GameManager.is_in_play() and not is_throw_in_taker:
		player.movement_intent = Vector2.ZERO
		return

	# Detect possession changes and force an immediate re-evaluation this frame
	# rather than waiting for the stagger interval — eliminates the 250ms
	# "standing around" moment after every turnover.
	if ball != null:
		var current_possession_team: int = ball.last_touched_by.team if ball.last_touched_by != null else -1
		if current_possession_team != _last_possession_team:
			_last_possession_team = current_possession_team
			_transition_timer = TRANSITION_DURATION
			# Reset the frame counter so this player evaluates on its next tick.
			# Subtracting player_index ensures the evaluation lands on a frame
			# where ((_frame_counter + player_index) % 15 == 0).
			_frame_counter = 360 - player_index - 1

	if _transition_timer > 0.0:
		_transition_timer = maxf(_transition_timer - delta, 0.0)
	if _tackle_cooldown > 0.0:
		_tackle_cooldown = maxf(_tackle_cooldown - delta, 0.0)

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

	var dist_to_ball_sq: float = player.global_position.distance_squared_to(ball.global_position) if ball != null else 1000000.0
	var current_cadence: int = 45
	if (ball != null and ball.possessor == player) or dist_to_ball_sq < 90000.0:
		current_cadence = 8
	elif dist_to_ball_sq <= 490000.0:
		current_cadence = 20

	if (_frame_counter + player_index) % current_cadence == 0:
		if is_goalkeeper:
			# GoaliePatrol / GoalieRush evaluated on decision tick; dive is triggered per frame
			if current_action != &"GoalieDive":
				current_action = evaluate_tactical_action(_find_nearby_opponents())
				if current_action == &"GoalieRush":
					_cached_intercept = _predict_intercept_position()
		else:
			current_action = evaluate_tactical_action(_find_nearby_opponents())
			current_duty = _resolve_defensive_duty()
			_cached_space_target = _find_open_space_target()
			_cached_separation = _separation_force()
			if role == Role.OUTFIELD_DEFENDER:
				_cached_defensive_lateral = _defensive_line_lateral_separation()
			if current_action == &"ChaseBall" or current_action == &"PanicClear":
				_cached_intercept = _predict_intercept_position()

	player.movement_intent = _steer_for_action(delta)


## Straight run at the ball, used while the receiver lock is held. Deliberately
## simpler than _steer_for_action(): no separation, no formation spring — the
## whole point of the lock is that nothing pulls the receiver off the ball.
func _steer_toward_ball_direct() -> Vector2:
	if ball == null or player == null:
		return Vector2.ZERO
	var target: Vector2 = clamp_to_playable_area(ball.global_position)
	var offset: Vector2 = target - player.global_position
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
	return world.is_passing_lane_open(ball_pos, target_pos, player.team, PASS_LANE_CLEARANCE)


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
	_frame_counter = 360 - player_index - 1


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

	var half_mouth: float = pitch_boundary.goal_mouth_height * 0.5
	var predicted_y: float = ball.global_position.y + ball_vel.y * time_to_line
	if absf(predicted_y - goal_centre.y) > half_mouth + 40.0:
		return

	_cached_intercept = Vector2(goal_centre.x, predicted_y)
	current_action = &"GoalieDive"
	_goalie_dive_timer = GOALIE_DIVE_DURATION

	if player.state_factory != null and player.state_factory.current_state_name != PlayerState.GOALKEEPER_DIVE:
		var dive_state := player.state_factory.get_state(PlayerState.GOALKEEPER_DIVE) as GoalkeeperDiveState
		if dive_state != null:
			var dive_y: float = signf(predicted_y - player.global_position.y)
			if is_zero_approx(dive_y):
				dive_y = 1.0
			dive_state.dive_direction = Vector2(0.0, dive_y)
			player.state_factory.transition_to(PlayerState.GOALKEEPER_DIVE)


## Returns +1.0 for Team A (+X attacking axis) or -1.0 for Team B (-X attacking axis).
func _get_attack_sign() -> float:
	return 1.0 if player != null and player.team == GameManager.TEAM_A else -1.0


## Returns the forward attacking unit vector for this player's team.
func _get_attack_direction() -> Vector2:
	return Vector2(_get_attack_sign(), 0.0)


## Builds the UtilityContext snapshot for one decision tick (reusing _ctx in-place).
func _build_context(defenders_nearby: Array[Node2D] = []) -> UtilityContext:
	_ctx.pressure = calculate_pressure_index(defenders_nearby)

	# Read base attributes, then layer mood on top. Mood never mutates the
	# exported attributes — it is applied only at the decision site so the
	# Inspector always shows the base talent regardless of in-match state.
	var mood_node: MoodSystem = player.get_mood() if player != null else null
	_ctx.eff_vision      = clampf(vision_attribute      + (mood_node.get_vision_delta()      if mood_node != null else 0.0), 0.0, 1.0)
	_ctx.eff_composure   = clampf(composure_attribute   + (mood_node.get_composure_delta()   if mood_node != null else 0.0), 0.0, 1.0)
	_ctx.eff_aggression  = clampf(aggression_attribute  + (mood_node.get_aggression_delta()  if mood_node != null else 0.0), 0.0, 1.0)

	_ctx.dist_to_ball = player.global_position.distance_to(ball.global_position) if ball != null else INF
	_ctx.stamina_ratio = player.get_stamina_ratio()
	var is_throw_in_taker: bool = player != null and player.state_factory != null and player.state_factory.current_state_name == &"ThrowIn"
	_ctx.team_has_ball = _team_has_ball() or is_throw_in_taker
	_ctx.is_possessor  = (ball != null and ball.possessor == player) or is_throw_in_taker
	_ctx.sprint_locked = player.sprint_locked

	# Forward direction toward the opponent goal. Team A attacks toward +X.
	if pitch_boundary != null:
		var opp_team: int = 1 - player.team
		_ctx.dist_to_goal = player.global_position.distance_to(
			pitch_boundary.get_goal_centre(opp_team))
	else:
		_ctx.dist_to_goal = 800.0

	# Cache best pass target once per tactical slice here to avoid repeating
	# the entire 22-player evaluation loop in evaluate_tactical_action().
	_cached_pass_target = _find_best_pass_target(_ctx.pressure)
	_ctx.open_teammate_exists = _cached_pass_target != null
	_ctx.chase_is_legal       = _should_chase_ball()

	return _ctx


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
	# An exceptionally good pass (isolated receiver, well angled) should be
	# able to override dribbling/other actions outright rather than only
	# nudging this score within its normal band.
	if _cached_pass_score > 0.80:
		base += 0.20
	return clampf(base, 0.0, 1.0)


## Score for chasing the ball.
## Legal only when _should_chase_ball() approved it.  Closer + aggressive
## players score higher; a tired sprint-locked player scores much lower.
func _score_chase(ctx: UtilityContext) -> float:
	if not ctx.chase_is_legal:
		return 0.0
	# A loose ball has already been legality-gated in _should_chase_ball() to
	# the single closest role-eligible player (role budget + closer_count),
	# so proximity has already done its job by the time we get here.
	# Re-scoring it against CHASE_RADIUS (220px — tuned for contesting a ball
	# an OPPONENT still controls nearby) crushes prox to 0 for any loose ball
	# farther out, even though _should_chase_ball() now permits chasing a
	# loose ball well past 220px. With prox=0 the only remaining term is
	# eff_aggression*0.30 (~0.1-0.2), which _score_maintain_formation's
	# anchor-urgency term (up to 0.55) reliably beats — silently re-freezing
	# the exact case the loose-ball legality bypass exists to fix. A loose,
	# legal chase floors proximity at 1.0 instead.
	var prox: float = 1.0 if (ball != null and ball.possessor == null) \
			else clampf(1.0 - ctx.dist_to_ball / CHASE_RADIUS, 0.0, 1.0)
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

	base += _press_trigger_chase_bonus(ctx)

	# The one defender _resolve_defensive_duty() named as presser this tick
	# commits decisively rather than merely being nudged toward chasing —
	# without this, a covering teammate's own small press-trigger bonus above
	# could occasionally outscore the assigned presser and both end up diving
	# in, defeating the point of naming a single presser.
	if role == Role.OUTFIELD_DEFENDER and current_duty == DefensiveDuty.TRIGGER_PRESS:
		base += DUTY_TRIGGER_PRESS_CHASE_BONUS

	return clampf(base, 0.0, 1.0)


## Reads MatchWorldModel's pressing trigger flag rather than recomputing any
## of its five conditions here — see MatchWorldModel's "Pressing trigger
## detection" section for what can set it. Zero whenever: no trigger is
## active, this player's own team already has the ball (chasing a teammate's
## carry is not pressing), or the trigger's carrier is missing/on this
## player's own team (a backward/square pass trigger names the kicker, so a
## teammate's own backward pass must not boost this player's own chase score).
func _press_trigger_chase_bonus(ctx: UtilityContext) -> float:
	if ctx.team_has_ball or player == null:
		return 0.0
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or not world.press_trigger_active:
		return 0.0
	var carrier: HeavyPlayerController = world.press_trigger_carrier
	if not is_instance_valid(carrier) or carrier.team == player.team:
		return 0.0
	return PRESS_TRIGGER_CHASE_BONUS


## Score for finding space (off-ball intelligent run).
## High vision unlocks this; only fires when team has the ball.
func _score_find_space(ctx: UtilityContext) -> float:
	if ctx.is_possessor:
		return 0.0
	# Only make attacking runs when team has possession.
	if not ctx.team_has_ball:
		return 0.0
	# team_has_ball is last-touch-based (_team_has_ball()) and stays true even
	# once the ball has gone fully loose with nobody controlling it — without
	# this, a fast/visionary attacker's FindSpace score can comfortably
	# outscore ChaseBall's for the one player legally closest to a stalled
	# ball, sending them running further away instead of winning it back.
	# Only suppress FindSpace for THIS player when they are themselves the
	# legal chaser for that loose ball — a genuinely different teammate can
	# still make a supporting run while someone else goes to win it. See
	# AGENTS_ERRATA.md (find-space-outscores-chase-on-loose-ball).
	if ctx.chase_is_legal and ball != null and ball.possessor == null:
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
			var nearby_opponents: Array[int] = world.get_nearby_opponents(player.global_position, PRESSURE_RADIUS, player.team)
			for i: int in nearby_opponents:
				var other: HeavyPlayerController = world.player_nodes[i]
				if not is_instance_valid(other) or other == player:
					continue
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
	# "Holding shape" is an off-ball concept — a possessor can never legally
	# choose it. Without this guard the flat 0.20 floor below outscores a
	# real-but-weak Pass/Dribble/Shoot score (anything under 0.20), which
	# sits ABOVE the evaluate_tactical_action() PanicClear fallback's <= 0.05
	# threshold, so the carrier freezes in possession instead of either
	# executing that weak option or falling through to a desperation clear.
	# Mirrors the same possessor guard on _score_find_space() above.
	if ctx.is_possessor:
		return 0.0
	# Base desirability: modest but non-zero — always an option.
	var base: float = 0.20
	if not ctx.team_has_ball:
		# Defensive discipline: get back into shape when out of possession.
		if player != null:
			var anchor_dist: float = player.global_position.distance_to(formation_anchor)
			var anchor_urgency: float = clampf(anchor_dist / CHASE_RADIUS, 0.0, 1.0)
			base += anchor_urgency * 0.35
	return clampf(base, 0.0, 1.0)


## True when a loose ball is inside/near the penalty box or an unpressured attacker
## is in a 1v1 breakaway inside 280px of goal, and the goalkeeper is the closest defending player to intercept.
func _should_goalkeeper_rush() -> bool:
	if pitch_boundary == null or ball == null or player == null:
		return false
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false

	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(player.team)
	var ball_pos: Vector2 = ball.global_position
	var dist_ball_to_goal: float = ball_pos.distance_to(goal_centre)

	# Condition 1: Loose ball in or near penalty box (~320px depth from goal, ~250px half-height)
	var is_loose_near_box: bool = ball.possessor == null and absf(ball_pos.x - goal_centre.x) < 320.0 and absf(ball_pos.y - goal_centre.y) < 250.0

	# Condition 2: 1v1 breakaway inside 280px with low defensive pressure on the carrier
	var is_1v1_breakaway: bool = false
	if ball.possessor != null and ball.possessor.team != player.team and dist_ball_to_goal < 280.0:
		var pressure_on_carrier: float = world.get_opponent_density(ball_pos, 110.0, ball.possessor.team)
		if pressure_on_carrier < 0.30:
			is_1v1_breakaway = true

	if not is_loose_near_box and not is_1v1_breakaway:
		return false

	# Intercept point calculation
	var gk_top_speed: float = player.get_current_top_speed() * 1.35
	var intercept_pt: Vector2 = UtilityMath.calculate_intercept_point(
		player.global_position,
		gk_top_speed,
		ball_pos,
		ball.velocity,
		ball.pitch_friction * Pseudo3DBall.FRICTION_SCALE,
		INTERCEPT_REACTION_TIME
	)

	# Don't rush outside the defensive third (> 380px of goal)
	if intercept_pt.distance_to(goal_centre) > 380.0:
		return false

	var gk_time: float = player.global_position.distance_to(intercept_pt) / maxf(gk_top_speed, 1.0)

	# Check if another defending teammate can intercept faster
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] != player.team:
			continue
		var other_speed: float = other.get_current_top_speed()
		var other_time: float = world.player_positions[i].distance_to(intercept_pt) / maxf(other_speed, 1.0)
		if other_time < gk_time * 0.85:
			return false

	_cached_intercept = intercept_pt
	return true


## Turns the contextual vector into an action name. Returned names are
## deliberately tactical rather than mechanical — the steering layer decides how
## to execute them. Allocation-free hot path.
func evaluate_tactical_action(defenders_nearby: Array[Node2D] = []) -> StringName:
	if is_goalkeeper:
		if _should_goalkeeper_rush():
			return &"GoalieRush"
		return &"GoaliePatrol"

	var ctx: UtilityContext = _build_context(defenders_nearby)

	var is_throw_in_taker: bool = player != null and player.state_factory != null and player.state_factory.current_state_name == &"ThrowIn"
	if is_throw_in_taker:
		if ctx.open_teammate_exists:
			return &"Pass"
		else:
			return &"FindSpace"

	# --- Utility scoring (Zero dynamic allocations) ---
	# Noise is seeded from the player's instance id so it is deterministic per
	# player but different between players; the match tick varies it per tick.
	var noise_seed: int = player.get_instance_id() + GameManager.get_match_tick()
	_rng.seed = noise_seed

	var best_action: StringName = &"MaintainFormation"
	var s_maintain: float = clampf(_score_maintain_formation(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	var best_score: float = s_maintain

	## -1.0 = never evaluated this tick (the composure/pressure panic gate
	## below did not open) — kept distinct from a real 0.0 score for the
	## debug_log_action_scores printout.
	var s_panic: float = -1.0
	if ctx.pressure > 0.85 and ctx.eff_composure < 0.45:
		s_panic = clampf(0.85 + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
		if s_panic > best_score:
			best_score = s_panic
			best_action = &"PanicClear"

	var s_pass: float = clampf(_score_pass(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_pass > best_score:
		best_score = s_pass
		best_action = &"Pass"

	var s_chase: float = clampf(_score_chase(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_chase > best_score:
		best_score = s_chase
		best_action = &"ChaseBall"

	var s_space: float = clampf(_score_find_space(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_space > best_score:
		best_score = s_space
		best_action = &"FindSpace"

	var s_dribble: float = clampf(_score_dribble(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_dribble > best_score:
		best_score = s_dribble
		best_action = &"AttemptDribble"

	var s_shoot: float = clampf(_score_shoot(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_shoot > best_score:
		best_score = s_shoot
		best_action = &"AttemptShoot"

	# Fallback utility floor: if the ball carrier has zero viable offensive options,
	# force a desperation clearance rather than freezing in possession.
	if ctx.is_possessor:
		var max_offensive: float = maxf(s_pass, maxf(s_dribble, s_shoot))
		if max_offensive <= 0.05:
			best_action = &"PanicClear"

		# La Pausa: distinct from the floor above (which catches "nothing is any
		# good"). This catches "something is fine but MaintainFormation still
		# won and I'm dawdling on the ball regardless" — a genuine standstill,
		# not a scoring edge case. Uses MatchWorldModel's possession watchdog
		# timer rather than brain-local state, since brains run on a 15-frame
		# stagger (ai-architect.md) and would miss ticks trying to self-time.
		elif best_action == &"MaintainFormation" and not ctx.open_teammate_exists \
				and MatchWorldModel.instance != null \
				and MatchWorldModel.instance.get_active_possession_hold_seconds() > LA_PAUSA_HOLD_SECONDS:
			best_action = &"AttemptDribble" if s_dribble > LA_PAUSA_MIN_DRIBBLE_SCORE else &"PanicClear"

	# Opt-in crowding/space-creation diagnostics — see MatchWorldModel.
	# debug_spacing_diagnostics. No-op (single bool check) when disabled.
	if player != null and MatchWorldModel.instance != null and MatchWorldModel.instance.debug_spacing_diagnostics:
		MatchWorldModel.instance.record_decision(player.team, role, best_action, ctx.is_possessor, ctx.open_teammate_exists)

	if debug_log_action_scores or _trace_next_decision:
		# Steering-layer fields (velocity/movement_intent/foot-range) alongside
		# the decision-layer scores, so a single line answers both "what did
		# it decide" and "what is it actually doing about it" — movement_intent
		# is the value _steer_for_action() wrote on the PREVIOUS tick (this
		# print runs before this tick's steering call). _trace_this_tick is
		# left armed (not cleared here) so _steer_for_action(), called right
		# after this returns within the same physics tick, can print the
		# FRESH seek_target/force breakdown for the decision made just above
		# and clear it there — giving one matched pair of lines per traced
		# tick instead of one stale-by-a-tick line.
		var dist_to_ball_now: float = player.global_position.distance_to(ball.global_position) if ball != null else -1.0
		var in_foot_range: bool = player.get_ball_in_foot_range() != null
		print("[ActionScorer] %s picks %s  maintain=%.3f panic=%s pass=%.3f chase=%.3f space=%.3f dribble=%.3f shoot=%.3f  possessor=%s team_has_ball=%s chase_legal=%s open_teammate=%s dist_to_ball=%.1f  pos=%s vel_len=%.1f intent=%s intent_len=%.2f wants_sprint=%s dist_to_ball_now=%.1f in_foot_range=%s pass_target=%s" % [
			player.name, best_action,
			s_maintain, ("%.3f" % s_panic) if s_panic >= 0.0 else "n/a",
			s_pass, s_chase, s_space, s_dribble, s_shoot,
			ctx.is_possessor, ctx.team_has_ball, ctx.chase_is_legal, ctx.open_teammate_exists,
			ctx.dist_to_ball,
			player.global_position, player.velocity.length(), player.movement_intent, player.movement_intent.length(),
			player.wants_sprint, dist_to_ball_now, in_foot_range,
			_cached_pass_target.name if is_instance_valid(_cached_pass_target) else "null"])
		_trace_this_tick = true

	return best_action


## Minimum PassUtilityScorer.score_pass() total a candidate must clear to be
## considered pass-worthy at all — keeps a tightly marked, poorly angled, or
## wildly long ball from ever outscoring "nothing open" and getting forced.
const MIN_PASS_SCORE: float = 0.38

## Isolation reward applied on top of PassUtilityScorer's own pressure_utility
## dimension (see score_pass()'s RECEIVER_OPEN_RADIUS=160px weighting) — that
## dimension already favours an open receiver, but only mildly (WEIGHT_PRESSURE
## share of the total). This is a much stronger, super-linear bonus layered on
## at the consumption site in _find_best_pass_target() so a genuinely isolated
## teammate can decisively win over dribbling/other actions, without touching
## PassUtilityScorer's own documented weighted formula (that file is pure and
## takes no MatchWorldModel reads of its own — see its class doc). Uses the
## squared-distance ramp for a convex reward curve (isolation pays off faster
## as an opponent gets further away); computed from min_opp_dist, which
## _find_best_pass_target() already has from world.nearest_opponent_dist_to(),
## so no new spatial query or WorldModel accessor is needed for this.
const ISOLATION_RAD_SQ: float = 57600.0  # 240px * 240px
## min_opp_dist beyond this earns a flat bonus on top of the ramp above —
## rewards a receiver with real running room, not just "technically open."
const ISOLATION_BONUS_DIST: float = 220.0
const ISOLATION_BONUS_SCORE: float = 0.30

## Master switch for the mood-driven risk-aversion shift on pass-target
## scoring — see _find_best_pass_target(). Flip to false to fall back to raw
## passer_pressure with no mood influence, without touching the scoring math.
const MOOD_RISK_BIAS_ENABLED: bool = true
## Added to passer_pressure while SLUMP (panicked) — pushes weight toward the
## safe/open receiver and away from the ambitious forward ball.
const SLUMP_RISK_AVERSION: float = 0.35
## Subtracted from passer_pressure while STREAK (confident) — negative pressure
## floors at 0.0 via effective_pressure's clamp, so this only ever reduces the
## safety shift, never inverts it into extra ambition beyond "no shift at all".
const STREAK_RISK_AVERSION: float = -0.20

## Set true (e.g. from the debugger) to print the scored candidate list and
## the winner every time _find_best_pass_target() runs on this player.
var debug_log_pass_scores: bool = false

## Set true (e.g. via the Remote scene tree Inspector while the game is
## running, or from the debugger) to print every evaluate_tactical_action()
## action score plus the winner, every decision tick, for this player. Cheap
## to toggle at runtime — no rebuild needed to point it at whichever player
## is exhibiting a bad decision.
var debug_log_action_scores: bool = false

## One-shot version of the above: armed externally (MatchWorldModel's stall
## watchdog calls trace_next_decision() on whichever player is closest to a
## ball that has sat unpossessed and stationary for a couple of seconds) to
## force exactly one [ActionScorer] printout on this player's next decision
## tick, then auto-clears. Kept separate from debug_log_action_scores so an
## automatic watchdog trigger never turns into permanent per-tick spam.
var _trace_next_decision: bool = false

## Set (not cleared) by evaluate_tactical_action() alongside the
## [ActionScorer] print above for exactly the same tick, so
## _steer_for_action() — called right after, same physics tick — knows to
## print its own [Steer] line (seek_target/force breakdown) for that same
## decision, then clears both this and _trace_next_decision itself.
var _trace_this_tick: bool = false

func trace_next_decision() -> void:
	_trace_next_decision = true

## Public wrapper for set pieces: a CPU-controlled taker has no run-up during
## which the brain can steer facing_direction toward a real target the way
## open play does, so SetPieceCoordinator resolves one directly through this
## before forcing the taker into CHARGE_KICK. Same scoring, no behavior change.
func find_pass_target_for_set_piece() -> HeavyPlayerController:
	return _find_best_pass_target(0.0, true)

## Scores every same-team, non-GK, non-self teammate on four dimensions —
## distance, passer facing angle, receiver pressure, and forward advancement —
## via PassUtilityScorer, rejecting any candidate whose passing lane an
## opponent is standing in. Returns null if nothing clears MIN_PASS_SCORE.
##
## passer_pressure: this player's own UtilityContext.pressure for the current
## tick, threaded through so PassUtilityScorer can favour the safe/open outlet
## over the ambitious forward ball when the passer is under pressure.
##
## allow_backward_pass: bypasses the low-composure backward-pass veto below.
## Kickoff (and any other restart where IFAB rules confine every teammate to
## the passer's own half) leaves a low-composure taker with zero forward
## candidates by construction, so find_pass_target_for_set_piece() sets this
## true rather than let the veto force a null target — see AGENTS_ERRATA.md.
func _find_best_pass_target(passer_pressure: float = 0.0, allow_backward_pass: bool = false) -> HeavyPlayerController:
	if ball == null or player == null:
		return null
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return null

	var attack_dir: Vector2 = _get_attack_direction()
	var ball_pos: Vector2 = ball.global_position

	# Recompute effective composure locally (same pattern as evaluate_tactical_action).
	var mood_node: MoodSystem = player.get_mood() if player != null else null
	var eff_composure: float = composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0)
	eff_composure = clampf(eff_composure, 0.0, 1.0)

	# Mood-driven risk aversion: folded into the same "passer_pressure" dial
	# PassUtilityScorer already uses to shift weight from advancement toward
	# the safe/open receiver (PRESSURE_SAFETY_SHIFT) — a panicked SLUMP player
	# reads as more pressured than they physically are and favours the safe
	# ball; a confident STREAK player reads as less pressured and is more
	# willing to attempt the progressive pass. MOOD_RISK_BIAS_ENABLED is the
	# single switch to turn this off without touching the scoring math itself.
	var mood_risk_aversion: float = 0.0
	if MOOD_RISK_BIAS_ENABLED and mood_node != null:
		match mood_node.current_tier:
			MoodSystem.Tier.SLUMP:
				mood_risk_aversion = SLUMP_RISK_AVERSION
			MoodSystem.Tier.STREAK:
				mood_risk_aversion = STREAK_RISK_AVERSION
			_:
				mood_risk_aversion = 0.0

	var trust_sys: TrustSystem = player.get_trust_system()
	# Loop-invariant: passer_pressure and mood_risk_aversion are both fixed for
	# this decision tick, so this is computed once rather than per candidate.
	var effective_pressure: float = clampf(passer_pressure + mood_risk_aversion, 0.0, 1.0)

	# Macro urgency modulation (architecture plan "Pass Utility Weight
	# Modulation Functions"): a team chasing the game (positive urgency) leans
	# harder into forward advancement and eases off the safety/pressure
	# weighting; a team protecting a lead (negative urgency) does the inverse,
	# favouring the safe backward/lateral recycle over the ambitious ball.
	# Loop-invariant like effective_pressure above — computed once per
	# decision tick, not per candidate.
	var world_urgency: float = world.team_urgency[player.team]
	var w_dist: float = player.role_config.w_dist if player.role_config != null else PassUtilityScorer.WEIGHT_DISTANCE
	var w_angle: float = player.role_config.w_angle if player.role_config != null else PassUtilityScorer.WEIGHT_ANGLE
	var base_w_press: float = player.role_config.w_press if player.role_config != null else PassUtilityScorer.WEIGHT_PRESSURE
	var base_w_adv: float = player.role_config.w_adv if player.role_config != null else PassUtilityScorer.WEIGHT_ADVANCEMENT
	var urgent_w_press: float = base_w_press * (1.0 - 0.45 * world_urgency)
	var urgent_w_adv: float = base_w_adv * (1.0 + 0.6 * world_urgency)

	# xT lookup is loop-invariant on everything except candidate_pos: pitch
	# size and the origin-centred offset UtilityMath.get_xt_value() expects
	# (see its doc comment) don't change per candidate this tick.
	var xt_pitch_size: Vector2 = pitch_boundary.pitch_size if pitch_boundary != null else Vector2(1728.0, 1024.0)
	var xt_origin: Vector2 = pitch_boundary.get_centre_spot() if pitch_boundary != null else Vector2.ZERO
	var xt_attack_sign: float = attack_dir.x

	var best_target: HeavyPlayerController = null
	var best_score: float = MIN_PASS_SCORE

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
		if forward_dot < -0.2 and eff_composure < 0.55 and not allow_backward_pass:
			continue

		# Lane check: an opponent standing in the passing lane makes the pass an
		# interception, however open the receiver looks.
		if not world.is_passing_lane_open(ball_pos, candidate_pos, player.team, PASS_LANE_CLEARANCE):
			continue

		# Openness, straight off the world model — no second roster walk.
		var min_opp_dist: float = world.nearest_opponent_dist_to(candidate_pos, player.team)
		var distance: float = ball_pos.distance_to(candidate_pos)
		# A restart taker's facing_direction is leftover from before the
		# whistle (whatever it last was while moving pre-freeze) — it does not
		# represent a committed body orientation the way it does in open play,
		# so scoring the angle dimension against it would unfairly punish
		# exactly the backward candidates allow_backward_pass exists to
		# unlock. Treat a restart taker as equally "facing" every candidate.
		var facing_dot: float = 1.0 if allow_backward_pass else player.get_facing_dot(candidate_pos)
		var xt_value: float = UtilityMath.get_xt_value(candidate_pos - xt_origin, xt_pitch_size, xt_attack_sign)

		# Hot path: bare float, allocates nothing (see PassUtilityScorer docs).
		var score: float = PassUtilityScorer.score_pass(
			distance, facing_dot, forward_dot, min_opp_dist, effective_pressure,
			w_dist, w_angle, urgent_w_press, urgent_w_adv, xt_value)

		# Trust bias: how much this passer trusts THIS candidate as a receiver
		# nudges the already-computed utility score up or down. Neutral trust
		# (no history yet) is a 1.0x no-op — see TrustSystem.trust_multiplier().
		if trust_sys != null:
			score *= TrustSystem.trust_multiplier(trust_sys.get_trust(TrustSystem.player_key(candidate)))

		# Isolation reward: layered on top of the trust-adjusted score
		# rather than folded into PassUtilityScorer's own weighted total
		# (see ISOLATION_RAD_SQ doc comment above for why).
		var iso_dist_sq: float = min_opp_dist * min_opp_dist
		var u_free: float = clampf(iso_dist_sq / ISOLATION_RAD_SQ, 0.0, 1.75)
		score *= u_free
		if min_opp_dist > ISOLATION_BONUS_DIST:
			score += ISOLATION_BONUS_SCORE

		if debug_log_pass_scores:
			var breakdown: PassUtilityScorer.PassScoreBreakdown = PassUtilityScorer.score_pass_breakdown(
				distance, facing_dot, forward_dot, min_opp_dist, effective_pressure, candidate,
				w_dist, w_angle, urgent_w_press, urgent_w_adv, xt_value)
			# breakdown.total is pre-trust; `score` (post-multiplier) is what
			# actually decides best_target below, so print both.
			print("[PassScorer] %s -> %s  dist=%.2f angle=%.2f pressure=%.2f adv=%.2f xt=%.2f  raw=%.3f trust_adj=%.3f" % [
				player.name, candidate.name,
				breakdown.distance_utility, breakdown.angle_utility,
				breakdown.pressure_utility, breakdown.advancement_utility, xt_value,
				breakdown.total, score])

		if score > best_score:
			best_score = score
			best_target = candidate

	if debug_log_pass_scores and best_target != null:
		print("[PassScorer] %s picks %s  total=%.3f" % [player.name, best_target.name, best_score])

	_cached_pass_score = best_score if best_target != null else 0.0
	return best_target


## Returns true only if this player is the most appropriate chaser on the team.
## "Most appropriate" means: among all teammates, this player is one of the
## role's budgeted closest to the ball, AND within that role's max chase
## distance. This prevents all outfield players from simultaneously deciding
## to chase.
func _should_chase_ball() -> bool:
	if ball == null or player == null:
		return false
	# A possessor already has the ball — "chasing" it is a category error, not
	# a real option. Every sibling score function (_score_find_space,
	# _score_maintain_formation, _score_dribble, _score_shoot, _score_pass)
	# already excludes the possessor case; _score_chase()/_should_chase_ball()
	# never got the same guard. Since a possessor is by definition standing
	# right next to their own ball, _score_chase()'s proximity term scores
	# them very highly (routinely 0.7+), crowding out Pass/AttemptDribble —
	# see AGENTS_ERRATA.md (possessor-can-chase-own-ball).
	if ball.possessor == player:
		return false
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false

	var ball_pos: Vector2 = ball.global_position
	# Deliberately the RAW pitch rect here, not get_playable_rect() — that one
	# is inset by PITCH_TOUCHLINE/ENDLINE_SAFETY_MARGIN for STEERING clamps
	# (validate_chase_intent/clamp_to_playable_area), so its edge already sits
	# 35-45px inside the true touchline/end line. A throw-in ball rests
	# THROW_IN_INSET (24px) past the true touchline while waiting to be
	# collected; gating chase legality on the inset rect made that entire
	# legitimate restart zone permanently unreachable by every player's
	# _should_chase_ball(), freezing the match once a throw ever landed loose
	# there. See AGENTS_ERRATA.md (throw-in-ball-outside-chase-legality-rect).
	var out_of_play_rect: Rect2 = pitch_boundary.get_pitch_rect() if pitch_boundary != null \
			else Rect2(-800.0, -450.0, 1600.0, 900.0)
	if ball_pos.x < out_of_play_rect.position.x - CHASE_OUT_OF_BOUNDS_TOLERANCE \
			or ball_pos.x > out_of_play_rect.end.x + CHASE_OUT_OF_BOUNDS_TOLERANCE \
			or ball_pos.y < out_of_play_rect.position.y - CHASE_OUT_OF_BOUNDS_TOLERANCE \
			or ball_pos.y > out_of_play_rect.end.y + CHASE_OUT_OF_BOUNDS_TOLERANCE:
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
	var max_dist: float = (player.role_config.max_chase_distance
			if player != null and player.role_config != null
			else 380.0 if role == Role.OUTFIELD_ATTACKER
			else 320.0 if role == Role.OUTFIELD_MIDFIELDER
			else 260.0 if role == Role.OUTFIELD_DEFENDER
			else 0.0)

	# A genuinely loose ball (nobody controls it) is exempt from this absolute
	# range cap too, not just the anchor-relative clamp further down — see
	# bresenham-threat-shadowed-real-lane-check-match-wide / the loose-ball
	# freeze notes in AGENTS_ERRATA.md. The cap exists to stop a player being
	# pulled out of shape chasing a ball an OPPONENT is dictating from deep;
	# it has no such justification against a ball nobody owns. Without this,
	# a loose ball that comes to rest farther than EVERY player's max_dist
	# (not just outside their anchor budget) still freezes the whole team,
	# since this check runs before the ball.possessor == null bypass below
	# ever gets a chance to fire. The role-budget loop right after this still
	# applies, so only the single closest eligible player per role goes.
	var is_loose: bool = ball.possessor == null

	var my_dist_sq: float = player.global_position.distance_squared_to(ball_pos)
	if not is_loose and my_dist_sq > max_dist * max_dist:
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
		if world.player_positions[i].distance_squared_to(ball_pos) < my_dist_sq:
			closer_count += 1
		if closer_count >= budget:
			return false

	# A genuinely loose ball (nobody controls it) is exempt from the
	# anchor-relative clamp below too, for the same reason as the max_dist
	# bypass above: that clamp exists to stop shape discipline collapsing
	# while an opponent calmly dictates play from deep, not to leave an
	# uncontrolled ball unclaimed. Without this, a ball that comes to rest
	# outside every player's anchor budget (e.g. rolling into space after a
	# kickoff tap) has _should_chase_ball() return false for all 22 players
	# — none of the press triggers arm either, since they all key off a named
	# carrier — and the match freezes with nobody ever going to get it. The
	# role-budget loop above still applies, so this only lets the single
	# closest eligible player break anchor, not the whole team.
	if is_loose:
		return true

	# Before committing to the chase, check the budget: the ball must sit
	# within this role's max_chase_distance of its anchor, or the
	# chase is suppressed and the player holds shape instead. The
	# press-trigger exemption is applied inside clamp_chase_target(), so a
	# live trigger always passes through unchanged.
	var anchor_pos: Vector2
	if role == Role.OUTFIELD_DEFENDER:
		anchor_pos = Vector2(world.defensive_line_x[player.team], player.global_position.y)
	else:
		anchor_pos = formation_anchor

	var clamped: Vector2 = clamp_chase_target(ball_pos, anchor_pos, player, world)
	# If the clamped position is the same as ball_pos, the ball is within
	# budget — proceed. Otherwise suppress the chase.
	if clamped.distance_squared_to(ball_pos) > 1.0:
		return false

	return true


## 0.0-1.0 crowding score from opponents within PRESSURE_RADIUS.
## Uses MatchWorldModel spatial grid for O(1) allocation-free evaluation when available.
func calculate_pressure_index(defenders: Array[Node2D] = []) -> float:
	if player == null:
		return 0.0

	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null:
		return clampf(world.get_opponent_density(player.global_position, PRESSURE_RADIUS, player.team), 0.0, 1.0)

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
		return clamp_to_playable_area(formation_anchor)

	if is_goalkeeper:
		match current_action:
			&"GoalieDive":
				return _cached_intercept if _cached_intercept != Vector2.ZERO else _goalie_patrol_target()
			&"GoalieRush":
				return _cached_intercept if _cached_intercept != Vector2.ZERO else ball.global_position
			_:
				return _goalie_patrol_target()

	var target: Vector2
	match current_action:
		&"ChaseBall", &"PanicClear", &"AttemptDribble":
			# Prefer chasing the ball carrier rather than the raw ball position.
			# Carrier is whoever last touched the ball and is an opponent.
			var carrier: HeavyPlayerController = _get_ball_carrier()
			if carrier != null:
				target = carrier.global_position
			else:
				target = ball.global_position
		&"Pass":
			if _cached_pass_target != null and is_instance_valid(_cached_pass_target):
				target = _cached_pass_target.global_position + _cached_pass_target.velocity * 0.3
			else:
				target = ball.global_position
		&"AttemptShoot":
			target = ball.global_position if ball != null else formation_anchor
		_:
			target = _cached_space_target

	return clamp_to_playable_area(target)


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


## Coarse team-level phase consumed by FormationAnchorMath to shift off-ball
## anchors. TRANSITION briefly overrides IN_POSSESSION/OUT_OF_POSSESSION right
## after a turnover, before the team's shape has caught up with who actually
## has the ball — see _transition_timer, armed on every possession change.
func _current_team_phase() -> FormationAnchorMath.TeamPhase:
	if _transition_timer > 0.0:
		return FormationAnchorMath.TeamPhase.TRANSITION
	if _team_has_ball():
		return FormationAnchorMath.TeamPhase.IN_POSSESSION
	return FormationAnchorMath.TeamPhase.OUT_OF_POSSESSION


## Per-role balance between staying tight to whatever tactical point the
## caller hands to _evaluate_off_ball_target() (0.0) and drifting toward the
## most open nearby pocket of space (1.0). This is the single place role
## identity is expressed for off-ball positioning — defenders barely move off
## their tactical point, attackers are freer to drift into space. TUNE HERE.
## ROLE_SPACE_ALPHA is kept as a fallback for any player entity that does not
## yet have a role_config .tres assigned. New entities should always have one.
## Remove this constant once all HeavyPlayerController scenes are migrated.
const ROLE_SPACE_ALPHA: Dictionary = {
	Role.OUTFIELD_DEFENDER: 0.20,
	Role.OUTFIELD_MIDFIELDER: 0.40,
	Role.OUTFIELD_ATTACKER: 0.65,
}

## Fan of candidate offsets sampled around the anchor point handed to
## _evaluate_off_ball_target(), scaled per-role by ROLE_SPACE_ALPHA (a higher
## alpha searches a wider radius) so attackers explore meaningfully more space
## than defenders without a second tunable. Kept fixed and small — seven
## points, one of them the anchor itself — so the evaluation stays a bounded
## O(7) world-model reads per decision tick rather than growing with pitch size.
const OFF_BALL_CANDIDATE_OFFSETS: Array[Vector2] = [
	Vector2.ZERO,
	Vector2(70.0, 0.0), Vector2(-70.0, 0.0),
	Vector2(0.0, 70.0), Vector2(0.0, -70.0),
	Vector2(50.0, 50.0), Vector2(-50.0, -50.0),
]

## Distance at which a candidate's openness score is already saturated at
## 1.0 — matches the scale _find_channel_run_target() reads off
## nearest_opponent_dist_to() so the two space heuristics feel consistent.
const OFF_BALL_OPENNESS_RADIUS: float = 220.0
## Distance below which a teammate standing near a candidate counts against it.
const OFF_BALL_CROWD_RADIUS: float = 70.0
## Distance at which a candidate's anchor-proximity score has decayed to 0.0.
## Comfortably above the largest offset in OFF_BALL_CANDIDATE_OFFSETS (~92px
## at the widest role radius) so every candidate still gets a graded score
## rather than several tying at the floor.
const OFF_BALL_ANCHOR_NORM: float = 100.0


## Returns true if this player is in an attacking role (ST, LW, RW, AM).
func _is_attacking_role() -> bool:
	if role == Role.OUTFIELD_ATTACKER:
		return true
	if player != null and player.role_config != null:
		var rname: String = player.role_config.role_name
		if rname == "ST" or rname == "LW" or rname == "RW" or rname == "AM" or rname == "CF" or rname == "SS":
			return true
	var pdata: PlayerData = player.get_meta(&"player_data", null) as PlayerData if player != null else null
	if pdata != null and (pdata.position_role == "ST" or pdata.position_role == "LW" or pdata.position_role == "RW" or pdata.position_role == "AM" or pdata.position_role == "CF"):
		return true
	return false


## Off-ball target evaluation: given a tactical anchor point [anchor] — already
## resolved by the caller (a dynamic formation anchor, a defensive press point,
## whatever this role's positioning logic decided is "home" for this tick) —
## samples candidate points and scores them across forward advancement, defender
## separation, and passing lane openness from the ball carrier.
## Blends the best candidate with [anchor] via (1.0 - player.role_config.anchor_weight).
func _evaluate_off_ball_target(anchor: Vector2) -> Vector2:
	if player == null:
		return anchor
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return clamp_to_playable_area(anchor)

	var alpha: float
	if player != null and player.role_config != null:
		# anchor_weight: 1.0 = rigid, 0.0 = free roam — the INVERSE of roam alpha
		alpha = 1.0 - player.role_config.anchor_weight
	else:
		alpha = float(ROLE_SPACE_ALPHA.get(role, 0.35))

	var is_attacker: bool = _is_attacking_role()
	var in_possession: bool = _current_team_phase() == FormationAnchorMath.TeamPhase.IN_POSSESSION
	var attack_sign: float = _get_attack_sign()

	var opp_goal_centre: Vector2 = pitch_boundary.get_goal_centre(1 - player.team) if pitch_boundary != null else Vector2(attack_sign * 800.0, 0.0)
	var pitch_len: float = pitch_boundary.pitch_size.x if pitch_boundary != null else 1600.0

	var carrier_pos: Vector2 = ball.global_position if ball != null else anchor
	var carrier: HeavyPlayerController = _get_ball_carrier()
	if carrier != null:
		carrier_pos = carrier.global_position

	_off_ball_candidates.clear()
	_off_ball_candidates.append(anchor)

	if is_attacker and in_possession:
		# Forward channel candidates: gaps between opposing CB-FB pairs and half-spaces
		# 1. Forward depth penetration along attack axis
		for fwd_dist: float in [70.0, 140.0, 210.0, 280.0]:
			_off_ball_candidates.append(anchor + Vector2(attack_sign * fwd_dist, 0.0))

		# 2. Diagonal channel runs (cutting inside toward half-spaces or overlapping outside)
		var anchor_side: float = signf(anchor.y)
		if is_zero_approx(anchor_side):
			anchor_side = 1.0
		for fwd_dist: float in [80.0, 160.0, 240.0]:
			# Diagonal inside toward half-space / centre
			_off_ball_candidates.append(anchor + Vector2(attack_sign * fwd_dist, -anchor_side * 80.0))
			_off_ball_candidates.append(anchor + Vector2(attack_sign * fwd_dist, -anchor_side * 140.0))
			# Diagonal outside into wide channel
			_off_ball_candidates.append(anchor + Vector2(attack_sign * fwd_dist, anchor_side * 80.0))

		# 3. Canonical half-space and channel depth targets
		var fwd_depth_x: float = anchor.x + attack_sign * 150.0
		for channel_y: float in [-320.0, -160.0, 0.0, 160.0, 320.0]:
			_off_ball_candidates.append(Vector2(fwd_depth_x, channel_y))

		# 4. Gaps between opposing defenders
		var opp_def_team: int = 1 - player.team
		var opp_def_line_x: float = world.defensive_line_x[opp_def_team]
		_opp_y_coords.clear()
		for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
			if world.player_teams[i] == opp_def_team and is_instance_valid(world.player_nodes[i]):
				var opos: Vector2 = world.player_positions[i]
				if absf(opos.x - opp_def_line_x) < 180.0:
					_opp_y_coords.append(opos.y)
		_opp_y_coords.sort()
		if _opp_y_coords.size() >= 2:
			for k: int in range(_opp_y_coords.size() - 1):
				var gap_y: float = (_opp_y_coords[k] + _opp_y_coords[k + 1]) * 0.5
				_off_ball_candidates.append(Vector2(opp_def_line_x - attack_sign * 30.0, gap_y))
				_off_ball_candidates.append(Vector2(opp_def_line_x + attack_sign * 40.0, gap_y))
	else:
		# Standard candidate fan around anchor
		var radius_scale: float = lerpf(0.6, 1.3, alpha)
		for base_offset: Vector2 in OFF_BALL_CANDIDATE_OFFSETS:
			_off_ball_candidates.append(anchor + base_offset * radius_scale)

	var best_pos: Vector2 = anchor
	var best_score: float = -INF

	for raw_candidate: Vector2 in _off_ball_candidates:
		var candidate: Vector2 = clamp_to_playable_area(raw_candidate)

		# 1. Forward advancement toward opposition goal line
		var dist_to_goal: float = candidate.distance_to(opp_goal_centre)
		var fwd_adv: float = clampf(1.0 - (dist_to_goal / (pitch_len * 0.85)), 0.0, 1.0)
		var fwd_progress: float = clampf((candidate.x - anchor.x) * attack_sign / 220.0, -0.5, 1.0)
		var adv_score: float = clampf(fwd_adv * 0.65 + (fwd_progress + 0.5) * 0.5 * 0.35, 0.0, 1.0)

		# 2. Separation distance from nearest defender
		var min_opp_dist: float = world.nearest_opponent_dist_to(candidate, player.team)
		var sep_score: float = clampf(min_opp_dist / OFF_BALL_OPENNESS_RADIUS, 0.0, 1.0)

		# 3. Passing lane openness from ball carrier
		var lane_open: bool = world.is_passing_lane_open(carrier_pos, candidate, player.team, PASS_LANE_CLEARANCE)
		var min_lane_dist: float = world.get_passing_lane_min_distance(carrier_pos, candidate, player.team)
		var lane_score: float = 1.0 if lane_open else clampf(min_lane_dist / PASS_LANE_CLEARANCE, 0.0, 0.8)

		# 4. Teammate crowding penalty
		var teammate_penalty: float = world.get_teammate_density(candidate, OFF_BALL_CROWD_RADIUS, player.team, player_index)

		# 5. Composite space score
		var space_score: float
		if is_attacker and in_possession:
			space_score = adv_score * 0.35 + sep_score * 0.35 + lane_score * 0.30
			space_score = clampf(space_score - teammate_penalty * 0.35, 0.0, 1.0)
		else:
			space_score = clampf(sep_score - teammate_penalty * 0.30, 0.0, 1.0)

		# 6. Proximity to anchor
		var norm_dist: float = OFF_BALL_ANCHOR_NORM * (2.5 if is_attacker and in_possession else 1.0)
		var anchor_score: float = 1.0 - clampf(candidate.distance_to(anchor) / norm_dist, 0.0, 1.0)

		# 7. Blended evaluation
		var blended: float = lerpf(anchor_score, space_score, alpha)
		if blended > best_score:
			best_score = blended
			best_pos = candidate

	# Blend candidate target with formation anchor using alpha (1.0 - anchor_weight)
	var final_target: Vector2 = anchor.lerp(best_pos, alpha)
	final_target = clamp_chase_target(final_target, anchor, player, world)
	return clamp_to_playable_area(final_target)


const MAX_CHASE_DEFAULT: float = 250.0

## Clamps `desired` so it never exceeds the player's chase budget from
## `anchor`. Budget is read from role_config when assigned; falls back
## to MAX_CHASE_DEFAULT. Does NOT clamp when a press trigger is active,
## because a TRIGGER_PRESS player must be free to chase the ball carrier
## without a radius constraint.
func clamp_chase_target(
		desired: Vector2,
		anchor: Vector2,
		player: HeavyPlayerController,
		wm: MatchWorldModel
) -> Vector2:
	if wm.press_trigger_active and wm.press_trigger_carrier != null \
			and is_instance_valid(wm.press_trigger_carrier) and wm.press_trigger_carrier.team != player.team:
		return desired
	var budget: float = MAX_CHASE_DEFAULT
	if player.role_config != null:
		budget = player.role_config.max_chase_distance
	var offset: Vector2 = desired - anchor
	if offset.length_squared() > budget * budget:
		return anchor + offset.normalized() * budget
	return desired


## Returns the world-space position this player should move to when NOT chasing
## the ball. The result is role-specific and possession-aware:
##   - When team HAS ball: attackers run channels, mids hold a passing angle
##   - When team DOES NOT have ball: attackers drop off, mids track the ball
##     laterally, defenders mark the nearest threat or hold the line
## Every non-run-specific branch below routes through _evaluate_off_ball_target()
## so the final off-ball target is always nudged toward whichever nearby candidate
## best balances that role's anchor discipline against open space.
func _find_open_space_target() -> Vector2:
	if ball == null or player == null:
		return clamp_to_playable_area(formation_anchor)

	var ball_pos: Vector2 = ball.global_position
	var has_ball: bool = _team_has_ball()

	var dynamic_anchor: Vector2 = formation_anchor.lerp(ball_pos, formation_ball_weight)
	if pitch_boundary != null:
		dynamic_anchor = FormationAnchorMath.get_dynamic_anchor_position(
			role,
			_current_team_phase(),
			formation_anchor,
			ball_pos,
			formation_ball_weight,
			pitch_boundary.get_centre_spot(),
			pitch_boundary.pitch_size,
			_get_attack_sign(),
			MatchWorldModel.instance.team_urgency[player.team] if MatchWorldModel.instance != null else 0.0
		)
	dynamic_anchor = clamp_to_playable_area(dynamic_anchor)

	match role:

		Role.OUTFIELD_ATTACKER:
			if has_ball:
				# Find the best forward channel / penetration run target
				return _evaluate_off_ball_target(dynamic_anchor)
			else:
				# Defending: drop toward own half but maintain counter-attack readiness
				var drop_target: Vector2 = dynamic_anchor.lerp(ball_pos, 0.20)
				return _evaluate_off_ball_target(drop_target)

		Role.OUTFIELD_MIDFIELDER:
			if has_ball:
				if _is_attacking_role():
					return _evaluate_off_ball_target(dynamic_anchor)
				return _find_passing_triangle_position(ball_pos)
			else:
				var defend_pos: Vector2 = dynamic_anchor
				defend_pos.x = lerpf(defend_pos.x, ball_pos.x, formation_ball_weight)
				return _evaluate_off_ball_target(defend_pos)

		Role.OUTFIELD_DEFENDER:
			if has_ball:
				var safe_pos: Vector2 = dynamic_anchor
				if absf(formation_anchor.y) > 120.0:
					var is_rb: bool = formation_anchor.y > 0.0
					var is_lb: bool = formation_anchor.y < 0.0
					var opposite_advanced: bool = false
					var world: MatchWorldModel = MatchWorldModel.instance
					if world != null:
						for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
							if world.player_teams[i] == player.team and world.player_nodes[i] != player:
								var px: float = world.p_pos_x[i]
								var py: float = world.p_pos_y[i]
								var advanced_x: float = px * _get_attack_sign()
								if advanced_x > 0.0 and absf(py) > 180.0:
									if (is_lb and py > 0.0) or (is_rb and py < 0.0):
										opposite_advanced = true
										break
					if opposite_advanced:
						var clamped_y: float = clampf(safe_pos.y, -180.0, 180.0)
						safe_pos = Vector2(safe_pos.x, clamped_y)
						return clamp_to_playable_area(safe_pos)
					safe_pos = safe_pos.lerp(ball_pos, 0.08)
					return _evaluate_off_ball_target(safe_pos)
				else:
					safe_pos = safe_pos.lerp(ball_pos, 0.08)
					var target: Vector2 = _evaluate_off_ball_target(safe_pos)
					if pitch_boundary != null:
						var max_adv: float = pitch_boundary.get_centre_spot().x - 60.0 * _get_attack_sign()
						if _get_attack_sign() > 0.0:
							target.x = minf(target.x, max_adv)
						else:
							target.x = maxf(target.x, max_adv)
					return clamp_to_playable_area(target)
			else:
				var world: MatchWorldModel = MatchWorldModel.instance
				if current_duty == DefensiveDuty.COVER_SUPPORT:
					if world != null and is_instance_valid(world.press_trigger_carrier):
						var carrier_pos: Vector2 = world.press_trigger_carrier.global_position
						var opp_goal: Vector2 = pitch_boundary.get_goal_centre(player.team)
						var btg_axis: Vector2 = (opp_goal - carrier_pos).normalized()
						var sup_pos: Vector2 = carrier_pos + btg_axis * 50.0
						return clamp_to_playable_area(sup_pos)
				if current_duty == DefensiveDuty.COVER_SHADOW:
					if world != null and is_instance_valid(world.press_trigger_carrier):
						var cx: int = clampi(int((player.global_position.x + MatchWorldModel.TACTICAL_OFFSET_X) / MatchWorldModel.TACTICAL_CELL_W), 0, MatchWorldModel.TACTICAL_GRID_WIDTH - 1)
						var cy: int = clampi(int((player.global_position.y + MatchWorldModel.TACTICAL_OFFSET_Y) / MatchWorldModel.TACTICAL_CELL_H), 0, MatchWorldModel.TACTICAL_GRID_HEIGHT - 1)
						var best_threat: int = -1
						var best_cell: Vector2 = player.global_position
						for dy: int in range(-1, 2):
							for dx: int in range(-1, 2):
								var nx: int = cx + dx
								var ny: int = cy + dy
								if nx >= 0 and nx < MatchWorldModel.TACTICAL_GRID_WIDTH and ny >= 0 and ny < MatchWorldModel.TACTICAL_GRID_HEIGHT:
									var idx: int = ny * MatchWorldModel.TACTICAL_GRID_WIDTH + nx
									var threat: int = world.grid_away[idx] if player.team == 0 else world.grid_home[idx]
									if threat > best_threat:
										best_threat = threat
										best_cell = Vector2(float(nx) * MatchWorldModel.TACTICAL_CELL_W - MatchWorldModel.TACTICAL_OFFSET_X + MatchWorldModel.TACTICAL_CELL_W * 0.5, float(ny) * MatchWorldModel.TACTICAL_CELL_H - MatchWorldModel.TACTICAL_OFFSET_Y + MatchWorldModel.TACTICAL_CELL_H * 0.5)
						return clamp_to_playable_area(best_cell)
				
				var line_anchor: Vector2 = dynamic_anchor
				if world != null:
					line_anchor.x = lerpf(line_anchor.x, world.defensive_line_x[player.team], DEFENSIVE_LINE_DEPTH_WEIGHT)

				var threat: HeavyPlayerController = _find_nearest_threatening_opponent()
				if threat != null:
					var threat_pos: Vector2 = threat.global_position.lerp(line_anchor, 0.45)
					return clamp_to_playable_area(threat_pos)
				return _evaluate_off_ball_target(line_anchor)

		_:
			return clamp_to_playable_area(dynamic_anchor)


## Channel run target evaluation: leverages _evaluate_off_ball_target with the
## phase-shifted dynamic anchor to find purposeful forward channel penetration.
func _find_channel_run_target(ball_pos: Vector2) -> Vector2:
	if pitch_boundary == null or player == null:
		return clamp_to_playable_area(formation_anchor)
	var dynamic_anchor: Vector2 = formation_anchor.lerp(ball_pos, formation_ball_weight)
	if pitch_boundary != null:
		dynamic_anchor = FormationAnchorMath.get_dynamic_anchor_position(
			role,
			_current_team_phase(),
			formation_anchor,
			ball_pos,
			formation_ball_weight,
			pitch_boundary.get_centre_spot(),
			pitch_boundary.pitch_size,
			_get_attack_sign(),
			MatchWorldModel.instance.team_urgency[player.team] if MatchWorldModel.instance != null else 0.0
		)
	return _evaluate_off_ball_target(dynamic_anchor)


## Returns a position in a passing triangle: offset laterally and slightly
## behind the ball so the midfielder is always available for a short outlet.
func _find_passing_triangle_position(ball_pos: Vector2) -> Vector2:
	if player == null:
		return clamp_to_playable_area(formation_anchor)

	var anchor_side: float = signf(formation_anchor.y - ball_pos.y)
	if is_zero_approx(anchor_side):
		anchor_side = 1.0

	var offset_y: float = anchor_side * 140.0
	var offset_x: float = -_get_attack_sign() * 60.0

	var triangle_pos: Vector2 = ball_pos + Vector2(offset_x, offset_y)
	return clamp_to_playable_area(triangle_pos)


## Gate for _recompute_team_marking(): only an OUTFIELD_DEFENDER calls this,
## and only from _find_nearest_threatening_opponent(), which is itself only
## ever reached from inside evaluate_tactical_action()'s decision-tick gate
## (_resolve_defensive_duty() and _find_open_space_target(), both cached at
## the same tick — see the (_frame_counter + player_index) % current_cadence
## gate) — never from per-frame steering. That call chain is what satisfies
## ai-architect.md's "15-frame AI decision stagger" requirement here; this
## function adds its own per-team dedup on top so the whole team's assignment
## is recomputed roughly once per cadence window rather than once per
## defender (5-6x redundant work for an identical deterministic result).
func _maybe_recompute_team_marking() -> void:
	if player == null:
		return
	var tick: int = GameManager.get_match_tick()
	if tick - _marking_last_tick[player.team] < MARKING_REASSIGN_INTERVAL_TICKS:
		return
	_marking_last_tick[player.team] = tick
	_recompute_team_marking()


## Team-wide greedy bipartite marking pass for player.team's defenders against
## the opposing OUTFIELD_ATTACKERs. Writes _marking_assignment for every
## defender slot found; clears stale entries first so a defender who left the
## roster (red card — MatchWorldModel.mark_player_unavailable()) doesn't keep
## a stale target. See the class section header above for the algorithm
## shape and why it is greedy rather than optimal.
func _recompute_team_marking() -> void:
	if player == null or pitch_boundary == null:
		return
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return

	var my_team: int = player.team
	var opp_attack_sign: float = -_get_attack_sign()
	var pitch_size: Vector2 = pitch_boundary.pitch_size
	var xt_origin: Vector2 = pitch_boundary.get_centre_spot()
	var our_goal: Vector2 = pitch_boundary.get_goal_centre(my_team)
	# Cost normalizers so the dist_sq/goal_dist_sq terms (px^2, easily in the
	# tens of thousands) don't drown out the (1.0 - threat) term (0..1) before
	# the formula's own weights ever get applied — derived from pitch_size
	# rather than a fixed pixel constant so this stays correct if the pitch
	# rect ever changes. See MARKING cost formula below.
	var norm_dist_sq: float = maxf(pitch_size.x * pitch_size.x * 0.25, 1.0)
	var norm_goal_sq: float = maxf(pitch_size.x * pitch_size.x, 1.0)

	var defender_count: int = 0
	var attacker_count: int = 0
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		if defender_count >= MAX_MARKING_SLOTS and attacker_count >= MAX_MARKING_SLOTS:
			break
		var node: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(node):
			continue
		var brain := node.get_node_or_null("PlayerBrain") as PlayerBrain
		if brain == null:
			continue
		if world.player_teams[i] == my_team:
			if brain.role == Role.OUTFIELD_DEFENDER and defender_count < MAX_MARKING_SLOTS:
				_mark_defender_idx[defender_count] = i
				_mark_defender_used[defender_count] = 0
				defender_count += 1
		elif brain.role == Role.OUTFIELD_ATTACKER and attacker_count < MAX_MARKING_SLOTS:
			var pos: Vector2 = world.player_positions[i]
			_mark_attacker_idx[attacker_count] = i
			_mark_attacker_threat[attacker_count] = UtilityMath.get_xt_value(pos - xt_origin, pitch_size, opp_attack_sign)
			_mark_attacker_used[attacker_count] = 0
			attacker_count += 1

	# Clear this tick's defender slots up front — a defender_count that
	# shrank since the last pass (red card) must not leave a stale target
	# sitting in a world_index no longer visited below.
	for d: int in range(defender_count):
		_marking_assignment[_mark_defender_idx[d]] = NO_MARK_INDEX

	# Greedy: highest-threat unassigned attacker first, paired with its
	# lowest-cost unassigned defender, repeat. No sort needed — attacker_count
	# is tiny (<= 11), so a linear max-scan per step is simpler than sorting
	# and costs the same in the worst case.
	for _step: int in range(attacker_count):
		var pick_a: int = -1
		var pick_a_threat: float = -1.0
		for a: int in range(attacker_count):
			if _mark_attacker_used[a] != 0:
				continue
			if _mark_attacker_threat[a] > pick_a_threat:
				pick_a_threat = _mark_attacker_threat[a]
				pick_a = a
		if pick_a == -1:
			break
		_mark_attacker_used[pick_a] = 1

		var attacker_pos: Vector2 = world.player_positions[_mark_attacker_idx[pick_a]]
		var goal_dist_sq: float = attacker_pos.distance_squared_to(our_goal)
		# C = dist_sq * 0.5 + goal_dist_sq * 0.3 + (1.0 - threat) * 0.2, with
		# dist_sq/goal_dist_sq normalized to 0..1 first (see norm_*_sq above).
		var goal_term: float = clampf(goal_dist_sq / norm_goal_sq, 0.0, 1.0) * 0.3
		var threat_term: float = (1.0 - pick_a_threat) * 0.2

		var pick_d: int = -1
		var best_cost: float = INF
		for d: int in range(defender_count):
			if _mark_defender_used[d] != 0:
				continue
			var dist_sq: float = world.player_positions[_mark_defender_idx[d]].distance_squared_to(attacker_pos)
			var cost: float = clampf(dist_sq / norm_dist_sq, 0.0, 1.0) * 0.5 + goal_term + threat_term
			if cost < best_cost:
				best_cost = cost
				pick_d = d
		if pick_d == -1:
			continue
		_mark_defender_used[pick_d] = 1
		_marking_assignment[_mark_defender_idx[pick_d]] = _mark_attacker_idx[pick_a]


## Returns the nearest opponent who is in a threatening forward position
## (ahead of the defensive line, between the defender and goal). An
## OUTFIELD_DEFENDER prefers its _recompute_team_marking() assignment when one
## exists — coordinated across the whole back line rather than each defender
## picking independently — falling back to the old local nearest-distance
## pick only when no coordinated assignment is available yet (e.g. no
## opposing OUTFIELD_ATTACKER currently qualifies).
func _find_nearest_threatening_opponent() -> HeavyPlayerController:
	if player == null or pitch_boundary == null:
		return null
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return null

	if role == Role.OUTFIELD_DEFENDER:
		_maybe_recompute_team_marking()
		var assigned_idx: int = _marking_assignment[player_index] \
			if player_index >= 0 and player_index < _marking_assignment.size() else NO_MARK_INDEX
		if assigned_idx != NO_MARK_INDEX:
			var assigned_node: HeavyPlayerController = world.player_nodes[assigned_idx]
			if is_instance_valid(assigned_node):
				return assigned_node

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
			var toward_goal: bool = (other_pos.x < centre_x) if _get_attack_sign() > 0.0 else (other_pos.x > centre_x)
			if toward_goal and d < best_dist:
				best_dist = d
				best = other

	return best


## Assigns this tick's pressing duty for an OUTFIELD_DEFENDER while
## MatchWorldModel's pressing trigger is active — see DefensiveDuty. Every
## live defender on the team reads the same synchronized world-model snapshot
## this tick, so each one independently resolves "am I the closest defender
## to the carrier" to the same single answer without any central coordinator
## — the same pattern _should_chase_ball()'s role budget already relies on.
## Non-defenders, and defenders when no trigger concerns an opponent carrier,
## always resolve to NONE and are unaffected.
func _resolve_defensive_duty() -> DefensiveDuty:
	if role != Role.OUTFIELD_DEFENDER or player == null:
		return DefensiveDuty.NONE
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or not world.press_trigger_active:
		return DefensiveDuty.NONE
	if _team_has_ball():
		return DefensiveDuty.NONE
	var carrier: HeavyPlayerController = world.press_trigger_carrier
	if not is_instance_valid(carrier) or carrier.team == player.team:
		return DefensiveDuty.NONE

	var my_dist_sq: float = player.global_position.distance_squared_to(carrier.global_position)
	var closer_count: int = 0
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		if world.player_teams[i] != player.team:
			continue
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain == null or other_brain.role != Role.OUTFIELD_DEFENDER:
			continue
		var other_dist_sq: float = world.player_positions[i].distance_squared_to(carrier.global_position)
		if other_dist_sq < my_dist_sq or (is_equal_approx(other_dist_sq, my_dist_sq) and i < player_index):
			closer_count += 1

	var my_dist: float = sqrt(my_dist_sq)
	if closer_count == 0:
		return DefensiveDuty.TRIGGER_PRESS
	elif closer_count == 1 and my_dist <= COVER_SHADOW_RADIUS:
		return DefensiveDuty.COVER_SUPPORT
	elif closer_count == 2 and my_dist <= COVER_SHADOW_RADIUS:
		return DefensiveDuty.COVER_SHADOW
	# Too far from the pressing situation to usefully shadow a lane — label
	# only, the pre-existing hold-shape branch in _find_open_space_target()
	# already picks between marking a real threat and holding the line.
	return DefensiveDuty.MARKING if _find_nearest_threatening_opponent() != null else DefensiveDuty.RETREAT


## Cover-shadow target for a supporting defender: a point that cuts the
## passing lane between the pressing trigger's carrier and this defender's
## own nearest marked threat, rather than either standing off passively or
## piling onto the ball like the presser. Different defenders track different
## threats (_find_nearest_threatening_opponent() is per-player), so several
## COVER_SHADOW defenders naturally spread across different lanes instead of
## clumping on one point.
func _cover_shadow_target(carrier: HeavyPlayerController) -> Vector2:
	if player == null or not is_instance_valid(carrier):
		return formation_anchor

	var threat: HeavyPlayerController = _find_nearest_threatening_opponent()
	var lane_far_point: Vector2 = threat.global_position if threat != null else formation_anchor
	var shadow_pos: Vector2 = carrier.global_position.lerp(lane_far_point, COVER_SHADOW_LANE_RATIO)

	# Still respect the shared defensive line depth so cover-shadowing never
	# drags the back line badly out of shape — same blend
	# Role.OUTFIELD_DEFENDER's default hold-line target already applies.
	var world: MatchWorldModel = MatchWorldModel.instance
	if world != null:
		shadow_pos.x = lerpf(shadow_pos.x, world.defensive_line_x[player.team], DEFENSIVE_LINE_DEPTH_WEIGHT)

	return shadow_pos


## Repels this player from teammates within sep_radius so off-ball players
## don't stack on top of each other.
func _separation_force(sep_radius: float = 110.0) -> Vector2:
	if player == null:
		return Vector2.ZERO
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return Vector2.ZERO

	var force: Vector2 = Vector2.ZERO
	var nearby_teammates: Array[int] = world.get_nearby_teammates(player.global_position, sep_radius, player.team, player_index)
	for i: int in nearby_teammates:
		var offset: Vector2 = player.global_position - world.player_positions[i]
		var dist: float = offset.length()
		if dist > 0.0 and dist < sep_radius:
			# Cubic falloff: barely nudges teammates near the edge of the
			# radius, ramps up sharply only once genuinely crowded — softer
			# than the old linear (1 - dist/radius) at long range, stronger
			# at short range.
			var ratio: float = (sep_radius - dist) / sep_radius
			force += offset.normalized() * (ratio * ratio * ratio) * 0.85
	return force


## Lateral-only repulsion among same-team defenders — the "lateral spacing"
## half of the defensive-line controller (MatchWorldModel.defensive_line_x
## supplies the depth half). Projects onto the pitch-width (Y) axis only so it
## never fights the shared line's X pull in _find_open_space_target(): a
## defender pulled forward to mark a threat still gets pushed sideways off a
## teammate, but is never dragged back onto the line by this force alone.
## Cached once per decision tick (see _cached_defensive_lateral) — a full
## roster walk has no place in the per-frame steering path.
func _defensive_line_lateral_separation() -> Vector2:
	if role != Role.OUTFIELD_DEFENDER or player == null:
		return Vector2.ZERO
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return Vector2.ZERO

	var lateral_push: float = 0.0
	var nearby_defenders: Array[int] = world.get_nearby_teammates(player.global_position, DEFENSIVE_LINE_SEPARATION_RADIUS, player.team, player_index)
	for i: int in nearby_defenders:
		var other: HeavyPlayerController = world.player_nodes[i]
		if not is_instance_valid(other) or other == player:
			continue
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain == null or other_brain.role != Role.OUTFIELD_DEFENDER:
			continue
		var dy: float = player.global_position.y - world.player_positions[i].y
		var dist: float = absf(dy)
		if dist > 0.0 and dist < DEFENSIVE_LINE_SEPARATION_RADIUS:
			lateral_push += signf(dy) * (1.0 - dist / DEFENSIVE_LINE_SEPARATION_RADIUS)

	return Vector2(0.0, lateral_push)


func _get_ball_carrier() -> HeavyPlayerController:
	if ball == null:
		return null
	var toucher: HeavyPlayerController = ball.last_touched_by
	if toucher != null and toucher.team != player.team:
		return toucher
	return null


## CPU-only reflex: is this the moment a ChaseBall-committed defender should
## commit to a tackle lunge, rather than just continuing to close down?
## Mirrors wants_sprint's pattern — a per-frame reflex set in
## _steer_for_action(), not a decision-tick-gated tactical choice. Reuses
## ChaseBall's own legality/scoring gate as the "worth closing down" question
## and asks a narrower, TackleState-mirroring "worth committing" one on top:
## the ball must be live and held by an OPPONENT (never a teammate, never a
## loose ball — DribbleState already handles picking up a loose one), close
## enough for the lunge to plausibly connect, and already faced well enough
## that TackleState's own MIN_FACING_DOT re-check at the moment of contact
## would not immediately call it a foul anyway. See AGENTS_ERRATA.md
## (cpu-players-never-gated-into-tackle-state).
func _should_attempt_tackle() -> bool:
	if current_action != &"ChaseBall":
		return false
	if _tackle_cooldown > 0.0:
		return false
	if ball.is_airborne():
		return false

	var holder: HeavyPlayerController = ball.possessor as HeavyPlayerController
	if holder == null or holder.team == player.team:
		return false

	if player.global_position.distance_squared_to(ball.global_position) \
			> TACKLE_ATTEMPT_RANGE * TACKLE_ATTEMPT_RANGE:
		return false

	if player.get_facing_dot(ball.global_position) < TackleState.MIN_FACING_DOT:
		return false

	return true


## 8-way probe directions for AttemptDribble's open-space scan (see the
## &"AttemptDribble" case below) — pre-allocated PackedVector2Array so the
## per-frame scan never constructs a Vector2 array. Same 8-way convention as
## the course spec's digital aiming (docs/course_implementation_specification.md
## Section 2), reused here for "which way should I run with the ball" instead
## of aim input.
const DRIBBLE_PROBES: PackedVector2Array = [
	Vector2(1, 0), Vector2(0.707, 0.707), Vector2(0, 1), Vector2(-0.707, 0.707),
	Vector2(-1, 0), Vector2(-0.707, -0.707), Vector2(0, -1), Vector2(0.707, -0.707),
]
## How far ahead (world-px) each dribble probe samples for opponent proximity.
const DRIBBLE_PROBE_DIST: float = 70.0
## Weight on a probe's alignment with the attacking direction — dominant term,
## so "run at goal" always wins over "run into the emptiest corner."
const DRIBBLE_FORWARD_WEIGHT: float = 0.40
## Weight on a probe's clearance from the nearest opponent, scaled so a fully
## open ~300px probe (world_to_cell's 160px cells make that a realistic local
## max) contributes roughly the same order of magnitude as the forward term
## above rather than swamping it.
const DRIBBLE_SPACE_WEIGHT: float = 0.0008

## Blends three forces into the final movement_intent: a seek toward the
## current action's target, separation from teammates (off-ball only, so
## chasers aren't pushed off the intercept line), and a gentle formation
## spring when far from the anchor.
func _steer_for_action(delta: float) -> Vector2:
	if is_goalkeeper:
		return _steer_goalkeeper()

	# Transition detection: current_action only ever changes at a decision
	# tick, a mid-slice abort, or the exec blocks just below flipping back to
	# MaintainFormation — never inside this same check. Catching the change
	# here, before anything this frame reacts to the new action, means
	# _blend_from_intent is always last frame's real steering output, not a
	# value already contaminated by the new target.
	if current_action != _blend_prev_action:
		_blend_from_intent = player.movement_intent
		_blend_timer = INTENT_BLEND_DURATION
		_blend_prev_action = current_action
	elif _blend_timer > 0.0:
		_blend_timer = maxf(_blend_timer - delta, 0.0)

	# --- Tackle reflex ---
	# Recomputed every frame like wants_sprint below, not gated to the
	# decision-tick cadence. Always false for a human — PlayerBrain never
	# runs for one, see _physics_process()'s is_user_controlled bail-out — so
	# this can never fight a human's own action_tackle input.
	player.wants_tackle = _should_attempt_tackle()
	if player.wants_tackle:
		_tackle_cooldown = TACKLE_ATTEMPT_COOLDOWN

	# --- Pass execution ---
	var is_throw_in_taker: bool = player != null and player.state_factory != null and player.state_factory.current_state_name == &"ThrowIn"
	if current_action == &"Pass" and _cached_pass_target != null and is_instance_valid(_cached_pass_target) and not is_throw_in_taker:
		if player.global_position.distance_to(ball.global_position) < 80.0 and player.get_ball_in_foot_range() != null:
			var lead_pos: Vector2 = _cached_pass_target.global_position + _cached_pass_target.velocity * 0.3
			var aim: Vector2 = (lead_pos - ball.global_position).normalized()
			ball.apply_kick(aim * 260.0, 0.0, player)

			# Register this pass with the passer's TrustSystem before the
			# target reference is cleared below — DribbleState resolves this
			# into a trust gain (receiver controls it) or loss (an opponent
			# cuts it out) once the ball's next possession change is observed.
			var trust_sys: TrustSystem = player.get_trust_system()
			if trust_sys != null:
				trust_sys.register_pass(TrustSystem.player_key(_cached_pass_target))

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
		&"AttemptDribble":
			# Score all 8 probe directions on forward alignment + local
			# opponent clearance, rather than committing to a single fixed
			# attack_dir/goal-lerp target — lets the carrier bend the run
			# around a defender standing directly ahead instead of dribbling
			# straight into them. Falls back to attack_dir itself if no probe
			# beats it (e.g. surrounded on all sides).
			var world_probe: MatchWorldModel = MatchWorldModel.instance
			# Prefer the true bearing to the opponent's goal mouth over the flat
			# attack_dir (X-only) so a wide player's run still converges toward
			# goal instead of just marching straight downfield.
			var forward_ref: Vector2 = _get_attack_direction()
			if pitch_boundary != null:
				var opp_goal: Vector2 = pitch_boundary.get_goal_centre(1 - player.team)
				var to_goal: Vector2 = opp_goal - player.global_position
				if to_goal.length_squared() > 0.0001:
					forward_ref = to_goal.normalized()
			var best_probe_dir: Vector2 = forward_ref
			var best_probe_score: float = -INF
			if world_probe != null:
				for i: int in range(DRIBBLE_PROBES.size()):
					var probe_dir: Vector2 = DRIBBLE_PROBES[i]
					var probe_pos: Vector2 = player.global_position + probe_dir * DRIBBLE_PROBE_DIST
					var probe_score: float = probe_dir.dot(forward_ref) * DRIBBLE_FORWARD_WEIGHT \
						+ world_probe.nearest_opponent_dist_to(probe_pos, player.team) * DRIBBLE_SPACE_WEIGHT
					if probe_score > best_probe_score:
						best_probe_score = probe_score
						best_probe_dir = probe_dir
			seek_target = player.global_position + best_probe_dir * DRIBBLE_PROBE_DIST
		_:
			seek_target = _cached_space_target

	# ChaseBall/PanicClear/AttemptShoot all seek the ball's own position and
	# must physically close on it to trigger foot-sensor pickup or a kick —
	# unlike settling into a stationary FORMATION anchor or PASS position,
	# "arrived" here means touching the ball, not merely being nearby. The
	# generic arrival cushion below (tuned for the former) zeroes
	# movement_intent the instant distance drops under ARRIVE_RADIUS (24px),
	# which can permanently strand a player who correctly chose to chase but
	# is still meaningfully short of the ball — see AGENTS_ERRATA.md
	# (arrive-radius-strands-correct-chase-decision).
	var must_reach_ball: bool = current_action == &"ChaseBall" \
			or current_action == &"PanicClear" or current_action == &"AttemptShoot"

	# validate_chase_intent()'s safety-margin inset rect exists to keep
	# ordinary formation/space/pass targets off the touchline, but a ball a
	# player was just legally cleared to chase (_should_chase_ball()'s own,
	# more permissive out-of-play check) can legitimately sit past that inset
	# — e.g. a throw-in resting THROW_IN_INSET past the true touchline.
	# Clamping a must-reach-ball target to the inset rect would strand the
	# chaser short of a ball it was correctly sent to collect. See
	# AGENTS_ERRATA.md (throw-in-ball-outside-chase-legality-rect).
	if not must_reach_ball:
		seek_target = validate_chase_intent(seek_target)

	# --- Three-force blend ---
	var offset: Vector2 = seek_target - player.global_position
	var distance: float = offset.length()

	if distance <= ARRIVE_RADIUS and not must_reach_ball:
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

	# 5. Defensive-line lateral spacing — same-role repulsion projected onto
	# the pitch-width (Y) axis only, so the back line spreads sideways without
	# fighting the shared depth line pulled into _cached_space_target above.
	# Off-ball only, same guard as separation, and read from the decision-tick
	# cache rather than recomputed here.
	var line_lateral_force: Vector2 = Vector2.ZERO
	if role == Role.OUTFIELD_DEFENDER and current_action != &"ChaseBall" and current_action != &"PanicClear":
		line_lateral_force = _cached_defensive_lateral * DEFENSIVE_LINE_SEPARATION_WEIGHT

	# Sprint is expressed as intent, not the resolved is_sprinting — the
	# controller alone decides whether stamina actually allows it.
	player.wants_sprint = current_action == &"ChaseBall" and distance > CHASE_RADIUS * 0.5
	var sacchi_force: Vector2 = Vector2.ZERO
	# Off-ball only, same guard as sep_force/line_lateral_force above (and for
	# the same reason): this is an ambient team-shape nudge, and it can reach
	# its full clamped magnitude (1.0) at just 200px of excess team spread —
	# routine during any transition or counter-attack, not a rare edge case.
	# Summed unguarded into a ChaseBall/PanicClear/AttemptShoot seek force
	# (themselves often well under 1.0 — deflection alone maxes at 1.0 only
	# at long range) before the final .limit_length(1.0) clamp, a maxed-out
	# sacchi_force can all but cancel a correct, decisive chase — see
	# AGENTS_ERRATA.md (sacchi-force-cancels-urgent-ball-actions).
	var applies_to_ball_actions: bool = current_action != &"ChaseBall" \
			and current_action != &"PanicClear" and current_action != &"AttemptShoot"
	if applies_to_ball_actions and (role == Role.OUTFIELD_DEFENDER or role == Role.OUTFIELD_MIDFIELDER or role == Role.OUTFIELD_ATTACKER):
		var world: MatchWorldModel = MatchWorldModel.instance
		if world != null:
			var com_x: float = world.team_com_x[player.team]
			var att_x: float = world.team_att_x[player.team]
			var def_x: float = world.team_def_x[player.team]
			var L_team: float = absf(att_x - def_x)
			if L_team > 340.0:
				var K_sacchi: float = 0.0025
				var p_x: float = player.global_position.x
				var f_mag: float = -K_sacchi * ((L_team - 340.0) * (L_team - 340.0)) * signf(p_x - com_x)
				# 0.25 scale for 10px stretch, limit max to 1.0
				f_mag = clampf(f_mag / 100.0, -1.0, 1.0)
				sacchi_force = Vector2(f_mag, 0.0)

	var raw_intent: Vector2 = (seek_force + sep_force + spring_force + assist_force + line_lateral_force + sacchi_force).limit_length(1.0)
	var blended_intent: Vector2 = _apply_intent_blend(raw_intent)

	if _trace_this_tick:
		print("[Steer] %s action=%s seek_target=%s offset=%s distance=%.1f deflection=%.2f  seek=%s sep=%s spring=%s assist=%s line_lat=%s sacchi=%s  raw_intent=%s(len=%.2f) blended=%s(len=%.2f)" % [
			player.name, current_action, seek_target, offset, distance, deflection,
			seek_force, sep_force, spring_force, assist_force, line_lateral_force, sacchi_force,
			raw_intent, raw_intent.length(), blended_intent, blended_intent.length()])
		_trace_this_tick = false
		_trace_next_decision = false

	return blended_intent


## Eases from _blend_from_intent toward [raw_intent] over INTENT_BLEND_DURATION
## whenever a transition is in progress (see the current_action check at the
## top of _steer_for_action()); a no-op once _blend_timer has run out. Blending
## the direction vector itself — rather than, say, capping angular speed — is
## what makes a near-reversal read as a deceleration through a slower diagonal
## rather than an instant flip: lerp() between two roughly opposite unit
## vectors passes through a near-zero magnitude at the midpoint before
## re-extending toward the new heading, and HeavyPlayerController's own
## turning-penalty curve (soccer-physics.md) does the rest.
func _apply_intent_blend(raw_intent: Vector2) -> Vector2:
	if _blend_timer <= 0.0:
		return raw_intent
	var t: float = 1.0 - (_blend_timer / INTENT_BLEND_DURATION)
	return _blend_from_intent.lerp(raw_intent, t)


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

	var attack_dir: Vector2 = _get_attack_direction()
	var lateral_offset: float = player.global_position.y - ball.global_position.y
	var assist_target: Vector2 = clamp_to_playable_area(ball.global_position + attack_dir * 120.0 + Vector2(0.0, lateral_offset))

	var to_assist: Vector2 = assist_target - player.global_position
	if to_assist.is_zero_approx():
		return Vector2.ZERO
	return to_assist.normalized() * 0.25


## Goal-line lock steering: patrol slides along Y between the posts, tracking
## the ball along a dynamic bisector arc off the goal line except during a committed dive or rush.
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

	if current_action == &"GoalieRush":
		player.wants_sprint = true
		var rush_target: Vector2 = _cached_intercept if _cached_intercept != Vector2.ZERO else ball.global_position
		rush_target = clamp_to_playable_area(rush_target)
		var rush_offset: Vector2 = rush_target - player.global_position
		if rush_offset.length() <= 15.0:
			return Vector2.ZERO
		return rush_offset.normalized()

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


## World-space patrol point: dynamic position along the bisector angle between
## the ball position and the two goalposts, clamped to a 40–90px arc off the goal line.
func _goalie_patrol_target() -> Vector2:
	if pitch_boundary == null or player == null or ball == null:
		return formation_anchor
	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(player.team)
	var half_mouth: float = pitch_boundary.goal_mouth_height * 0.5
	var ball_pos: Vector2 = ball.global_position

	var pitch_in_dir: float = 1.0 if player.team == GameManager.TEAM_A else -1.0
	var to_ball: Vector2 = ball_pos - goal_centre

	if to_ball.is_zero_approx() or to_ball.x * pitch_in_dir <= 0.0:
		return goal_centre + Vector2(pitch_in_dir * GOALIE_ARC_MIN_DIST, 0.0)

	var bisector_dir: Vector2 = to_ball.normalized()
	var dist_to_ball: float = to_ball.length()

	# Dynamic arc distance off the goal line: 40px when ball is far (>600px), up to 90px when close (<200px)
	var t_dist: float = clampf((dist_to_ball - 200.0) / 400.0, 0.0, 1.0)
	var arc_dist: float = clampf(lerpf(GOALIE_ARC_MAX_DIST, GOALIE_ARC_MIN_DIST, t_dist), GOALIE_ARC_MIN_DIST, GOALIE_ARC_MAX_DIST)

	var patrol_pos: Vector2 = goal_centre + bisector_dir * arc_dist

	# Constrain Y within the goal mouth height
	patrol_pos.y = clampf(patrol_pos.y, goal_centre.y - half_mouth, goal_centre.y + half_mouth)

	# Ensure X stays on the playing field side of the goal line
	if pitch_in_dir > 0.0:
		patrol_pos.x = clampf(patrol_pos.x, goal_centre.x + 35.0, goal_centre.x + 130.0)
	else:
		patrol_pos.x = clampf(patrol_pos.x, goal_centre.x - 130.0, goal_centre.x - 35.0)

	return patrol_pos


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


## Opponents near this player within PRESSURE_RADIUS, queried from MatchWorldModel's
## spatial grid rather than scanning the whole roster. Refills a member buffer rather
## than allocating — the returned Array is overwritten by the next call.
func _find_nearby_opponents() -> Array[Node2D]:
	_opponents_buffer.clear()
	if player == null:
		return _opponents_buffer
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return _opponents_buffer

	var nearby: Array[Node2D] = world.get_nearby_opponent_nodes(player.global_position, PRESSURE_RADIUS, player.team)
	_opponents_buffer.append_array(nearby)
	return _opponents_buffer
