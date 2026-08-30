##
## GameEvents (Autoload singleton)
##
## The match-wide signal bus. Nothing in the game connects directly to anything
## else across system boundaries: the goal zone, referee, HUD, audio and camera
## all publish and subscribe here, which is what lets any of them be replaced or
## removed without touching the others.
##
## Rule of thumb: signals that describe *the match* live here. Signals that
## describe one entity's internals (a ball bouncing, a player's stamina bar)
## stay on that node.
##
## Depends on: nothing — this must stay dependency-free.
## Exposes: the signals below.
##

extends Node

## --- Match flow ------------------------------------------------------------

signal kickoff_started
signal kickoff_confirmed(team: int)
signal goal_scored(team: int)
signal ball_out_of_bounds(side: String)
signal foul_committed(fouler: Node, victim: Node, position: Vector2)
signal match_ended(winner: int)
signal match_phase_changed(phase: int)
signal half_time_reached

## --- Set pieces --------------------------------------------------------------

signal goal_kick_started(team: int, position: Vector2)
signal corner_kick_started(team: int, position: Vector2)
signal throw_in_started(team: int, position: Vector2)
signal free_kick_started(team: int, position: Vector2, is_direct: bool)
signal penalty_started(team: int, position: Vector2)
## The taker's kick/throw has been released — HUD and audio react to this
## rather than to the state transition directly.
signal set_piece_taken(taker: Node)
## HUD hint only: no wall-building AI is wired up yet (see SetPieceCoordinator).
signal defensive_wall_requested(free_kick_pos: Vector2)

## --- Player events ---------------------------------------------------------

signal player_switched(new_player: Node)
signal stamina_depleted(player: Node)
## Fired when a player's mood tier changes (not on every float nudge).
signal player_mood_changed(player: Node, tier: int)

## --- Contact events (feel, audio and stats hooks) --------------------------
## Extensions beyond the core match set: the audio and camera layers need to
## hear about contact, and routing it here keeps them decoupled from the FSM.

signal ball_struck(player: Node, speed: float, charge_ratio: float)
signal tackle_won(winner: Node, loser: Node)
signal aerial_contested(player: Node, clean: bool)

## --- Referee events ---------------------------------------------------------

## Fired when the referee decides to award a foul. HUD and audio react to this.
signal referee_awarded_foul(referee: Node, fouler: Node, victim: Node, position: Vector2)
## Fired when the referee decides to play on after a foul_committed event.
signal referee_played_on(referee: Node, fouler: Node, victim: Node, position: Vector2)
## Fired when the referee shows a yellow card. HUD reacts with a banner.
signal yellow_card_shown(player: Node, team: int)
## Fired when the referee shows a red card, straight or via second yellow.
signal red_card_shown(player: Node, team: int, is_second_yellow: bool)
## Fired when a sent-off player was the goalkeeper, so PitchScene can prompt an
## emergency substitution.
signal goalkeeper_sent_off(team: int)

## --- Manager events -------------------------------------------------------

## Fired by ManagerDirector when a mid-match formation shift occurs.
signal manager_formation_changed(team: int, new_formation: String)

## Fired by ManagerDirector._apply_formation() every time a team's shape is laid
## out — at bind time, at each kickoff, and after a tactical shift. `new_anchors`
## maps PlayerBrain.player_index (int) to that slot's world-space anchor
## (Vector2). PlayerBrain listens for this so a shape change is steered to on
## the next frame rather than at the brain's next staggered decision tick.
##
## Distinct from manager_formation_changed, which announces *that* the shape
## changed (for the touchline bubble and HUD) but carries only its name.
signal formation_anchors_changed(team: int, new_anchors: Dictionary)

## Fired by PitchScene._log_manager_stats() after every match ends.
## Career mode UI connects to this to refresh the manager profile screen.
signal manager_stats_updated(manager: ManagerData)

## --- Team management (pre-game screen and pause menu) -----------------------

## Emitted by PreGameScreen once the user clicks Kick Off; match start is
## deferred until this fires.
signal pregame_confirmed
## Emitted by PauseMenu when the player opens or closes the pause.
signal pause_opened
signal pause_closed
signal substitution_made(team: int, player_out_idx: int, player_in_idx: int)
signal formation_changed(team: int, new_formation: String)
signal lineup_changed(team: int)
