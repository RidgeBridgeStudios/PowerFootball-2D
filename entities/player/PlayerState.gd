##
## PlayerState
##
## Abstract base for every player state. States are flyweights: one instance per
## player, created by PlayerStateFactory, receiving the player as an argument
## rather than storing scene references. Keeping them out of the scene tree means
## a state can never hold a stale node reference across a respawn.
##
## Contract:
##   enter(player)                    -> setup on entry
##   exit(player)                     -> teardown on exit
##   process(player, delta)           -> next state name, or &"" to stay
##   physics_process(player, delta)   -> movement / physics work for this tick
##
## Depends on: HeavyPlayerController.
## Exposes: the four lifecycle methods plus the shared transition helpers below.
##

class_name PlayerState
extends RefCounted

const IDLE: StringName = &"Idle"
const MOVE: StringName = &"Move"
const DRIBBLE: StringName = &"Dribble"
const CHARGE_KICK: StringName = &"ChargeKick"
const SHOT_LOCK: StringName = &"ShotLock"
const TACKLE: StringName = &"Tackle"
const AERIAL: StringName = &"Aerial"
const SET_PIECE_FREEZE: StringName = &"SetPieceFreeze"
const THROW_IN: StringName = &"ThrowIn"
const PENALTY_KICK: StringName = &"PenaltyKick"
const GOALKEEPER_DIVE: StringName = &"GoalkeeperDive"
const GOALKEEPER_HOLD: StringName = &"GoalkeeperHold"

## Ball height above which an aerial challenge becomes available.
const AERIAL_TRIGGER_HEIGHT: float = 10.0


func enter(_player: HeavyPlayerController) -> void:
	pass


func exit(_player: HeavyPlayerController) -> void:
	pass


## Returns the next state name, or &"" to remain in this state.
func process(_player: HeavyPlayerController, _delta: float) -> StringName:
	return &""


func physics_process(_player: HeavyPlayerController, _delta: float) -> void:
	pass


## Transitions available from any grounded, in-control state. Checked in
## priority order: an aerial ball beats a tackle, a tackle beats a kick.
func check_common_transitions(player: HeavyPlayerController) -> StringName:
	var aerial_ball: Pseudo3DBall = player.get_ball_in_aerial_range()
	if aerial_ball != null and aerial_ball.position_z > AERIAL_TRIGGER_HEIGHT:
		return AERIAL

	if wants(player, &"action_tackle") or player.wants_tackle:
		return TACKLE

	if wants(player, &"action_kick"):
		if player.get_ball_in_foot_range() != null:
			return CHARGE_KICK
		# Ball not at the player's feet — engage shot lock-on. ShotLockState
		# bails straight back out on its own next tick if no shootable ball is
		# within range, so no need to duplicate that search here.
		return SHOT_LOCK

	return &""


## Action reads are funnelled through here so CPU players never poll the
## keyboard. Brain-driven players express intent by setting flags on the
## controller instead.
## TODO: replace the is_user_controlled branch with an input-source object once
## PlayerBrain drives buttons as well as steering — it keeps local multiplayer
## and replays honest.
func wants(player: HeavyPlayerController, action: StringName) -> bool:
	if not player.is_user_controlled:
		return false
	return Input.is_action_pressed(action)


func just_wants(player: HeavyPlayerController, action: StringName) -> bool:
	if not player.is_user_controlled:
		return false
	return Input.is_action_just_pressed(action)
