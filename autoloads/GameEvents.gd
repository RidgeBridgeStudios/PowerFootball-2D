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
signal goal_scored(team: int)
signal ball_out_of_bounds(side: String)
signal foul_committed(fouler: Node, victim: Node)
signal match_ended(winner: int)
signal match_phase_changed(phase: int)

## --- Player events ---------------------------------------------------------

signal player_switched(new_player: Node)
signal stamina_depleted(player: Node)

## --- Contact events (feel, audio and stats hooks) --------------------------
## Extensions beyond the core match set: the audio and camera layers need to
## hear about contact, and routing it here keeps them decoupled from the FSM.

signal ball_struck(player: Node, speed: float, charge_ratio: float)
signal tackle_won(winner: Node, loser: Node)
signal aerial_contested(player: Node, clean: bool)
