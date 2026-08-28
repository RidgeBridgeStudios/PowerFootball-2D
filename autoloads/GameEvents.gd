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
