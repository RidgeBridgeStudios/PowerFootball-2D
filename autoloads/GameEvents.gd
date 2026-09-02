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

signal match_intro_started
signal match_intro_finished
signal match_intro_skipped
signal kickoff_started
signal kickoff_confirmed(team: int)
## scorer is whoever last touched the ball before it crossed the line
## (Pseudo3DBall.last_touched_by at the moment of the goal) — null if
## unknown. scorer.team != team means an own goal. Existing 1-arg listeners
## still work unmodified: Godot drops trailing emitted args a callback
## doesn't declare (same convention as ball_struck's is_shot addition).
signal goal_scored(team: int, scorer: Node)
signal ball_out_of_bounds(side: String)
signal foul_committed(fouler: Node, victim: Node, position: Vector2)
signal match_ended(winner: int)
signal match_phase_changed(phase: int)
signal half_time_reached
signal half_time_started
signal half_time_ended
signal stoppage_time_announced(added_minutes: int, half: int)

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

## --- Penalty shootout --------------------------------------------------------

## Fired by PenaltyShootoutCoordinator once a single kick resolves (scored,
## saved, or wide). kick_index is that team's 0-based kick count so far —
## also the dot the HUD overlay should fill in.
signal shootout_kick_result(team: int, kick_index: int, scored: bool)

## --- Player events ---------------------------------------------------------

signal player_switched(new_player: Node)
signal stamina_depleted(player: Node)
## Fired when a player's mood tier changes (not on every float nudge).
signal player_mood_changed(player: Node, tier: int)

## --- Contact events (feel, audio and stats hooks) --------------------------
## Extensions beyond the core match set: the audio and camera layers need to
## hear about contact, and routing it here keeps them decoupled from the FSM.

## is_shot distinguishes a shooting strike (ShotLockState, PenaltyKickState, or a
## held ChargeKickState release) from a pass/throw (a tapped ChargeKickState
## release or ThrowInState) — MatchStatsTracker uses it to route shot vs pass
## counting. Existing 3-arg listeners (OffsideDetector, MoodSystem) still work
## unmodified: Godot drops trailing emitted args a callback doesn't declare.
signal ball_struck(player: Node, speed: float, charge_ratio: float, is_shot: bool)
signal tackle_won(winner: Node, loser: Node)
signal aerial_contested(player: Node, clean: bool)
## Fired by ChargeKickState when a held, high-charge shot is released — the
## hit-stop hook. GameManager freezes the clock briefly on this.
signal powerful_shot_landed(shooter: HeavyPlayerController, speed: float, ratio: float)

## Fired 0.3s before a predicted interception
signal anticipatory_turnover_predicted(team: int)

## --- Telemetry & advanced analytics ------------------------------------------

signal pass_completed(passer: Node, receiver: Node, orig_pos: Vector2, dest_pos: Vector2, packed_count: int, xt_delta: float)
signal shot_taken(shooter: Node, orig_pos: Vector2, xg_val: float, psxg_val: float, is_on_target: bool)
signal defensive_action_logged(player: Node, action_type: StringName, pos: Vector2)
signal carry_completed(player: Node, start_pos: Vector2, end_pos: Vector2, is_progressive: bool, xt_delta: float)

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
## Fired by OffsideDetector when a player is caught offside.
## position is the offside player's world position at the moment
## of the call, used as the restart spot.
signal offside_called(offside_player: Node, defending_team: int, position: Vector2)

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

## --- Pressing (defensive trigger detection) --------------------------------

## Fired by MatchWorldModel whenever the active pressing trigger changes —
## once when a trigger arms (active=true) and once when it expires
## (active=false, trigger_type=MatchWorldModel.PressTrigger.NONE, carrier=null).
## trigger_type is a MatchWorldModel.PressTrigger enum value. carrier is the
## HeavyPlayerController the trigger concerns (nullable — a backward/square
## pass trigger names the kicker, since the receiver is not yet known at the
## moment the ball is struck). position is where the trigger was raised, for
## HUD/debug overlays. Consumers should react to this signal — or read
## MatchWorldModel.instance.press_trigger_active directly when they already
## have a reason to be looking — rather than polling every frame.
signal press_trigger_changed(active: bool, trigger_type: int, carrier: Node, position: Vector2)

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

