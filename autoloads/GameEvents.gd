##
## GameEvents (Autoload singleton)
##
## The signal bus. Nothing in the game connects directly to anything else across
## system boundaries: systems publish and subscribe here, which is what lets any
## of them be replaced or removed without touching the others.
##
## Rule of thumb: signals that describe *a career or a match outcome* live here.
## Signals that describe one entity's internals stay on that node.
##
## Before the manager-only pivot this file carried the whole real-time match
## vocabulary — kickoff and set-piece flow, referee calls, contact/telemetry
## events, momentum and urgency scalar broadcasts, game-crunch narrative hooks.
## Every one of those emitters was part of the archived 22-player match layer,
## so those signals were removed with it. What remains is the career world's own
## event bus, plus the two team-management signals the Manager Mode tactics
## screen raises.
##
## Depends on: WorldEvent (shared/career) for one signal parameter type. Keep it
##             otherwise dependency-free.
## Exposes: the signals below.
##

extends Node

## --- Team management (Manager Mode tactics screen) --------------------------

## Fired by TacticsPanel when the user commits a new formation or lineup, so an
## open panel can refresh without polling.
signal formation_changed(team: int, new_formation: String)
signal lineup_changed(team: int)

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
## Fired when the async Continue loop starts.
signal career_continue_started()
## Fired when the async Continue loop stops (cancelled or reached event).
signal career_continue_stopped(reason: String)
## Fired when the continue simulation speed multiplier changes.
signal career_speed_changed(speed: int)
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
