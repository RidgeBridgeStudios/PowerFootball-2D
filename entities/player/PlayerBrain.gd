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

enum FreeKickActionType { SHORT_PASS, DIRECT_SHOT, CROSS, LONG_BALL }

var free_kick_action_type: FreeKickActionType = FreeKickActionType.SHORT_PASS
var free_kick_charge_ratio: float = 0.0
var free_kick_is_lob: bool = false
var free_kick_is_tap: bool = true
var free_kick_action_label: String = "PASS"
var free_kick_intent_active: bool = false

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
	var injury_severity: float       ## 0-1, HeavyPlayerController.injury_severity

@export var role: Role = Role.OUTFIELD_MIDFIELDER

## Radius inside which an opponent contributes to the pressure index.
const PRESSURE_RADIUS: float = 180.0
## Distance at which the brain commits to chasing the ball rather than holding shape.
const CHASE_RADIUS: float = 220.0

## Distance inside which a ChaseBall-committed defender's lunge has a
## realistic chance of reaching foot-sensor range (15px, HeavyPlayer.tscn)
## before TackleState's own WINDUP+WINDOW elapses.
## Calibration: widened 30 -> 42. At 30px a CPU defender had to be inside
## foot-sensor range (15px) plus barely a body width before it would even
## consider committing, so by the time the gate opened the carrier had
## normally already turned away — CPU sides contained without ever actually
## challenging. 42px is roughly one closing stride out, which is where a real
## challenge is launched from.
const TACKLE_ATTEMPT_RANGE: float = 42.0
## Minimum alignment between the defender's own movement intent and the
## direction to the carrier before a challenge is committed. Distinct from the
## facing check below: facing says the body is pointed at the ball, this says
## the defender is actually travelling into the challenge rather than being
## carried past it by momentum from somewhere else.
const TACKLE_INTENT_DOT: float = 0.55

## Minimum gap between CPU-initiated tackle attempts by the same brain.
## Raised to 3.0s to reflect professional restraint and avoid slide tackle spam.
const TACKLE_ATTEMPT_COOLDOWN: float = 3.0

## Additive bonus to _score_chase() while MatchWorldModel's pressing trigger
## detector has flagged a football-relevant reason to close down right now
## (a backward/square pass into pressure, the carrier facing their own goal,
## pinned on the touchline, or a heavy touch) and that trigger concerns the
## opponent currently on the ball. Small enough that a legitimately better
## option (a covering defender holding the line instead of diving in) can
## still outscore it — this nudges the chase/hold-shape balance, it does not
## override it.
## Calibration: 0.18 -> 0.15 so that this bonus plus
## DUTY_TRIGGER_PRESS_CHASE_BONUS sums to exactly the +0.45 commitment the
## named presser is meant to carry, while a nearby non-presser still only gets
## the smaller nudge.
const PRESS_TRIGGER_CHASE_BONUS: float = 0.15

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
const CHASE_OUT_OF_BOUNDS_TOLERANCE: float = 75.0

## "La Pausa" standstill-breaker: a possessor who has held the ball this long
## with no open teammate and would otherwise settle on MaintainFormation gets
## forced into AttemptDribble/PanicClear instead — see evaluate_tactical_action().
const LA_PAUSA_HOLD_SECONDS: float = 1.0
## Same "is this option worth anything at all" bar the existing max_offensive
## <= 0.05 floor below uses, reused here so AttemptDribble is only chosen over
## PanicClear when dribbling is genuinely viable, not just nonzero.
const LA_PAUSA_MIN_DRIBBLE_SCORE: float = 0.05

## Goalkeeper arc clamping distance off the goal line (in pixels). This is the
## close-range "narrow the angle" band used while the ball is inside/near the
## defending third — see GOALIE_SWEEPER_MAX_DIST for the separate, larger band
## used to roam the box and sweep behind an advanced back line.
const GOALIE_ARC_MIN_DIST: float = 40.0
const GOALIE_ARC_MAX_DIST: float = 90.0

## Sweeper-keeper roaming: when the ball is deep in the attacking half
## (dist_to_ball > GOALIE_SWEEPER_BALL_DIST) and there is no defensive
## emergency (that is _should_goalkeeper_rush()'s job), the keeper steps off
## the goal line to sit as an outlet behind the team's shared defensive line
## instead of parking in the 6-yard box. GOALIE_SWEEPER_MAX_DIST caps how far
## that can push — just shy of the 320px penalty-area depth
## (SetPieceCoordinator.PENALTY_AREA_DEPTH) — and GOALIE_SWEEPER_LINE_MARGIN
## keeps the keeper trailing behind the last defender rather than level with it.
const GOALIE_SWEEPER_BALL_DIST: float = 500.0
const GOALIE_SWEEPER_MAX_DIST: float = 280.0
const GOALIE_SWEEPER_LINE_MARGIN: float = 60.0

## How much closer to a loose ball played in behind the keeper must be than the
## nearest opposing runner before committing to sweep it up. A tie is not
## enough — losing this race leaves an empty net.
const SWEEPER_RUSH_MARGIN: float = 45.0
## How far from goal the keeper may sweep when the trigger is a through-ball in
## behind, as opposed to the 380px defensive-third cap that governs the loose-
## ball and 1v1 cases. Just past the penalty area, so the keeper can smother
## outside the box without ending up in midfield.
const SWEEPER_RUSH_MAX_DIST: float = 460.0

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

## --- Pass strike calibration -------------------------------------------------
## Seconds of receiver velocity the pass is aimed ahead of — the lead point
## PassUtilityScorer.LEAD_PASS_BONUS prices as a through-ball.
const PASS_LEAD_SECONDS: float = 0.3
## Overshoot factor on the closed-form launch speed. The exact solution
## v0 = sqrt(2 * d * a) arrives with precisely zero pace, which in practice
## means the ball dies a stride short of a receiver who is still moving. 1.18
## delivers it at roughly a third of launch speed — a driven ball that can be
## taken in stride rather than one the receiver has to stop and wait for.
const PASS_SPEED_OVERSHOOT: float = 1.18
## Floor and ceiling on the solved launch speed. The floor keeps a six-yard
## exchange from being a nudge the nearest opponent walks onto; the ceiling
## keeps a maximum-range ball inside the striking power of a ground pass.
## The ceiling is set from the ball's own roll model rather than picked by
## feel: at the tuned 206 px/s^2 ground deceleration a ball struck at 505 px/s
## rolls 505^2 / (2 * 206) = 620px before coming to rest, which is the top of
## the driven-pass range. The floor's 240 px/s correspondingly rolls ~140px, so
## even the shortest exchange is firm rather than a nudge an opponent walks on
## to. Retune the ceiling together with Pseudo3DBall.pitch_friction — the two
## numbers only mean anything relative to each other.
const PASS_SPEED_MIN: float = 240.0
const PASS_SPEED_MAX: float = 505.0
## Charge ratio reported to GameEvents.ball_struck for a CPU ground pass.
const PASS_CHARGE_RATIO: float = 0.4
## Pressure index at or above which the settle window is overridden and the
## carrier may release the pass immediately — a player being closed down does
## not get a beat to take a touch and look up.
const SETTLE_OVERRIDE_PRESSURE: float = 0.55

## --- Composure under crowding ------------------------------------------------
## Radius (px) and body count that together define "genuinely crowded". Two
## opponents inside CROWDING_RADIUS is a player being closed from both sides,
## which is where technique starts to fail — distinct from the smooth
## PRESSURE_RADIUS index, which counts a single distant opponent as pressure.
const CROWDING_RADIUS: float = 75.0
const CROWDING_BODY_COUNT: int = 2
## Maximum accuracy decay a fully crowded, zero-composure player suffers.
## Scaled by (1 - composure), so a composed player barely notices and a
## panicky one loses control of the ball's direction entirely.
const CROWDING_MAX_ACCURACY_DECAY: float = 1.0
## Radians of aim scatter a ground pass picks up at full crowding decay.
## Passing was previously pinpoint under any amount of pressure, which is a
## large part of why possession never actually broke down: a surrounded
## defender played exactly the same ball as an unmarked one in open space.
const PASS_CROWDING_SCATTER: float = 0.16


## 0.0-1.0 accuracy decay from being closed down by multiple opponents at once.
## Zero unless at least CROWDING_BODY_COUNT opponents are inside
## CROWDING_RADIUS; from there it scales with how far composure falls short of
## perfect. Spatial read routes through MatchWorldModel; allocates nothing.
func _crowding_accuracy_decay(eff_composure: float) -> float:
	if player == null:
		return 0.0
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return 0.0
	var crowd: int = world.count_nearby_opponents(player.global_position, CROWDING_RADIUS, player.team)
	if crowd < CROWDING_BODY_COUNT:
		return 0.0
	# Each body past the first two deepens it, saturating at four.
	var crowd_ratio: float = clampf(float(crowd - CROWDING_BODY_COUNT + 1) / 3.0, 0.0, 1.0)
	return CROWDING_MAX_ACCURACY_DECAY * crowd_ratio * (1.0 - clampf(eff_composure, 0.0, 1.0))


## Launch speed (px/s) that carries a ground pass `distance` px to its target
## with pace still on it, solved against the ball's own current deceleration:
##     v0 = sqrt(2 * d * a) * PASS_SPEED_OVERSHOOT
## Calibration note: every CPU pass previously left the foot at a flat
## 260 px/s. Against the tuned 206 px/s^2 pitch friction that ball stops after
## 164px — shorter than PassUtilityScorer.PREFERRED_DISTANCE (220px) and less
## than a third of MAX_USEFUL_DISTANCE (520px). So the scorer was selecting
## progressive balls the strike could not physically deliver: anything but the
## shortest exchange died in open grass and was collected by whoever was
## closest, which reads as aimless recycling. Solving the speed from the
## distance is what makes the retuned pass weights actually reachable, and it
## puts a driven ball (PASS_SPEED_MAX-adjacent) in the 480-620px band.
func _solve_pass_speed(distance: float) -> float:
	var decel: float = ball.get_ground_deceleration() if ball != null else 206.0
	var solved: float = sqrt(2.0 * maxf(distance, 0.0) * maxf(decel, 1.0)) * PASS_SPEED_OVERSHOOT
	return clampf(solved, PASS_SPEED_MIN, PASS_SPEED_MAX)

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

