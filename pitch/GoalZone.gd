##
## GoalZone
##
## Trigger volume behind a goal mouth. It detects the ball crossing the line and
## reports it to GameManager; it does not know about the score, the HUD, or the
## restart. Everything downstream reacts to GameEvents.goal_scored.
##
## `defending_team` is the team whose net this is — a ball entering here scores
## for the *other* side.
##
## Depends on: CollisionLayers, GameManager.
## Exposes: signal via GameEvents.goal_scored, defending_team
##

class_name GoalZone
extends Area2D

## Team that defends this goal (0 or 1).
@export var defending_team: int = 0
## Ignores a second trigger while the ball is still inside the net.
@export var retrigger_lockout: float = 1.5

var _locked_until: float = 0.0


func _ready() -> void:
	# Only the ball layer matters here; players run through goal mouths freely.
	collision_layer = 0
	collision_mask = CollisionLayers.LAYER_BALL_PHYSICS
	monitoring = true
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	var ball := body as Pseudo3DBall
	if ball == null:
		return

	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _locked_until:
		return

	# A ball above the crossbar is over the end line: report out-of-bounds miss
	if ball.position_z > crossbar_height():
		_locked_until = now + retrigger_lockout
		var toucher: HeavyPlayerController = ball.last_touched_by
		var attacker_touched_last: bool = (toucher == null or toucher.team != defending_team)
		GameEvents.ball_out_of_bounds.emit("end_line_goal_kick" if attacker_touched_last else "end_line_corner")
		return

	_locked_until = now + retrigger_lockout

	var scoring_team: int = 1 - defending_team
	GameManager.register_goal(scoring_team, ball.last_touched_by)


## Height of the crossbar in pixels of pseudo-3D Z.
func crossbar_height() -> float:
	return 60.0

	# TODO: model the frame properly — a post/crossbar rebound (ball within a few
	# pixels of the goal edge) should bounce and emit a "woodwork" event for the
	# camera shake and crowd reaction, rather than counting or passing silently.
