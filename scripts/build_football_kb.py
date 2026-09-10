#!/usr/bin/env python3
"""
build_football_kb.py — Builds .agents/football_domain.db, a local SQLite reference
database of kinematic/tactical benchmarks, IFAB laws, and known match-AI tactical
anomaly patterns. Consumed by tools/football_mcp.py.

Usage:
    py -3 scripts/build_football_kb.py
"""

from __future__ import annotations

import os
import sqlite3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, ".agents", "football_domain.db")

SCHEMA = """
DROP TABLE IF EXISTS kinematic_benchmarks;
DROP TABLE IF EXISTS tactical_benchmarks;
DROP TABLE IF EXISTS ifab_rules;
DROP TABLE IF EXISTS tactical_anomaly_patterns;
DROP TABLE IF EXISTS transition_latencies;

CREATE TABLE kinematic_benchmarks (
    metric_name TEXT PRIMARY KEY,
    min_value   REAL NOT NULL,
    max_value   REAL NOT NULL,
    unit        TEXT NOT NULL,
    notes       TEXT NOT NULL
);

CREATE TABLE tactical_benchmarks (
    metric_name TEXT PRIMARY KEY,
    min_value   REAL NOT NULL,
    max_value   REAL NOT NULL,
    unit        TEXT NOT NULL,
    phase       TEXT NOT NULL,
    notes       TEXT NOT NULL
);

CREATE TABLE ifab_rules (
    law_number TEXT NOT NULL,
    topic      TEXT NOT NULL,
    rule_text  TEXT NOT NULL,
    PRIMARY KEY (law_number, topic)
);

CREATE TABLE tactical_anomaly_patterns (
    pattern_key             TEXT PRIMARY KEY,
    description             TEXT NOT NULL,
    real_world_expectation  TEXT NOT NULL,
    likely_gdscript_source  TEXT NOT NULL
);

CREATE TABLE transition_latencies (
    previous_action TEXT NOT NULL,
    current_action  TEXT NOT NULL,
    min_delay_sec   REAL NOT NULL,
    notes           TEXT NOT NULL,
    PRIMARY KEY (previous_action, current_action)
);
"""

# (metric_name, min, max, unit, notes)
# Ranges compiled from public sports-science/tracking-data literature (elite outfield
# players). Treat as plausibility bounds for tuning, not hard physical laws.
KINEMATIC_BENCHMARKS: list[tuple[str, float, float, str, str]] = [
    ("player_top_speed", 5.5, 10.3, "m/s", "Full-match top speed range; 10.3 m/s (~37 km/h) is an elite sprinter ceiling."),
    ("player_acceleration", 1.5, 4.5, "m/s^2", "0-10m burst acceleration range from a standing/jogging start."),
    ("player_deceleration", 2.5, 6.5, "m/s^2", "Braking/plant deceleration when stopping or checking a run."),
    ("turn_rate_at_pace", 90.0, 220.0, "deg/s", "Achievable turn rate; inversely scaled by current sprint speed — near-full-speed turns are far slower than a standing turn."),
    ("shot_velocity", 18.0, 36.0, "m/s", "Struck-ball speed off the boot, ~65-130 km/h."),
    ("ground_pass_velocity", 8.0, 22.0, "m/s", "Ground pass speed, ~29-79 km/h."),
    ("ball_grass_friction_decay", 0.20, 0.45, "m/s^2", "Rolling ball deceleration on natural grass."),
    ("human_reaction_latency", 0.15, 0.25, "s", "Simple visual reaction time for trained athletes."),
]

# (metric_name, min, max, unit, phase, notes)
TACTICAL_BENCHMARKS: list[tuple[str, float, float, str, str, str]] = [
    ("pitch_length", 105.0, 105.0, "m", "any", "IFAB-recommended pitch length for international matches."),
    ("pitch_width", 68.0, 68.0, "m", "any", "IFAB-recommended pitch width for international matches."),
    ("high_block_line", 55.0, 75.0, "m", "high_press", "Defensive line distance from own goal line during a high press."),
    ("mid_block_line", 35.0, 50.0, "m", "mid_block", "Defensive line distance from own goal line in a mid block."),
    ("low_block_line", 18.0, 32.0, "m", "low_block", "Defensive line distance from own goal line in a low block."),
    ("block_depth", 22.0, 35.0, "m", "any", "Vertical compactness: distance between the back line and the highest outfield line."),
    ("block_width", 36.0, 52.0, "m", "any", "Horizontal compactness of the outfield shape."),
]

# (law_number, topic, rule_text)
IFAB_RULES: list[tuple[str, str, str]] = [
    ("Law 11", "offside_freeze_frame",
     "Offside position and offence are judged at the exact moment the ball is played (touched/played) "
     "by a teammate, not when it is received. There is no offside offence directly from a goal kick, "
     "throw-in, or corner kick."),
    ("Law 12", "dogso_penalty_area",
     "Since the 2019 revision: a genuine attempt to play the ball that denies an obvious goal-scoring "
     "opportunity (DOGSO) inside the offender's own penalty area is punished with a caution (yellow "
     "card) plus a penalty kick, not a sending-off. Holding, pulling, pushing, or a foul with no "
     "attempt to play the ball remains a red card even inside the box."),
    ("Law 13", "free_kick_wall_distance",
     "Opponents must retreat at least 9.15m (10 yards) from the ball at a free kick until it is in "
     "play, unless they are standing on their own goal line between the posts."),
    ("Law 14", "penalty_kick_restart",
     "All players other than the kicker and the defending goalkeeper must be inside the field of "
     "play, outside the penalty area, at least 9.15m (10 yards) from the penalty mark, and behind "
     "the ball, until it is kicked."),
    ("Law 15", "throw_in_restart",
     "The throw-in is taken from the point where the ball crossed the touchline, with part of both "
     "feet on or behind the line, delivered with both hands from behind and over the head."),
    ("Law 16", "goal_kick_restart",
     "The ball must be kicked from any point within the goal area and must leave the penalty area "
     "before being played by another player; opponents must remain outside the penalty area until "
     "the ball is in play."),
]