## Fixed-size opponent-position scratch handed to UtilityMath.calculate_xg()
## so the xG comparison behind SHOOT_OVERRIDE_XG_RATIO never allocates on a
## decision tick. Sized once in _ready() to one slot per opponent and refilled
## in place by _shot_xg_at(); a slot whose player is not live is written with
## OFF_PITCH_SENTINEL, which can never fall inside a shot triangle.
var _xg_opp_scratch: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	_xg_opp_scratch.resize(MatchWorldModel.TOTAL_PLAYERS / 2)
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


## False for a goalkeeper once the ball has already crossed behind their own goal line
## (in the net) — prevents "catching" a goal that has already scored.
## Always true for outfield players. Call this at the possession-assignment
## site (wherever ball.set_possessor() is invoked), never from the decision
## tick — carrying eligibility must be checked at the moment it matters.
func can_carry_ball() -> bool:
	if not is_goalkeeper or player == null or pitch_boundary == null or ball == null:
		return true
	var goal_x: float = pitch_boundary.get_goal_centre(player.team).x
	var pitch_in_dir: float = _get_attack_sign()
	var depth_from_line: float = (ball.global_position.x - goal_x) * pitch_in_dir
	return depth_from_line > -10.0


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

	if GameManager.current_phase == GameManager.MatchPhase.GOAL_SCORED:
		_steer_celebration(delta)
		return

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
			# GoaliePatrol / GoalieRush evaluated on decision tick; dive is coordinated by PitchScene on shot
			if player.state_factory == null or player.state_factory.current_state_name != PlayerState.GOALKEEPER_DIVE:
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


## Note: Goalkeeper dive reaction is event-driven and coordinated by PitchScene
## (_on_ball_struck_for_dive) via GoalkeeperDiveBrain whenever GameEvents.ball_struck
## fires on a real shot, avoiding redundant per-frame triggers.


## Returns +1.0 for Team A (+X attacking axis) or -1.0 for Team B (-X attacking axis),
## dynamically inverted when pitch ends are swapped (e.g. during 2nd half).
func _get_attack_sign() -> float:
	var base_sign: float = 1.0 if player != null and player.team == GameManager.TEAM_A else -1.0
	if pitch_boundary != null and pitch_boundary.sides_flipped:
		return -base_sign
	return base_sign


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
	_ctx.injury_severity = player.injury_severity

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

	# A knocked player chases half-heartedly. HeavyPlayerController's sprint
	# gate (_update_sprint(), injury_severity > INJURY_LIMP_SEVERITY) already
	# stops them physically outrunning anyone — this just discourages the AI
	# from committing to the race in the first place.
	if ctx.injury_severity > 0.0:
		base *= 1.0 - clampf(ctx.injury_severity, 0.0, 1.0) * 0.5

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
## True when a live pressing trigger names an opposing carrier this player
## should be sprinting at right now. Shares _press_trigger_chase_bonus()'s
## gating (own team not in possession, trigger carrier is a valid opponent
## still on the ball) but is evaluated per frame from _steer_for_action(),
## where wants_sprint lives, rather than on the decision tick.
func _press_trigger_commits(is_chasing: bool) -> bool:
	if not is_chasing or player == null or _team_has_ball():
		return false
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or not world.press_trigger_active:
		return false
	var carrier: HeavyPlayerController = world.press_trigger_carrier
	if not is_instance_valid(carrier) or carrier.team == player.team or carrier.is_holding_ball():
		return false
	return true


func _press_trigger_chase_bonus(ctx: UtilityContext) -> float:
	if ctx.team_has_ball or player == null:
		return 0.0
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or not world.press_trigger_active:
		return 0.0
	var carrier: HeavyPlayerController = world.press_trigger_carrier
	if not is_instance_valid(carrier) or carrier.team == player.team or carrier.is_holding_ball():
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
	# Defenders do not make forward space runs off the ball.
	if role == Role.OUTFIELD_DEFENDER:
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

	var role_cap: float = 1.0
	if role == Role.OUTFIELD_MIDFIELDER and not _is_attacking_role():
		role_cap = 0.50

	return clampf(base, 0.0, role_cap)


## Score for attempting a dribble (carrying the ball forward).
## Aggressive players attempt it; the score collapses under heavy pressure
## unless composure is very high.
func _score_dribble(ctx: UtilityContext) -> float:
	if not ctx.is_possessor:
		return 0.0
	var base: float = ctx.eff_aggression * 0.45
	# Pressure kills dribble desirability unless composure keeps it alive.
	base -= ctx.pressure * (1.0 - ctx.eff_composure) * 0.50
	# Stamina matters — a tired player should not try to beat their marker.
	base *= ctx.stamina_ratio

	# Wide players and attacking roles maintain a viable dribble floor along the flank
	# so they take on markers or carry down the wing rather than freezing or panic clearing.
	if role == Role.OUTFIELD_ATTACKER or (role == Role.OUTFIELD_MIDFIELDER and _is_attacking_role()):
		base = maxf(base, 0.12 * ctx.stamina_ratio)

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


## --- Shooting calibration ----------------------------------------------------
## Range gate (px, player -> opponent goal centre) inside which a shot is legal
## at all, and the normalising distance for the proximity ramp below.
const SHOOT_RANGE: float = 320.0
## Steepness of the exponential final-third proximity ramp:
##     U_shoot = U_base * exp(SHOOT_PROXIMITY_RAMP * (1 - d / SHOOT_RANGE)) * facing
## exp(2.2) ~= 9.03 on the goal line, decaying to a 1.0x no-op at the range
## gate. The previous linear prox_bonus (max +0.30) left a shot from 12 yards
## scoring below a square recycling pass, which is the arithmetic behind the
## 0.0-shots / 0.0-xG diagnosis: possession never converted because shooting
## never won the utility contest anywhere on the pitch. The ramp makes the
## final third genuinely different from the rest of it rather than a linear
## continuation of it.
const SHOOT_PROXIMITY_RAMP: float = 2.2
## Floor on the facing term (body heading . unit vector to goal centre) so a
## striker with the ball at their feet but half-turned still reads as able to
## shoot rather than scoring a hard zero. This term is also the repo's only
## available proxy for a strike-across-the-body penalty: PlayerData carries no
## footedness field, so a literal weak-foot multiplier would mean adding a new
## persisted attribute rather than retuning an existing one.
const SHOOT_FACING_FLOOR: float = 0.15
## Range (px) treated as "in the box" for the finishing bonus and the
## late-game desperation boost.
const SHOOT_IN_BOX_RANGE: float = 240.0
## Fraction of a goalpost lane that may be occluded before the strike stops
## counting as a clear sight of goal. Both posts must clear this bar.
const SHOOT_CLEAR_LANE_MAX_OCCLUSION: float = 0.40
## How far (px) the nearest closing defender must be before the clear-lane
## utility floor arms.
const SHOOT_CLEAR_LANE_DEFENDER_DIST: float = 70.0
## Absolute utility floor applied once a clear sight of goal is confirmed — a
## genuinely unblocked strike is never allowed to lose to a recycling pass on
## base-score arithmetic alone. See _shot_override_active() for the companion
## suppression of Pass/FindSpace.
const SHOOT_CLEAR_LANE_FLOOR: float = 0.76
## A teammate must be worth this multiple of the shooter's own xG before a
## confirmed clear sight of goal defers to a pass instead.
const SHOOT_OVERRIDE_XG_RATIO: float = 1.8
## Flat boost to shooting inside SHOOT_IN_BOX_RANGE while this team is trailing
## in the closing stage (GameManager.STAGE_3_FRACTION = 75/90 = 0.833).
const SHOOT_DESPERATION_BOOST: float = 0.25
## Multiplier collapsing MaintainFormation inside the opponent penalty area — a
## player in the box is a poacher, a blocker or a loose-ball predator, never a
## stationary formation anchor.
const BOX_FORMATION_FLOOR_COLLAPSE: float = 0.05
## Stand-in position for a non-live roster slot in _xg_opp_scratch. Far enough
## off-pitch that is_point_in_triangle() can never report it as a blocker,
## which keeps the scratch buffer a fixed size instead of being resized (and
## therefore reallocated) per call.
const OFF_PITCH_SENTINEL: Vector2 = Vector2(1.0e6, 1.0e6)


## Score for attempting a shot on goal.
## Only legal when the player owns the ball and is within SHOOT_RANGE.
## Conviction is a blend of aggression (willingness), close control (technique)
## and composure (nerve); the exponential ramp and the facing term then decide
## how much that conviction is actually worth from this position.
func _score_shoot(ctx: UtilityContext) -> float:
	if not ctx.is_possessor:
		return 0.0
	if ctx.dist_to_goal > SHOOT_RANGE:
		return 0.0

	var technique: float = player.get_close_control() if player != null else 0.65
	var base: float = 0.28 + ctx.eff_aggression * 0.28 + technique * 0.14 + ctx.eff_composure * 0.10

	var facing: float = SHOOT_FACING_FLOOR
	if player != null and pitch_boundary != null:
		facing = maxf(
			player.get_facing_dot(pitch_boundary.get_goal_centre(1 - player.team)),
			SHOOT_FACING_FLOOR)

	var ramp: float = exp(SHOOT_PROXIMITY_RAMP * (1.0 - ctx.dist_to_goal / SHOOT_RANGE))
	var score: float = base * ramp * facing

	# Under pressure, get the shot away before the challenge arrives.
	score += ctx.pressure * ctx.eff_aggression * 0.15

	if ctx.dist_to_goal < SHOOT_IN_BOX_RANGE:
		score += 0.15
		if _is_trailing_in_crunch():
			score += SHOOT_DESPERATION_BOOST

	if _has_clear_sight_of_goal():
		score = maxf(score, SHOOT_CLEAR_LANE_FLOOR)

	return clampf(score, 0.0, 1.0)