## --- Macro match architecture (urgency, momentum, stage) --------------------
## Layer 2 (ManagerDirector) evaluates urgency and stage on a low-frequency
## tick and publishes scalars here; MatchWorldModel is the sole listener that
## caches them (team_urgency / team_momentum / current_match_stage), so every
## hot-path reader (PlayerBrain, PassUtilityScorer/FormationAnchorMath call
## sites) reads a cached float instead of re-deriving it. See
## POWERFOOTBALL_MASTER_VISION.md and AGENTS_ERRATA.md for the formulas.

## Fired by ManagerDirector roughly once per second when a team's computed
## Match Urgency changes by more than a small epsilon. urgency is [-1, 1]:
## negative = protecting a lead / playing safe, positive = chasing the game.
signal team_urgency_updated(team: int, urgency: float)
## Fired by MatchStatsTracker whenever its anti-snowball momentum accumulator
## for `team` changes by more than a small epsilon — either a discrete event
## impulse (shot on target, tackle won, goal conceded, ...) or a continuous
## decay tick catching up past the publish threshold. momentum is [-1, 1].
signal team_momentum_updated(team: int, momentum: float)
## Fired by GameManager when the match crosses a macro temporal stage
## boundary (see GameManager.MatchStage). stage is a GameManager.MatchStage
## value: 0 = Sizing-Up, 1 = Equilibrium, 2 = Transitions, 3 = Game-Crunch.
signal match_stage_changed(stage: int)

## Fired once per team, at most once per match, by ManagerDirector when that
## team is trailing by >= 1 goal at time_ratio >= GameManager.STAGE_3_FRACTION
## (Game-Crunch) — a discrete narrative event (Layer 4 tactical directive ->
## Layer 5 touchline reaction), NOT a third cached macro scalar alongside
## team_urgency_updated/team_momentum_updated above: there is no
## MatchWorldModel cache for this one, listen directly (PitchScene does, for
## the touchline shout — see its home-perspective-only convention in
## AGENTS_ERRATA.md). tactic_type is currently always &"ALL_OUT_ATTACK"; kept
## as a StringName rather than a bool so a second emergency tactic can be
## added later without a new signal.
signal emergency_tactics_triggered(team: int, tactic_type: StringName)

## Fired by GameManager when the simulation / playback speed scale is updated
## (e.g. during CPU vs CPU matches via speed slider / preset buttons / hotkeys).
signal simulation_speed_changed(speed: float)

## --- Goal replay system (Football Manager-style match highlights) -----------
signal goal_replays_toggled(enabled: bool)
signal replay_started(team: int, scorer: Node)
signal replay_ended

## --- Goal celebration system -----------------------------------------------
signal celebration_started(team: int, scorer: Node)
signal celebration_ended

## --- Career mode (Layer 4 club world) ---------------------------------------
## All NEW signals. Per AGENTS_ERRATA/ai-architect.md, adding a trailing
## parameter to an EXISTING signal breaks every under-declared listener, so the
## career layer never widens an existing signature — it only adds its own.

## Fired by CareerManager once a career is loaded or created and its state is
## ready to read. Career UI populates on this rather than in _ready(), since
## the autoload may still be restoring a slot when a scene enters the tree.
signal career_started(save_name: String, club_name: String)
## Fired once per simulated day as the Continue loop advances. iso_date is the
## new CareerDate in "YYYY-MM-DD" form.
signal career_day_advanced(iso_date: String)
## Fired when the Continue loop stops early because something needs the
## manager's attention. reason is a short display string.
signal career_advance_halted(reason: String)
## Fired for each item pushed into the inbox, so an open inbox screen can
## refresh without polling.
signal career_inbox_changed(unread_count: int, pending_decisions: int)
## Fired when the user's next fixture is today and the match is ready to start.
signal career_match_ready(home_team_index: int, away_team_index: int)
## Fired after a fixture the user played or simulated has been recorded.
signal career_result_recorded(home_score: int, away_score: int)
## Fired at each season rollover, after promotion/relegation and the archive.
signal career_season_ended(season_year: int, final_position: int)
## Fired when the board terminates the manager's contract.
signal career_manager_sacked(club_name: String, reason: String)
## Fired by WorldEventLog for every entry appended. PressOffice-driven UI and
## the club-world feed both listen rather than polling the log.
signal world_event_logged(event: WorldEvent)