# (pattern_key, description, real_world_expectation, likely_gdscript_source)
TACTICAL_ANOMALY_PATTERNS: list[tuple[str, str, str, str]] = [
    ("loose_ball_passivity",
     "AI players hold their formation anchor instead of collapsing on a high-value loose ball.",
     "The nearest two or three players should break anchor discipline and converge, with urgency "
     "scaled by how dangerous/valuable the loose ball is (proximity to goal, transition risk).",
     "entities/player/PlayerBrain.gd (utility scoring), shared/PlayerRoleConfig.gd (anchor_weight)"),
    ("vertical_overextension",
     "Block depth exceeds ~38m, leaving excessive space between the midfield and back lines.",
     "The press line and back line should compress toward the 22-35m block-depth band to deny "
     "through-ball space between the lines.",
     "autoloads/MatchWorldModel.gd (defensive_line_x), shared/FormationAnchorMath.gd"),
    ("uncoordinated_press",
     "A single forward presses the ball carrier without the midfield line stepping up behind them, "
     "opening passing angles through the gap.",
     "A press trigger on the front line should raise the pressing aggression/step-up threshold for "
     "the line directly behind it, so the press moves as a coordinated block, not one isolated player.",
     "entities/player/PlayerBrain.gd (_resolve_defensive_duty / TRIGGER_PRESS), autoloads/MatchWorldModel.gd"),
    ("flat_defensive_line",
     "Defenders sit in a perfectly flat line with no diagonal cover or depth stagger against a "
     "through-ball runner.",
     "A covering defender should sit slightly deeper and inside of the engaging defender, cutting "
     "off the passing lane behind rather than mirroring the same depth.",
     "entities/player/PlayerBrain.gd, shared/FormationAnchorMath.gd"),
    ("carrier_crowding",
     "Off-ball teammates run directly toward the ball carrier instead of offering passing triangles.",
     "Support runners should offer at angles (splitting the half-space/central channel) rather than "
     "stacking on the same line or same channel as the carrier.",
     "shared/PassUtilityScorer.gd, shared/FormationAnchorMath.gd"),
]

# (previous_action, current_action, min_delay_sec, notes)
TRANSITION_LATENCIES: list[tuple[str, str, float, str]] = [
    ("carry", "pass", 0.05, "Minimal windup for a first-time or near-first-time pass out of a carry."),
    ("carry", "shot", 0.10, "Shot windup is shorter than a pass because momentum is already carrying through the ball."),
    ("tackle", "recovery", 0.20, "Post-tackle recovery/rebalancing before the tackler can re-engage."),
    ("recovery", "carry", 0.15, "Regaining balance before resuming a controlled dribble."),
    ("pass", "tackle", 0.15, "Reaction time floor to close down/intercept after an opponent's pass is released; should not undercut human_reaction_latency."),
    ("shot", "recovery", 0.30, "Follow-through and rebalancing after striking a shot."),
]


def build() -> None:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("PRAGMA journal_mode=WAL;")
        conn.executescript(SCHEMA)
        conn.executemany(
            "INSERT INTO kinematic_benchmarks (metric_name, min_value, max_value, unit, notes) VALUES (?, ?, ?, ?, ?)",
            KINEMATIC_BENCHMARKS,
        )
        conn.executemany(
            "INSERT INTO tactical_benchmarks (metric_name, min_value, max_value, unit, phase, notes) VALUES (?, ?, ?, ?, ?, ?)",
            TACTICAL_BENCHMARKS,
        )
        conn.executemany(
            "INSERT INTO ifab_rules (law_number, topic, rule_text) VALUES (?, ?, ?)",
            IFAB_RULES,
        )
        conn.executemany(
            "INSERT INTO tactical_anomaly_patterns (pattern_key, description, real_world_expectation, likely_gdscript_source) VALUES (?, ?, ?, ?)",
            TACTICAL_ANOMALY_PATTERNS,
        )
        conn.executemany(
            "INSERT INTO transition_latencies (previous_action, current_action, min_delay_sec, notes) VALUES (?, ?, ?, ?)",
            TRANSITION_LATENCIES,
        )
        conn.commit()
    finally:
        conn.close()

    print(f"[OK] Built {DB_PATH}")
    print(f"  kinematic_benchmarks:        {len(KINEMATIC_BENCHMARKS)} rows")
    print(f"  tactical_benchmarks:         {len(TACTICAL_BENCHMARKS)} rows")
    print(f"  ifab_rules:                  {len(IFAB_RULES)} rows")
    print(f"  tactical_anomaly_patterns:   {len(TACTICAL_ANOMALY_PATTERNS)} rows")
    print(f"  transition_latencies:        {len(TRANSITION_LATENCIES)} rows")


if __name__ == "__main__":
    build()
