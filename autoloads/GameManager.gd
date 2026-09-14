##
## GameManager (Autoload singleton)
##
## The scoreboard boundary between the career world and a resolved fixture: the
## two team side constants, the match phase the career UI observes, and the last
## simulated result (score, clock, duration).
##
## Before the manager-only pivot this was the full match-lifecycle choke point —
## a real-time phase machine, a per-frame clock, stoppage-time accumulation,
## set-piece placement state and a penalty-shootout controller, all broadcast
## through GameEvents. That machinery belonged to the archived real-time match
## layer, and went with it.
##
## What survives is exactly the surface the career world and QuickSimEngine read
## and write:
##   - QuickSimEngine.apply_to_match_stats_tracker() writes score, match_time and
##     simulated_match_time, and sets current_phase = MatchPhase.FULL_TIME.
##   - MatchStatsUI and MatchStatsTracker read score back for the full-time view.
##   - OptionsMenu sets the half duration via set_half_duration().
##
## Depends on: nothing.
## Exposes: TEAM_A, TEAM_B, MatchPhase, current_phase, score, match_time,
##          match_duration, half_duration_real_sec, simulated_match_time,
##          set_half_duration().
##

extends Node

## The only match-outcome states the career world observes: no fixture has been
## resolved yet, or the last one has. QuickSimEngine sets FULL_TIME once it has
## published a simulated result.
enum MatchPhase { PREGAME, FULL_TIME }

const TEAM_A: int = 0
const TEAM_B: int = 1

## Simulated 90-minute match duration (5400s). The simulated clock runs 0..5400
## and is published wholesale by QuickSimEngine at full time.
const SIMULATED_MATCH_DURATION: float = 90.0 * 60.0  # 5400.0s

var current_phase: MatchPhase = MatchPhase.PREGAME
## [team_a, team_b]
var score: Array[int] = [0, 0]
## Seconds elapsed in the match.
var match_time: float = 0.0
## Real seconds per 45-minute half (default: 150.0s for a 5-minute full match).
var half_duration_real_sec: float = 150.0
## Full-time whistle in real seconds (synchronized to 2.0 * half_duration_real_sec).
var match_duration: float = 300.0
## Simulated match clock in in-game seconds (0.0 to 5400.0).
var simulated_match_time: float = 0.0


func set_half_duration(real_sec: float) -> void:
	half_duration_real_sec = maxf(real_sec, 10.0)
	match_duration = half_duration_real_sec * 2.0