## True while this player's team is behind on the scoreboard in the closing
## stage of the match. Reads GameManager's already-published stage/score state
## rather than re-deriving the clock. Feeds SHOOT_DESPERATION_BOOST and the
## trailing-state progression bias in _find_best_pass_target().
func _is_trailing_in_crunch() -> bool:
	if player == null:
		return false
	if GameManager.get_match_time_ratio() < GameManager.STAGE_3_FRACTION:
		return false
	return GameManager.score[player.team] < GameManager.score[1 - player.team]


## True when both goalpost lanes are clear enough to strike through and no
## defender is close enough to close the shot down — the "unblockable" trigger
## behind SHOOT_CLEAR_LANE_FLOOR. Routes every spatial read through
## MatchWorldModel and allocates nothing.
func _has_clear_sight_of_goal() -> bool:
	if player == null or ball == null or pitch_boundary == null:
		return false
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return false

	var shot_pos: Vector2 = ball.global_position
	if world.nearest_opponent_dist_to(shot_pos, player.team) <= SHOOT_CLEAR_LANE_DEFENDER_DIST:
		return false

	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(1 - player.team)
	var half_mouth: float = pitch_boundary.goal_mouth_height * 0.5
	var top_post: Vector2 = Vector2(goal_centre.x, goal_centre.y - half_mouth)
	var bottom_post: Vector2 = Vector2(goal_centre.x, goal_centre.y + half_mouth)

	if _lane_occlusion(shot_pos, top_post) >= SHOOT_CLEAR_LANE_MAX_OCCLUSION:
		return false
	return _lane_occlusion(shot_pos, bottom_post) < SHOOT_CLEAR_LANE_MAX_OCCLUSION


## 0.0 (nobody near the lane) to 1.0 (an opponent standing on it) for the
## corridor between [from_pos] and [to_pos], normalised against
## PASS_LANE_CLEARANCE. Thin wrapper over MatchWorldModel's existing lane
## distance query so the occlusion percentage is expressed once, here.
func _lane_occlusion(from_pos: Vector2, to_pos: Vector2) -> float:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or player == null:
		return 0.0
	var min_dist: float = world.get_passing_lane_min_distance(from_pos, to_pos, player.team)
	return clampf(1.0 - min_dist / PASS_LANE_CLEARANCE, 0.0, 1.0)


## Expected goals for a strike taken from [shot_pos], using the repo's existing
## logistic xG solver (UtilityMath.calculate_xg) rather than a second model.
## Opponent positions are copied into the pre-sized _xg_opp_scratch buffer so
## the call allocates nothing; dead roster slots are filled with
## OFF_PITCH_SENTINEL to keep the buffer a fixed length.
func _shot_xg_at(shot_pos: Vector2) -> float:
	if player == null or pitch_boundary == null:
		return 0.0
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return 0.0

	var opp_team: int = 1 - player.team
	var slot: int = 0
	var capacity: int = _xg_opp_scratch.size()
	for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
		if slot >= capacity:
			break
		if world.player_teams[i] != opp_team or not world.is_slot_live(i):
			continue
		_xg_opp_scratch.set(slot, world.player_positions[i])
		slot += 1
	while slot < capacity:
		_xg_opp_scratch.set(slot, OFF_PITCH_SENTINEL)
		slot += 1

	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(opp_team)
	var half_mouth: float = pitch_boundary.goal_mouth_height * 0.5
	return UtilityMath.calculate_xg(
		shot_pos, goal_centre,
		Vector2(goal_centre.x, goal_centre.y - half_mouth),
		Vector2(goal_centre.x, goal_centre.y + half_mouth),
		_xg_opp_scratch, false)


## True when a confirmed clear sight of goal should suppress Pass/FindSpace
## outright. The one football-legitimate reason to pass up an unblocked strike
## is a teammate standing in a materially better position, so this defers only
## when the cached pass target's own xG beats the shooter's by
## SHOOT_OVERRIDE_XG_RATIO. Cheap by construction: the xG pair is only ever
## evaluated for the possessor, and only once _has_clear_sight_of_goal() has
## already returned true.
func _shot_override_active(ctx: UtilityContext) -> bool:
	if not ctx.is_possessor or ball == null:
		return false
	if ctx.dist_to_goal > SHOOT_RANGE:
		return false
	if not _has_clear_sight_of_goal():
		return false
	if not is_instance_valid(_cached_pass_target):
		return true
	var own_xg: float = _shot_xg_at(ball.global_position)
	var mate_xg: float = _shot_xg_at(_cached_pass_target.global_position)
	return mate_xg <= own_xg * SHOOT_OVERRIDE_XG_RATIO


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

	# Role-based tactical discipline: defenders and deep midfielders prioritize
	# maintaining structural shape over speculative forward runs.
	match role:
		Role.OUTFIELD_DEFENDER:
			base += 0.35
		Role.OUTFIELD_MIDFIELDER:
			if not _is_attacking_role():
				base += 0.20
		_:
			pass

	# Positional discipline: get back into shape when displaced from formation anchor.
	# Evaluated regardless of possession so players who drifted return to their tactical zone.
	if player != null:
		var anchor_dist: float = player.global_position.distance_to(formation_anchor)
		var anchor_urgency: float = clampf(anchor_dist / CHASE_RADIUS, 0.0, 1.0)
		base += anchor_urgency * 0.30

	# Penalty-box floor collapse: inside the opponent's 18-yard box there is no
	# such thing as holding shape. A player in there is a poacher attacking the
	# near post, a runner arriving late, or a body blocking the keeper's view —
	# never a dot standing on an anchor. Without this collapse the flat
	# discipline base (up to 0.55 for a defender, 0.20 + anchor urgency for
	# everyone else) reliably out-argues FindSpace for the attackers who should
	# be overloading the six-yard area, which is why box entries produced no
	# secondary runners and therefore no rebounds, cut-backs or tap-ins.
	if player != null and pitch_boundary != null \
			and pitch_boundary.is_in_penalty_area(player.global_position, 1 - player.team):
		base *= BOX_FORMATION_FLOOR_COLLAPSE

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

	# Condition 3: a through-ball has been played in behind — the ball is loose
	# between this team's own defensive line and its goal — and the keeper is
	# clearly favourite to reach it. That "clearly" is the whole point of
	# SWEEPER_RUSH_MARGIN: a keeper who is merely level with the attacker and
	# comes anyway is a keeper stranded in no-man's land, so the margin has to
	# be won, not tied. Reads the shared defensive line from MatchWorldModel
	# rather than deriving a private one (see docs/CORE_INVARIANTS.md).
	var is_through_ball_in_behind: bool = false
	if ball.possessor == null:
		var attack_sign: float = _get_attack_sign()
		var line_x: float = world.defensive_line_x[player.team]
		# "Behind the line" means goal-side of it along this team's own axis.
		if (ball_pos.x - line_x) * attack_sign < 0.0:
			var gk_dist: float = player.global_position.distance_to(ball_pos)
			var chaser_dist: float = world.nearest_opponent_dist_to(ball_pos, player.team)
			if gk_dist < chaser_dist - SWEEPER_RUSH_MARGIN:
				is_through_ball_in_behind = true

	if not is_loose_near_box and not is_1v1_breakaway and not is_through_ball_in_behind:
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

	# Don't rush outside the defensive third (> 380px of goal). A through-ball
	# in behind is the exception the sweeper-keeper role exists for: the whole
	# value of coming is meeting the ball before the runner does, which by
	# definition happens further out than the box.
	var rush_limit: float = SWEEPER_RUSH_MAX_DIST if is_through_ball_in_behind else 380.0
	if intercept_pt.distance_to(goal_centre) > rush_limit:
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

	# Clear sight of goal outranks buildup: a striker with an unblocked strike
	# and no defender within SHOOT_CLEAR_LANE_DEFENDER_DIST does not square it
	# off. Evaluated once here rather than inside each scorer so Pass and
	# FindSpace are suppressed together and the shot is compared against the
	# only option that legitimately beats it — a teammate in a materially
	# better position (SHOOT_OVERRIDE_XG_RATIO).
	var shot_overrides: bool = _shot_override_active(ctx)

	var s_pass: float = clampf(_score_pass(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_pass > best_score and not shot_overrides:
		best_score = s_pass
		best_action = &"Pass"

	var s_chase: float = clampf(_score_chase(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_chase > best_score:
		best_score = s_chase
		best_action = &"ChaseBall"

	var s_space: float = clampf(_score_find_space(ctx) + _rng.randf_range(-0.04, 0.04), 0.0, 1.0)
	if s_space > best_score and not shot_overrides:
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
	# force a desperation clearance only when deep in own defensive half,
	# otherwise default to attempting to carry/dribble or finding a pass.
	if ctx.is_possessor:
		var max_offensive: float = maxf(s_pass, maxf(s_dribble, s_shoot))
		if max_offensive <= 0.05:
			var in_defensive_half: bool = false
			if pitch_boundary != null and player != null:
				in_defensive_half = (player.global_position.x - pitch_boundary.get_centre_spot().x) * _get_attack_direction().x < 0.0
			if in_defensive_half and (role == Role.OUTFIELD_DEFENDER or ctx.pressure > 0.75):
				best_action = &"PanicClear"
			else:
				best_action = &"AttemptDribble"

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
const ISOLATION_RAD_SQ: float = 25600.0  # 160px * 160px
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

func has_free_kick_intent() -> bool:
	return free_kick_intent_active


func clear_free_kick_intent() -> void:
	free_kick_intent_active = false
	free_kick_action_type = FreeKickActionType.SHORT_PASS
	free_kick_charge_ratio = 0.0
	free_kick_is_lob = false
	free_kick_is_tap = true
	free_kick_action_label = "PASS"


## Evaluates tactical intent for a free kick (direct shot, cross into box,
## long ball, or short pass) based on pitch geography, direct vs indirect status,
## player attributes, and teammate positioning. Configures intent properties for
## ChargeKickState and returns the resolved aiming facing_direction.
func evaluate_free_kick_intent(fk_pos: Vector2, is_direct: bool) -> Vector2:
	free_kick_intent_active = true
	_rng.seed = (player.get_instance_id() if player != null else 1) + GameManager.get_match_tick()

	var opp_goal: Vector2 = pitch_boundary.get_goal_centre(1 - player.team) if pitch_boundary != null else Vector2(800.0 if player.team == 0 else -800.0, 0.0)
	var dist_to_goal: float = fk_pos.distance_to(opp_goal)
	var attack_dir_x: float = signf(opp_goal.x - fk_pos.x)
	if is_zero_approx(attack_dir_x):
		attack_dir_x = 1.0 if player.team == 0 else -1.0

	var mood_node: MoodSystem = player.get_mood() if player != null else null
	var eff_composure: float = clampf(composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0), 0.0, 1.0)
	var eff_aggression: float = clampf(aggression_attribute + (mood_node.get_aggression_delta() if mood_node != null else 0.0), 0.0, 1.0)

	# 1. Determine weights for each potential action
	var w_shot: float = 0.0
	var w_cross: float = 0.0
	var w_long: float = 0.0
	var w_pass: float = 0.35

	# DIRECT SHOT: Direct FK only, within shooting range (~480px) and feasible lateral angle
	var lat_dist_to_goal: float = absf(fk_pos.y - opp_goal.y)
	if is_direct and dist_to_goal <= 480.0 and lat_dist_to_goal <= 260.0:
		var dist_factor: float = clampf(1.0 - (dist_to_goal - 180.0) / 300.0, 0.0, 1.0)
		var angle_factor: float = clampf(1.0 - lat_dist_to_goal / 260.0, 0.0, 1.0)
		w_shot = 0.40 + dist_factor * 0.40 + angle_factor * 0.30
		if role == Role.OUTFIELD_ATTACKER:
			w_shot += 0.20
		elif role == Role.OUTFIELD_DEFENDER:
			w_shot -= 0.25
		w_shot += (eff_aggression - 0.5) * 0.20 + (eff_composure - 0.5) * 0.15
		w_shot = clampf(w_shot, 0.10, 1.50)

	# CROSS: In attacking half / crossing range (~200px to ~720px from goal)
	if dist_to_goal >= 200.0 and dist_to_goal <= 720.0:
		var wide_factor: float = clampf(lat_dist_to_goal / 200.0, 0.0, 1.0)
		w_cross = 0.35 + wide_factor * 0.45
		if dist_to_goal > 320.0 and dist_to_goal <= 600.0:
			w_cross += 0.30
		if not is_direct:
			w_cross += 0.50
		w_cross = clampf(w_cross, 0.10, 1.30)

	# LONG BALL: In defensive half / deep territory
	if dist_to_goal > 620.0:
		var deep_factor: float = clampf((dist_to_goal - 620.0) / 400.0, 0.0, 1.0)
		w_long = 0.40 + deep_factor * 0.50
		if role == Role.OUTFIELD_DEFENDER:
			w_long += 0.20
		w_long = clampf(w_long, 0.10, 1.20)

	# 2. Weighted sampling
	var total_weight: float = w_shot + w_cross + w_long + w_pass
	var roll: float = _rng.randf() * total_weight
	var chosen_action: FreeKickActionType = FreeKickActionType.SHORT_PASS

	if roll < w_shot:
		chosen_action = FreeKickActionType.DIRECT_SHOT
	elif roll < w_shot + w_cross:
		chosen_action = FreeKickActionType.CROSS
	elif roll < w_shot + w_cross + w_long:
		chosen_action = FreeKickActionType.LONG_BALL
	else:
		chosen_action = FreeKickActionType.SHORT_PASS

	# 3. Resolve execution parameters and aim direction
	var aim_dir: Vector2 = Vector2.ZERO
	free_kick_action_type = chosen_action

	match chosen_action:
		FreeKickActionType.DIRECT_SHOT:
			free_kick_action_label = "DIRECT FK"
			free_kick_is_tap = false
			var corner_y: float = -65.0 if _rng.randf() < 0.5 else 65.0
			var target_point: Vector2 = opp_goal + Vector2(0.0, corner_y + _rng.randf_range(-15.0, 15.0))
			aim_dir = (target_point - fk_pos).normalized()
			free_kick_charge_ratio = clampf(lerpf(0.70, 0.95, dist_to_goal / 480.0), 0.65, 0.98)
			free_kick_is_lob = dist_to_goal > 280.0 or _rng.randf() < 0.60

		FreeKickActionType.CROSS:
			free_kick_action_label = "CROSS"
			free_kick_is_tap = false
			free_kick_is_lob = true
			var box_target: Vector2 = opp_goal + Vector2(-attack_dir_x * 150.0, _rng.randf_range(-40.0, 40.0))
			var best_teammate: HeavyPlayerController = _find_best_box_target(opp_goal, attack_dir_x)
			if best_teammate != null:
				box_target = best_teammate.global_position + Vector2(attack_dir_x * 20.0, 0.0)
			aim_dir = (box_target - fk_pos).normalized()
			var target_dist: float = fk_pos.distance_to(box_target)
			free_kick_charge_ratio = clampf(target_dist / 480.0, 0.65, 0.85)

		FreeKickActionType.LONG_BALL:
			free_kick_action_label = "LONG BALL"
			free_kick_is_tap = false
			free_kick_is_lob = true
			var advanced_target: Vector2 = (pitch_boundary.get_centre_spot() if pitch_boundary != null else Vector2.ZERO) + Vector2(attack_dir_x * 240.0, _rng.randf_range(-120.0, 120.0))
			var best_fwd: HeavyPlayerController = _find_most_advanced_teammate(attack_dir_x)
			if best_fwd != null:
				advanced_target = best_fwd.global_position + Vector2(attack_dir_x * 30.0, 0.0)
			aim_dir = (advanced_target - fk_pos).normalized()
			var long_dist: float = fk_pos.distance_to(advanced_target)
			free_kick_charge_ratio = clampf(long_dist / 550.0, 0.75, 0.92)

		FreeKickActionType.SHORT_PASS:
			free_kick_action_label = "PASS"
			free_kick_is_tap = true
			free_kick_is_lob = false
			free_kick_charge_ratio = 0.0
			var pass_target: HeavyPlayerController = find_pass_target_for_set_piece()
			if pass_target != null:
				aim_dir = (pass_target.global_position - fk_pos).normalized()
			elif pitch_boundary != null:
				aim_dir = (opp_goal - fk_pos).normalized()
			else:
				aim_dir = Vector2(attack_dir_x, 0.0)

	if is_zero_approx(aim_dir.length_squared()):
		aim_dir = Vector2(attack_dir_x, 0.0)

	return aim_dir


func _find_best_box_target(opp_goal: Vector2, attack_dir_x: float) -> HeavyPlayerController:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or player == null:
		return null
	var best: HeavyPlayerController = null
	var best_dist_sq: float = 99999999.0
	for i: int in range(world.player_nodes.size()):
		if world.player_teams[i] != player.team:
			continue
		var other: HeavyPlayerController = world.player_nodes[i]
		if other == null or other == player:
			continue
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain != null and other_brain.is_goalkeeper:
			continue
		var p_pos: Vector2 = other.global_position
		var depth_to_goal: float = (opp_goal.x - p_pos.x) * attack_dir_x
		if depth_to_goal > 0.0 and depth_to_goal < 320.0 and absf(p_pos.y - opp_goal.y) < 280.0:
			var d_sq: float = p_pos.distance_squared_to(opp_goal)
			if d_sq < best_dist_sq:
				best_dist_sq = d_sq
				best = other
	return best


func _find_most_advanced_teammate(attack_dir_x: float) -> HeavyPlayerController:
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null or player == null:
		return null
	var best: HeavyPlayerController = null
	var best_advancement: float = -999999.0
	for i: int in range(world.player_nodes.size()):
		if world.player_teams[i] != player.team:
			continue
		var other: HeavyPlayerController = world.player_nodes[i]
		if other == null or other == player:
			continue
		var other_brain := other.get_node_or_null("PlayerBrain") as PlayerBrain
		if other_brain != null and other_brain.is_goalkeeper:
			continue
		var adv: float = other.global_position.x * attack_dir_x
		if adv > best_advancement:
			best_advancement = adv
			best = other
	return best


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

	# --- Directional bias context (loop-invariant) ---------------------------
	# A side chasing the game in the closing stage leans harder into progression
	# and refuses the unforced backward ball outright; see PassUtilityScorer's
	# TRAILING_PROGRESS_MULTIPLIER / BACKWARD_PASS_PENALTY_TRAILING.
	var trailing_late: bool = _is_trailing_in_crunch()
	if trailing_late:
		urgent_w_adv *= PassUtilityScorer.TRAILING_PROGRESS_MULTIPLIER
	var backward_penalty: float = PassUtilityScorer.BACKWARD_PASS_PENALTY_TRAILING if trailing_late \
		else PassUtilityScorer.BACKWARD_PASS_PENALTY

	# The backward damper only applies from the middle third forward, and only
	# while the carrier actually has time on the ball — a centre-back genuinely
	# pinned by a presser keeps the safety valve.
	var carrier_axis_x: float = (ball_pos.x - (pitch_boundary.get_centre_spot().x if pitch_boundary != null else 0.0)) * attack_dir.x
	var nearest_presser: float = world.nearest_opponent_dist_to(ball_pos, player.team)
	var damp_backward: bool = carrier_axis_x > PassUtilityScorer.BACKWARD_DAMP_MIN_AXIS_X \
		and nearest_presser > PassUtilityScorer.UNPRESSURED_DEFENDER_DIST

	# Centre-back-to-centre-back recycling is the single clearest signature of
	# the sterile possession loop, so it is gated separately and harder: two
	# defenders may only pass between themselves once every forward lane out of
	# defence is genuinely shut (CB_RECYCLE_MIN_OCCLUSION).
	var passer_is_defender: bool = role == Role.OUTFIELD_DEFENDER
	var forward_lanes_shut: bool = passer_is_defender and _forward_lanes_are_shut()

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

		# Packing: how many opponents this ball actually eliminates. Spatial read,
		# so it comes from the world model cache, not a local roster walk.
		var bypassed: float = float(world.count_bypassed_opponents(
			ball_pos, candidate_pos, player.team, xt_attack_sign))

		# Directional bias, resolved here (the scorer stays match-state-free).
		var directional_bias: float = 0.0
		var is_negative_ball: bool = forward_dot < PassUtilityScorer.BACKWARD_PASS_DOT
		if is_negative_ball:
			if allow_backward_pass:
				pass
			elif passer_is_defender and candidate_brain != null \
					and candidate_brain.role == Role.OUTFIELD_DEFENDER and not forward_lanes_shut:
				# Back-line recycle with a way forward still available — refuse it.
				continue
			elif damp_backward:
				directional_bias -= backward_penalty
		elif _is_lead_pass_candidate(candidate, attack_dir):
			# Ball into the space ahead of a runner rather than into their feet.
			directional_bias += PassUtilityScorer.LEAD_PASS_BONUS

		# Hot path: bare float, allocates nothing (see PassUtilityScorer docs).
		var score: float = PassUtilityScorer.score_pass(
			distance, facing_dot, forward_dot, min_opp_dist, effective_pressure,
			w_dist, w_angle, urgent_w_press, urgent_w_adv, xt_value,
			bypassed, directional_bias)

		# Trust bias: how much this passer trusts THIS candidate as a receiver
		# nudges the already-computed utility score up or down. Neutral trust
		# (no history yet) is a 1.0x no-op — see TrustSystem.trust_multiplier().
		if trust_sys != null:
			score *= TrustSystem.trust_multiplier(trust_sys.get_trust(TrustSystem.player_key(candidate)))

		# Injury dampener: a knocked teammate cannot create the separation a
		# fit one can, so their apparent openness is discounted here rather
		# than inside PassUtilityScorer itself (see HeavyPlayerController.
		# injury_severity doc comment).
		if candidate.injury_severity > 0.0:
			score *= 1.0 - clampf(candidate.injury_severity, 0.0, 1.0) * 0.5

		# Isolation reward: layered on top of the trust-adjusted score
		# rather than folded into PassUtilityScorer's own weighted total
		# (see ISOLATION_RAD_SQ doc comment above for why).
		var iso_dist_sq: float = min_opp_dist * min_opp_dist
		var u_free: float = clampf(iso_dist_sq / ISOLATION_RAD_SQ, 0.45, 1.75)
		score *= u_free
		if min_opp_dist > ISOLATION_BONUS_DIST:
			score += ISOLATION_BONUS_SCORE

		if debug_log_pass_scores:
			var breakdown: PassUtilityScorer.PassScoreBreakdown = PassUtilityScorer.score_pass_breakdown(
				distance, facing_dot, forward_dot, min_opp_dist, effective_pressure, candidate,
				w_dist, w_angle, urgent_w_press, urgent_w_adv, xt_value,
				bypassed, directional_bias)
			# breakdown.total is pre-trust; `score` (post-multiplier) is what
			# actually decides best_target below, so print both.
			print("[PassScorer] %s -> %s  dist=%.2f angle=%.2f pressure=%.2f adv=%.2f pack=%.2f xt=%.2f bias=%+.2f  raw=%.3f trust_adj=%.3f" % [
				player.name, candidate.name,
				breakdown.distance_utility, breakdown.angle_utility,
				breakdown.pressure_utility, breakdown.advancement_utility,
				breakdown.packing_utility, xt_value, directional_bias,
				breakdown.total, score])

		if score > best_score:
			best_score = score
			best_target = candidate

	if debug_log_pass_scores and best_target != null:
		print("[PassScorer] %s picks %s  total=%.3f" % [player.name, best_target.name, best_score])

	_cached_pass_score = best_score if best_target != null else 0.0
	return best_target


## True when every forward outlet from the current ball position is occluded
## past PassUtilityScorer.CB_RECYCLE_MIN_OCCLUSION — the only condition under
## which two centre-backs are allowed to pass between themselves. Samples the
## lane to each forward teammate rather than a fan of arbitrary probe points,
## so "no way out" means no actual pass exists, not merely that a fixed
## direction happens to be blocked. Allocation-free.
func _forward_lanes_are_shut() -> bool:
	if player == null or ball == null:
		return true
	var world: MatchWorldModel = MatchWorldModel.instance
	if world == null:
		return true
	var attack_dir: Vector2 = _get_attack_direction()
	var ball_pos: Vector2 = ball.global_position

	for c: int in range(MatchWorldModel.TOTAL_PLAYERS):
		if world.player_teams[c] != player.team or not world.is_slot_live(c):
			continue
		var candidate: HeavyPlayerController = world.player_nodes[c]
		if candidate == player:
			continue
		var candidate_pos: Vector2 = world.player_positions[c]
		var to_candidate: Vector2 = candidate_pos - ball_pos
		if to_candidate.length_squared() < 1.0:
			continue
		if to_candidate.normalized().dot(attack_dir) <= 0.0:
			continue
		if _lane_occlusion(ball_pos, candidate_pos) < PassUtilityScorer.CB_RECYCLE_MIN_OCCLUSION:
			return false
	return true


## True when [candidate] is running onto the ball rather than standing to
## receive it — sprinting, and carrying real velocity along the attacking
## axis. The pass is then worth playing into the space ahead of them
## (PassUtilityScorer.LEAD_PASS_BONUS); _steer_for_action() already aims every
## pass at a lead point, so this only prices the option, it does not change
## where the ball is struck.
func _is_lead_pass_candidate(candidate: HeavyPlayerController, attack_dir: Vector2) -> bool:
	if not is_instance_valid(candidate) or not candidate.wants_sprint:
		return false
	if candidate.velocity.length_squared() < 1.0:
		return false
	return candidate.velocity.normalized().dot(attack_dir) > PassUtilityScorer.LEAD_PASS_MIN_FORWARD_DOT


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
	# chase the ball at once. Exactly 1 per outfield role (1 attacker, 1 mid,
	# 1 defender) prevents swarming and maintains team shape.
	var budget: int = 1
	if role == Role.GOALKEEPER:
		return false

	if ball.possessor != null and ball.possessor is HeavyPlayerController:
		var carrier := ball.possessor as HeavyPlayerController
		if carrier.is_holding_ball():
			return false

	# Maximum distance from the ball at which this player will ever chase,
	# regardless of being closest. Keeps shape when play is far away.
	var max_dist: float = (player.role_config.max_chase_distance
			if player != null and player.role_config != null
			else 280.0 if role == Role.OUTFIELD_ATTACKER
			else 220.0 if role == Role.OUTFIELD_MIDFIELDER
			else 180.0 if role == Role.OUTFIELD_DEFENDER
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


## Returns true if a teammate (or this player) controls or last touched the ball.
func _team_has_ball() -> bool:
	if ball == null:
		return false
	if ball.possessor != null and ball.possessor is HeavyPlayerController:
		var carrier := ball.possessor as HeavyPlayerController
		return carrier.team == player.team
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
## Roam alpha per role — the INVERSE of PlayerRoleConfig.anchor_weight (see
## docs/CORE_INVARIANTS.md): 0.0 holds the formation anchor rigidly, 1.0 roams
## freely. This dictionary, not the .tres presets, is what a live match
## actually runs on: role_config is an unassigned @export on every player in
## pitch/PitchScene.tscn, so _evaluate_off_ball_target() falls through to here.
## The presets in shared/roles/ are kept numerically consistent with it
## (alpha == 1.0 - anchor_weight) so assigning one never silently changes
## behaviour.
##
## Calibration (elastic geometry): the attacker's 0.65 (anchor_weight 0.35)
## kept strikers tethered close enough to a static anchor that they were never
## ahead of the ball when it arrived in the final third — there was simply
## nobody to pass forward to, which is half of why possession recycled instead
## of progressing. 0.78 (anchor_weight 0.22) lets a poacher play off the last
## defender's shoulder. Defenders move the other way (0.20 -> 0.15) to hold the
## rest-defence band; see MatchWorldModel.LINE_OFFSET_REST_DEFENCE.
const ROLE_SPACE_ALPHA: Dictionary = {
	Role.OUTFIELD_DEFENDER: 0.15,
	Role.OUTFIELD_MIDFIELDER: 0.50,
	Role.OUTFIELD_ATTACKER: 0.78,
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
## --- Role-specific anchor elasticity ----------------------------------------
## Lateral distance (px) from the pitch centre line beyond which an
## OUTFIELD_ATTACKER's formation anchor marks them as a wide player rather than
## a central striker. Read off the anchor rather than a role name because
## role_config — the only place a role string lives — is an unassigned @export
## in pitch/PitchScene.tscn (see ROLE_SPACE_ALPHA).
const WIDE_ATTACKER_ANCHOR_Y: float = 150.0
## Ball lateral offset (px) from the centre line past which the ball counts as
## being on the far flank from a given winger, arming the far-post bias.
const OPPOSITE_FLANK_BALL_Y: float = 120.0
## How far (0-1) a weak-side winger collapses off their own touchline toward
## the far post while the ball is worked down the opposite flank. Without this
## the far-side winger holds width on a flank the ball is never coming to, so
## a cross arrives into a box containing one striker and no second runner.
const FAR_POST_BIAS: float = 0.55
## Depth (px) off the goal line the far-post arrival point sits at — roughly
## the back edge of the six-yard box, where a cut-back or deep cross lands.
const FAR_POST_DEPTH: float = 90.0
## Fraction of the goal mouth half-height the far-post arrival point sits from
## the goal's centre.
const FAR_POST_MOUTH_RATIO: float = 0.85

## Distance (px) a midfielder's passing-triangle position is pulled toward the
## carrier, on top of the lateral offset, so the outlet is a genuine short
## diagonal rather than a flat square ball the first presser cuts out.
const TRIANGLE_CARRIER_PULL: float = 45.0

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
	# Only the ONE defender _resolve_defensive_duty() actually named as this
	# tick's presser is released from the chase budget. Previously any player at
	# all had the budget lifted for the whole duration of a press trigger, so
	# both centre-backs (and everyone else) could abandon their anchor and
	# converge on the same carrier at once — the shape broke exactly when a
	# turnover was most likely, and there was no rest defence left behind the
	# ball. Everyone else presses within their radius or holds the line.
	if current_duty == DefensiveDuty.TRIGGER_PRESS \
			and wm.press_trigger_active and wm.press_trigger_carrier != null \
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

	var carrier := ball.possessor as HeavyPlayerController if (ball.possessor != null and ball.possessor is HeavyPlayerController) else null
	if carrier != null and carrier.is_holding_ball():
		if carrier.team != player.team:
			# Opposing goalkeeper is holding the ball: fall back to defensive formation shape and keep outside the penalty box
			var fallback_anchor: Vector2 = formation_anchor
			if pitch_boundary != null:
				var opp_goal_x: float = pitch_boundary.get_goal_centre(1 - player.team).x
				var min_x_from_goal: float = PitchBoundary.PENALTY_AREA_DEPTH + 40.0
				if opp_goal_x < 0.0:
					fallback_anchor.x = maxf(fallback_anchor.x, opp_goal_x + min_x_from_goal)
				else:
					fallback_anchor.x = minf(fallback_anchor.x, opp_goal_x - min_x_from_goal)
			return clamp_to_playable_area(fallback_anchor)
		else:
			# Own goalkeeper is holding the ball: fan out and push forward into open distribution lanes
			var fwd_dir: float = _get_attack_sign()
			match role:
				Role.OUTFIELD_DEFENDER:
					var wide_anchor: Vector2 = formation_anchor
					if absf(formation_anchor.y) < 80.0:
						wide_anchor.y += 120.0 if player_index % 2 == 0 else -120.0
					return clamp_to_playable_area(wide_anchor)
				Role.OUTFIELD_MIDFIELDER:
					var mid_target: Vector2 = formation_anchor + Vector2(fwd_dir * 40.0, 0.0)
					return clamp_to_playable_area(mid_target)
				Role.OUTFIELD_ATTACKER:
					var att_target: Vector2 = formation_anchor + Vector2(fwd_dir * 80.0, 0.0)
					return clamp_to_playable_area(att_target)

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
	dynamic_anchor = _apply_far_post_bias(dynamic_anchor, ball_pos)
	return _evaluate_off_ball_target(dynamic_anchor)


## Pulls a weak-side winger off their own touchline and in toward the far post
## while the ball is being worked down the opposite flank — the inward
## half-space bias that turns a cross into a chance instead of a clearance.
## No-op for central strikers, for midfielders and defenders, and whenever the
## ball is on this player's own side of the pitch. Returns [anchor] unchanged
## in every one of those cases, so the caller can apply it unconditionally.
func _apply_far_post_bias(anchor: Vector2, ball_pos: Vector2) -> Vector2:
	if role != Role.OUTFIELD_ATTACKER or player == null or pitch_boundary == null:
		return anchor
	if not _team_has_ball():
		return anchor

	var centre_y: float = pitch_boundary.get_centre_spot().y
	var my_side: float = signf(formation_anchor.y - centre_y)
	if is_zero_approx(my_side) or absf(formation_anchor.y - centre_y) < WIDE_ATTACKER_ANCHOR_Y:
		return anchor  # central striker, not a winger

	var ball_side_offset: float = ball_pos.y - centre_y
	if absf(ball_side_offset) < OPPOSITE_FLANK_BALL_Y or signf(ball_side_offset) == my_side:
		return anchor  # ball is central, or already on this winger's flank

	var goal_centre: Vector2 = pitch_boundary.get_goal_centre(1 - player.team)
	var far_post: Vector2 = Vector2(
		goal_centre.x - _get_attack_sign() * FAR_POST_DEPTH,
		goal_centre.y + my_side * pitch_boundary.goal_mouth_height * 0.5 * FAR_POST_MOUTH_RATIO)
	return anchor.lerp(far_post, FAR_POST_BIAS)


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
	# Blend 65% with formation_anchor so midfielders maintain their tactical depth without collapsing into the ball carrier
	var blended_pos: Vector2 = triangle_pos.lerp(formation_anchor, 0.65)

	# Shift the settled position TRIANGLE_CARRIER_PULL px back toward the
	# carrier. The 65% anchor blend above is what stops midfielders collapsing
	# onto the ball, but it also pushed the outlet far enough away that the
	# short diagonal escape ball stopped existing — the carrier's only options
	# were long or backwards. This restores the near leg of the triangle
	# without giving back the depth discipline.
	var to_carrier: Vector2 = ball_pos - blended_pos
	if to_carrier.length_squared() > TRIANGLE_CARRIER_PULL * TRIANGLE_CARRIER_PULL:
		blended_pos += to_carrier.normalized() * TRIANGLE_CARRIER_PULL

	return clamp_to_playable_area(blended_pos)


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
	if not is_instance_valid(carrier) or carrier.team == player.team or carrier.is_holding_ball():
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
	if ball == null or ball.is_airborne():
		return false

	var holder: HeavyPlayerController = ball.possessor as HeavyPlayerController
	if holder == null or holder.team == player.team:
		return false

	if player.global_position.distance_squared_to(ball.global_position) \
			> TACKLE_ATTEMPT_RANGE * TACKLE_ATTEMPT_RANGE:
		return false

	# A slide tackle commit requires a well-aimed angle toward the ball (>= 0.60, ~53° cone)
	# to prevent high-risk clipping from the side or behind.
	if player.get_facing_dot(ball.global_position) < 0.60:
		return false

	# ...and the defender must be moving INTO the challenge, not drifting across
	# it. Without this a defender whose body happens to point at the ball while
	# its momentum carries it elsewhere still launches, which is the mistimed
	# lunge TackleState then punishes with a foul.
	var to_carrier: Vector2 = holder.global_position - player.global_position
	if player.movement_intent.length_squared() > 0.0001 and to_carrier.length_squared() > 0.0001:
		if player.movement_intent.normalized().dot(to_carrier.normalized()) < TACKLE_INTENT_DOT:
			return false

	# Disciplinary caution: a player already carrying a yellow card avoids reckless slide tackles.
	var pdata: PlayerData = player.get_meta(&"player_data", null) as PlayerData
	if pdata != null and pdata.yellow_cards_this_match > 0:
		if _rng.randf() > 0.15:
			return false

	# Personality risk calibration: composed players contain on their feet;
	# aggression drives the willingness to slide in.
	var mood_node: MoodSystem = player.get_mood() if player != null else null
	var eff_aggression: float = clampf(aggression_attribute + (mood_node.get_aggression_delta() if mood_node != null else 0.0), 0.0, 1.0)
	var eff_composure: float = clampf(composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0), 0.0, 1.0)

	var commit_chance: float = eff_aggression * 0.35 + (1.0 - eff_composure) * 0.15
	if role == Role.OUTFIELD_DEFENDER and current_duty == DefensiveDuty.TRIGGER_PRESS:
		commit_chance = minf(commit_chance + 0.30, 0.75)

	# Attribute contest: a defender reads how likely it is to actually get the
	# ball off THIS carrier before diving in. close_control is the repo's
	# technical/dribbling attribute (see PlayerData.calculate_overall_rating),
	# so a defender's own control stands in for tackling technique and the
	# carrier's for their ability to ride the challenge. Centred on 1.0 so an
	# even matchup is a no-op and only a genuine mismatch moves the odds.
	var contest: float = 1.0 + (player.get_close_control() - holder.get_close_control()) * 0.5
	commit_chance *= clampf(contest, 0.55, 1.45)

	if _rng.randf() > clampf(commit_chance, 0.10, 0.65):
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
const DRIBBLE_FORWARD_WEIGHT: float = 0.60
## Weight on a probe's clearance from the nearest opponent (scaled for local proximity).
const DRIBBLE_SPACE_WEIGHT: float = 0.0012
## Maximum local space distance considered for open-space dribble scoring (px).
const DRIBBLE_MAX_LOCAL_SPACE_DIST: float = 250.0
## Buffer distance from touchlines inside which dribble probes incur a boundary penalty.
const DRIBBLE_TOUCHLINE_BUFFER: float = 75.0
## Buffer distance from endlines inside which dribble probes incur a boundary penalty.
const DRIBBLE_ENDLINE_BUFFER: float = 85.0
## Outfield team spread threshold (X-axis) beyond which ambient Sacchi compactness applies.
const SACCHI_MAX_OUTFIELD_SPREAD: float = 540.0
## Maximum force magnitude of ambient Sacchi compactness nudge.
const SACCHI_MAX_FORCE: float = 0.20

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
	elif not _team_has_ball() and player != null:
		var carrier: HeavyPlayerController = _get_ball_carrier()
		if carrier != null and is_instance_valid(carrier):
			var dist_to_carrier: float = player.global_position.distance_to(carrier.global_position)
			if dist_to_carrier < 110.0:
				player.show_action_text("JOCKEY", Color(0.35, 0.75, 1.0))

	# --- Pass execution ---
	var is_throw_in_taker: bool = player != null and player.state_factory != null and player.state_factory.current_state_name == &"ThrowIn"
	# Settle window: a carrier who has just taken the ball under control holds
	# it for DribbleState's CONTROL_SETTLE window before releasing a pass, so a
	# reception is a touch-turn-look-up rather than a first-time redirection of
	# whatever arrived. The exception is a carrier under genuine pressure with a
	# defender already on them — that player has no time to settle anything and
	# must be free to move it immediately, which is also what keeps the panic
	# outlet intact.
	var settle_holds: bool = player.ball_settle_timer > 0.0 \
		and calculate_pressure_index() < SETTLE_OVERRIDE_PRESSURE
	if current_action == &"Pass" and _cached_pass_target != null and is_instance_valid(_cached_pass_target) \
			and not is_throw_in_taker and not settle_holds:
		if player.global_position.distance_to(ball.global_position) < 80.0 and player.get_ball_in_foot_range() != null:
			var lead_pos: Vector2 = _cached_pass_target.global_position + _cached_pass_target.velocity * PASS_LEAD_SECONDS
			var to_target: Vector2 = lead_pos - ball.global_position
			var aim: Vector2 = to_target.normalized()

			# Crowded passers misplace the ball. Scatter is applied to the struck
			# direction, not to the target selection, so the AI still *intends* the
			# right pass and simply fails to execute it — which is what turns a
			# press into turnovers rather than into slower but equally perfect
			# possession.
			var pass_mood: MoodSystem = player.get_mood()
			var pass_composure: float = clampf(
				composure_attribute + (pass_mood.get_composure_delta() if pass_mood != null else 0.0), 0.0, 1.0)
			var pass_decay: float = _crowding_accuracy_decay(pass_composure)
			if pass_decay > 0.0:
				_rng.seed = player.get_instance_id() + GameManager.get_match_tick()
				var scatter: float = _rng.randf_range(-PASS_CROWDING_SCATTER, PASS_CROWDING_SCATTER) * pass_decay
				aim = aim.rotated(scatter)

			var pass_speed: float = _solve_pass_speed(to_target.length())
			ball.apply_kick(aim * pass_speed, 0.0, player)

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

			player.show_action_text("PASS")
			GameEvents.ball_struck.emit(player, pass_speed, PASS_CHARGE_RATIO, false)
			MatchStatsTracker.record_pass_attempt(player, MatchStatsTracker.is_pass_toward_teammate(player, aim))

			_cached_pass_target = null
			current_action = &"MaintainFormation"

	# --- Panic clear execution ---
	# Clear the ball decisively upfield / into the opponent's half with height and power,
	# rather than kicking it sideways out for an opponent throw-in.
	if current_action == &"PanicClear" and pitch_boundary != null \
			and player.global_position.distance_to(ball.global_position) < 80.0 \
			and player.get_ball_in_foot_range() != null:
		var attack_dir: Vector2 = _get_attack_direction()
		_rng.seed = player.get_instance_id() + GameManager.get_match_tick()
		var scatter_y: float = _rng.randf_range(-0.35, 0.35)
		var clear_dir: Vector2 = (attack_dir + Vector2(0.0, scatter_y)).normalized()
		var clear_speed: float = 480.0
		# 340 px/s against the ball's 580 px/s^2 gravity is a 1.17s hang — inside
		# the aerial-contest window (see ChargeKickState.LOB_MIN_VELOCITY_Z).
		# At the previous 280 the clearance was down again in 0.97s, landing
		# before anyone could organise a challenge for the second ball.
		var clear_height: float = 340.0
		ball.apply_kick(clear_dir * clear_speed, clear_height, player)
		player.show_action_text("CLEAR")
		GameEvents.ball_struck.emit(player, clear_speed, 0.75, false)
		MatchStatsTracker.record_pass_attempt(player, false)
		current_action = &"MaintainFormation"

	# --- Shoot execution ---
	if current_action == &"AttemptShoot" and pitch_boundary != null \
			and player.global_position.distance_to(ball.global_position) < 80.0 \
			and player.get_ball_in_foot_range() != null:
		var opp_team: int = 1 - player.team
		var goal_centre: Vector2 = pitch_boundary.get_goal_centre(opp_team)
		var half_mouth: float = pitch_boundary.goal_mouth_height * 0.5

		# Locate opposing goalkeeper to place the shot into the open corner away from them
		var opp_gk_y: float = goal_centre.y
		var world_shoot: MatchWorldModel = MatchWorldModel.instance
		if world_shoot != null:
			for i: int in range(MatchWorldModel.TOTAL_PLAYERS):
				if world_shoot.player_teams[i] == opp_team and world_shoot.is_slot_live(i):
					var opp_p: HeavyPlayerController = world_shoot.player_nodes[i]
					if opp_p != null and is_instance_valid(opp_p) and opp_p.brain != null and opp_p.brain.is_goalkeeper:
						opp_gk_y = world_shoot.player_positions[i].y
						break

		# Select corner: if keeper is positioned below center, shoot high (-Y), else low (+Y)
		_rng.seed = player.get_instance_id() + GameManager.get_match_tick()
		var side_sign: float = 1.0 if opp_gk_y <= goal_centre.y else -1.0
		if absf(opp_gk_y - goal_centre.y) < 15.0:
			# Keeper is dead center: pick corner based on striker's side
			side_sign = 1.0 if (player.global_position.y >= goal_centre.y) else -1.0

		var mood_node: MoodSystem = player.get_mood() if player != null else null
		var eff_composure: float = clampf(composure_attribute + (mood_node.get_composure_delta() if mood_node != null else 0.0), 0.0, 1.0)

		# Target corner placement: 68% of half mouth (~68px from center, 32px inside post)
		var corner_target_y: float = goal_centre.y + side_sign * (half_mouth * 0.68)
		# Base placement spread from composure, widened further when the striker
		# is being closed down by more than one defender at the moment of the
		# strike — the difference between picking a corner and getting a shot away.
		var shot_decay: float = _crowding_accuracy_decay(eff_composure)
		var spread: float = (1.0 - eff_composure) * 35.0 + shot_decay * 40.0
		var aim_y: float = clampf(corner_target_y + _rng.randf_range(-spread, spread), goal_centre.y - half_mouth + 15.0, goal_centre.y + half_mouth - 15.0)

		var aim_target: Vector2 = Vector2(goal_centre.x, aim_y)
		var aim_dir: Vector2 = (aim_target - ball.global_position).normalized()

		# Shot power scales with proximity & aggression: 540px/s to 640px/s with full strike conviction
		var dist_to_mouth: float = player.global_position.distance_to(goal_centre)
		var dist_ratio: float = clampf(1.0 - dist_to_mouth / 320.0, 0.0, 1.0)
		var shot_power: float = lerpf(540.0, 640.0, dist_ratio * 0.7 + aggression_attribute * 0.3)
		var charge_ratio: float = lerpf(0.75, 1.0, dist_ratio)

		# Inherit striker momentum forward
		var run_dot: float = clampf(player.velocity.normalized().dot(aim_dir), 0.0, 1.0) if player.velocity.length_squared() > 1.0 else 0.0
		var inherited: Vector2 = aim_dir * (player.velocity.length() * run_dot * 0.30)

		ball.apply_kick(aim_dir * shot_power + inherited, 0.0, player)
		if charge_ratio > 0.65:
			GameEvents.powerful_shot_landed.emit(player, shot_power, charge_ratio)
		player.show_action_text("SHOT")
		GameEvents.ball_struck.emit(player, shot_power, charge_ratio, true)
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
			# opponent clearance + boundary avoidance, rather than committing
			# to a single fixed attack_dir/goal-lerp target.
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
					var forward_dot: float = probe_dir.dot(forward_ref)

					# Backward or reverse directions are penalized heavily
					var forward_score: float = forward_dot * DRIBBLE_FORWARD_WEIGHT
					if forward_dot < 0.0:
						forward_score *= 2.0

					# Cap opponent clearance to a local threat bubble so distant empty touchline space does not swamp goal pursuit
					var raw_opp_dist: float = world_probe.nearest_opponent_dist_to(probe_pos, player.team)
					var local_opp_dist: float = minf(raw_opp_dist, DRIBBLE_MAX_LOCAL_SPACE_DIST)
					var space_score: float = local_opp_dist * DRIBBLE_SPACE_WEIGHT

					# Penalize probes heading toward or beyond touchlines/endlines
					var boundary_penalty: float = 0.0
					if pitch_boundary != null:
						var pitch_half: Vector2 = pitch_boundary.pitch_size * 0.5
						var margin_y: float = pitch_half.y - absf(probe_pos.y)
						if margin_y < DRIBBLE_TOUCHLINE_BUFFER:
							boundary_penalty += (1.0 - clampf(margin_y / DRIBBLE_TOUCHLINE_BUFFER, 0.0, 1.0)) * 0.60
						var margin_x: float = pitch_half.x - absf(probe_pos.x)
						if margin_x < DRIBBLE_ENDLINE_BUFFER:
							boundary_penalty += (1.0 - clampf(margin_x / DRIBBLE_ENDLINE_BUFFER, 0.0, 1.0)) * 0.60

					var probe_score: float = forward_score + space_score - boundary_penalty
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

	# 2. Separation — only off-ball so carriers and chasers aren't pushed off course.
	var sep_force: Vector2 = Vector2.ZERO
	if current_action != &"ChaseBall" and current_action != &"PanicClear" and current_action != &"AttemptDribble" and current_action != &"Pass":
		sep_force = _cached_separation * 0.40

	# 3. Formation spring — gentle pull back when very far from anchor (off-ball only)
	var spring_force: Vector2 = Vector2.ZERO
	if current_action != &"AttemptDribble" and current_action != &"Pass" and current_action != &"ChaseBall" and current_action != &"PanicClear" and current_action != &"AttemptShoot":
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
	if role == Role.OUTFIELD_DEFENDER and current_action != &"ChaseBall" and current_action != &"PanicClear" and current_action != &"AttemptDribble" and current_action != &"Pass":
		line_lateral_force = _cached_defensive_lateral * DEFENSIVE_LINE_SEPARATION_WEIGHT

	# 6. Touchline boundary avoidance steering force — deflects players safely inward when near edges
	var boundary_avoid_force: Vector2 = Vector2.ZERO
	if pitch_boundary != null:
		var pitch_half: Vector2 = pitch_boundary.pitch_size * 0.5
		var p_pos: Vector2 = player.global_position
		var touchline_dist_top: float = p_pos.y - (-pitch_half.y)
		var touchline_dist_bot: float = pitch_half.y - p_pos.y
		var touch_margin: float = 65.0
		if touchline_dist_top < touch_margin:
			var push_t: float = 1.0 - clampf(touchline_dist_top / touch_margin, 0.0, 1.0)
			boundary_avoid_force.y += push_t * 0.40
		elif touchline_dist_bot < touch_margin:
			var push_b: float = 1.0 - clampf(touchline_dist_bot / touch_margin, 0.0, 1.0)
			boundary_avoid_force.y -= push_b * 0.40

	# Sprint is expressed as intent, not the resolved is_sprinting — the
	# controller alone decides whether stamina actually allows it.
	# A press trigger is a moment, not a position: the whole value of spotting a
	# backward-facing carrier, a touchline trap or a heavy touch is arriving
	# before it passes. So the chasing presser commits to a sprint regardless of
	# distance, rather than jogging the first half of CHASE_RADIUS and only then
	# accelerating — by which point the trigger has usually expired.
	var chasing: bool = current_action == &"ChaseBall"
	player.wants_sprint = chasing and (distance > CHASE_RADIUS * 0.5 or _press_trigger_commits(chasing))
	var sacchi_force: Vector2 = Vector2.ZERO
	# Off-ball only: ambient team-shape nudge applied only when team spread exceeds SACCHI_MAX_OUTFIELD_SPREAD.
	# All on-ball / urgent actions (ChaseBall, PanicClear, AttemptShoot, AttemptDribble, Pass) are strictly exempt.
	var applies_to_ball_actions: bool = current_action != &"ChaseBall" \
			and current_action != &"PanicClear" and current_action != &"AttemptShoot" \
			and current_action != &"AttemptDribble" and current_action != &"Pass"
	if applies_to_ball_actions and (role == Role.OUTFIELD_DEFENDER or role == Role.OUTFIELD_MIDFIELDER or role == Role.OUTFIELD_ATTACKER):
		var world: MatchWorldModel = MatchWorldModel.instance
		if world != null:
			var com_x: float = world.team_com_x[player.team]
			var att_x: float = world.team_att_x[player.team]
			var def_x: float = world.team_def_x[player.team]
			var L_team: float = absf(att_x - def_x)
			if L_team > SACCHI_MAX_OUTFIELD_SPREAD:
				var p_x: float = player.global_position.x
				var excess: float = L_team - SACCHI_MAX_OUTFIELD_SPREAD
				var f_mag: float = -clampf(excess / 300.0, 0.0, 1.0) * SACCHI_MAX_FORCE * signf(p_x - com_x)
				sacchi_force = Vector2(f_mag, 0.0)

	var raw_intent: Vector2 = (seek_force + sep_force + spring_force + assist_force + line_lateral_force + boundary_avoid_force + sacchi_force).limit_length(1.0)
	var blended_intent: Vector2 = _apply_intent_blend(raw_intent)

	if _trace_this_tick:
		print("[Steer] %s action=%s seek_target=%s offset=%s distance=%.1f deflection=%.2f  seek=%s sep=%s spring=%s assist=%s line_lat=%s bnd=%s sacchi=%s  raw_intent=%s(len=%.2f) blended=%s(len=%.2f)" % [
			player.name, current_action, seek_target, offset, distance, deflection,
			seek_force, sep_force, spring_force, assist_force, line_lateral_force, boundary_avoid_force, sacchi_force,
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

	# --- Goalkeeper possession / distribution ---
	if player.state_factory != null and player.state_factory.current_state_name == PlayerState.GOALKEEPER_HOLD:
		return Vector2.ZERO

	if pitch_boundary != null:
		var catch_ball: Pseudo3DBall = player.get_ball_in_catch_range()
		if catch_ball != null and player.state_factory != null:
			player.state_factory.transition_to(PlayerState.GOALKEEPER_HOLD)
			current_action = &"GoaliePatrol"
			return Vector2.ZERO

	if (ball.possessor == player or player.get_ball_in_foot_range() != null) and pitch_boundary != null:
		var target_player: HeavyPlayerController = _find_best_pass_target()
		var clear_dir: Vector2 = _get_attack_direction()
		var is_pass_to_teammate: bool = false
		if target_player != null and is_instance_valid(target_player):
			var lead_pos: Vector2 = target_player.global_position + target_player.velocity * 0.3
			clear_dir = (lead_pos - ball.global_position).normalized()
			is_pass_to_teammate = true
		else:
			var spread: float = _rng.randf_range(-0.25, 0.25)
			clear_dir = Vector2(_get_attack_sign(), spread).normalized()

		var kick_speed: float = 420.0
		ball.apply_kick(clear_dir * kick_speed, 60.0, player)
		player.show_action_text("CLEAR" if not is_pass_to_teammate else "PASS")
		GameEvents.ball_struck.emit(player, kick_speed, 0.7, false)
		MatchStatsTracker.record_pass_attempt(player, is_pass_to_teammate)
		current_action = &"GoaliePatrol"
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

	var pitch_in_dir: float = _get_attack_sign()
	var to_ball: Vector2 = ball_pos - goal_centre

	if to_ball.is_zero_approx() or to_ball.x * pitch_in_dir <= 0.0:
		return goal_centre + Vector2(pitch_in_dir * GOALIE_ARC_MIN_DIST, 0.0)

	var bisector_dir: Vector2 = to_ball.normalized()
	var dist_to_ball: float = to_ball.length()

	# Close-range arc: 40px when ball is far (>600px), up to 90px when close
	# (<200px) — narrows the shooting angle as danger approaches the box.
	var t_dist: float = clampf((dist_to_ball - 200.0) / 400.0, 0.0, 1.0)
	var arc_dist: float = clampf(lerpf(GOALIE_ARC_MAX_DIST, GOALIE_ARC_MIN_DIST, t_dist), GOALIE_ARC_MIN_DIST, GOALIE_ARC_MAX_DIST)

	# Sweeper push: with the ball deep in the attacking half, roam out toward
	# the team's shared defensive line instead of camping the 6-yard box.
	# Gated on ball distance so a sudden counter (ball distance drops below
	# GOALIE_SWEEPER_BALL_DIST) immediately hands positioning back to the
	# close-range arc above, retreating the keeper toward goal.
	if dist_to_ball > GOALIE_SWEEPER_BALL_DIST:
		var world: MatchWorldModel = MatchWorldModel.instance
		if world != null:
			var line_depth: float = absf(world.defensive_line_x[player.team] - goal_centre.x)
			var sweep_dist: float = clampf(line_depth - GOALIE_SWEEPER_LINE_MARGIN, GOALIE_ARC_MIN_DIST, GOALIE_SWEEPER_MAX_DIST)
			arc_dist = maxf(arc_dist, sweep_dist)

	var patrol_pos: Vector2 = goal_centre + bisector_dir * arc_dist

	# Constrain Y within the goal mouth height
	patrol_pos.y = clampf(patrol_pos.y, goal_centre.y - half_mouth, goal_centre.y + half_mouth)

	# Ensure X stays on the playing field side of the goal line, up to the
	# sweeper cap so the roam above isn't immediately clamped back down.
	if pitch_in_dir > 0.0:
		patrol_pos.x = clampf(patrol_pos.x, goal_centre.x + 35.0, goal_centre.x + GOALIE_SWEEPER_MAX_DIST)
	else:
		patrol_pos.x = clampf(patrol_pos.x, goal_centre.x - GOALIE_SWEEPER_MAX_DIST, goal_centre.x - 35.0)

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


func _steer_celebration(_delta: float) -> void:
	if player == null:
		return

	var scoring_team: int = GameManager.last_scoring_team
	var is_scoring_team: bool = (player.team == scoring_team)

	if is_scoring_team:
		if is_goalkeeper:
			var gk_target: Vector2 = formation_anchor
			var dist_sq: float = player.global_position.distance_squared_to(gk_target)
			if dist_sq > 400.0:
				player.movement_intent = (gk_target - player.global_position).normalized() * 0.4
			else:
				player.movement_intent = Vector2.ZERO
			player.wants_sprint = false
			return

		var world: MatchWorldModel = MatchWorldModel.instance
		var user_lead: HeavyPlayerController = null
		var scorer_lead: HeavyPlayerController = null

		if world != null:
			for p: HeavyPlayerController in world.player_nodes:
				if p != null and is_instance_valid(p) and p.team == scoring_team:
					if p.is_user_controlled:
						user_lead = p
						break
					elif scorer_lead == null and p.brain != null and not p.brain.is_goalkeeper:
						scorer_lead = p

		if user_lead != null:
			var angle: float = float(player_index) * 0.62831853
			var radius: float = 32.0 + float(player_index % 3) * 14.0
			var slot_target: Vector2 = user_lead.global_position + Vector2(cos(angle), sin(angle)) * radius
			var dist_sq: float = player.global_position.distance_squared_to(slot_target)
			if dist_sq > 625.0:
				player.movement_intent = (slot_target - player.global_position).normalized()
				player.wants_sprint = true
			else:
				player.movement_intent = Vector2.ZERO
				player.wants_sprint = false
				player.facing_direction = (user_lead.global_position - player.global_position).normalized()
		else:
			var half: Vector2 = (pitch_boundary.pitch_size * 0.5) if pitch_boundary != null else Vector2(800.0, 450.0)
			var centre: Vector2 = pitch_boundary.get_centre_spot() if pitch_boundary != null else Vector2.ZERO
			var defends_left: bool = (scoring_team == 0) if (pitch_boundary == null or not pitch_boundary.sides_flipped) else (scoring_team != 0)
			var attack_dir: float = 1.0 if defends_left else -1.0
			var y_sign: float = 1.0 if (scorer_lead != null and scorer_lead.global_position.y >= centre.y) else -1.0
			var corner_target: Vector2 = centre + Vector2(attack_dir * (half.x - 48.0), y_sign * (half.y - 48.0))

			var is_scorer: bool = (scorer_lead == player) or (ball != null and ball.last_touched_by == player)
			if is_scorer:
				var dist_sq: float = player.global_position.distance_squared_to(corner_target)
				if dist_sq > 1225.0:
					player.movement_intent = (corner_target - player.global_position).normalized()
					player.wants_sprint = true
				else:
					player.movement_intent = Vector2.ZERO
					player.wants_sprint = false
					player.facing_direction = Vector2(-attack_dir, -y_sign).normalized()
			else:
				var huddle_centre: Vector2 = scorer_lead.global_position if (scorer_lead != null and is_instance_valid(scorer_lead)) else corner_target
				var angle: float = float(player_index) * 0.62831853
				var radius: float = 30.0 + float(player_index % 3) * 12.0
				var slot_target: Vector2 = huddle_centre + Vector2(cos(angle), sin(angle)) * radius
				var dist_sq: float = player.global_position.distance_squared_to(slot_target)
				if dist_sq > 625.0:
					player.movement_intent = (slot_target - player.global_position).normalized()
					player.wants_sprint = true
				else:
					player.movement_intent = Vector2.ZERO
					player.wants_sprint = false
					player.facing_direction = (huddle_centre - player.global_position).normalized()
	else:
		var retreat_target: Vector2 = formation_anchor
		var dist_sq: float = player.global_position.distance_squared_to(retreat_target)
		if dist_sq > 900.0:
			player.movement_intent = (retreat_target - player.global_position).normalized() * 0.35
		else:
			player.movement_intent = Vector2.ZERO
		player.wants_sprint = false

