#!/usr/bin/env python3
"""
football_mcp.py — FastMCP server exposing football-domain diagnostics backed by the
local SQLite knowledge base at .agents/football_domain.db (built by
scripts/build_football_kb.py).

Tools:
    verify_kinematics          — check a velocity/acceleration/turn-rate value against
                                  human/physics plausibility bounds.
    audit_tactical_compactness — check a team's block depth/width against professional
                                  compactness bounds for a given phase.
    query_ifab_rule            — look up an IFAB Law by topic keyword.
    audit_action_transition    — check the elapsed time between two discrete player
                                  states against the minimum mechanical/physiological delay.
    diagnose_tactical_deviation — match a free-text description of AI misbehavior
                                  against known tactical anomaly patterns and return a
                                  grounded explanation plus the likely GDScript source.

Usage:
    py -3 tools/football_mcp.py
"""

from __future__ import annotations

import os
import sqlite3
import sys

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

from fastmcp import FastMCP

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DB_PATH = os.path.join(ROOT, ".agents", "football_domain.db")

mcp = FastMCP("football-expert")


def _connect() -> sqlite3.Connection:
    if not os.path.exists(DB_PATH):
        raise FileNotFoundError(
            f"{DB_PATH} not found. Run: py -3 scripts/build_football_kb.py"
        )
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


@mcp.tool
def verify_kinematics(
    metric_name: str,
    test_value: float,
    is_pixel_unit: bool = False,
    px_per_meter: float = 12.0,
) -> str:
    """Check a velocity/acceleration/turn-rate value against plausibility bounds.

    metric_name: one of player_top_speed, player_acceleration, player_deceleration,
        turn_rate_at_pace, shot_velocity, ground_pass_velocity, ball_grass_friction_decay,
        human_reaction_latency.
    test_value: the value to check, in the metric's native unit (or px/frame-style units
        if is_pixel_unit is true).
    is_pixel_unit: set true if test_value is in pixels/second (or px/s^2) and needs
        conversion via px_per_meter before comparison.
    """
    conn = _connect()
    try:
        row = conn.execute(
            "SELECT * FROM kinematic_benchmarks WHERE metric_name = ?", (metric_name,)
        ).fetchone()
    finally:
        conn.close()

    if row is None:
        known = _list_column(DB_PATH, "kinematic_benchmarks", "metric_name")
        return f"Unknown metric '{metric_name}'. Known metrics: {', '.join(known)}"

    value = test_value / px_per_meter if is_pixel_unit else test_value
    unit_note = f" (converted from {test_value} px-unit at {px_per_meter} px/m)" if is_pixel_unit else ""

    if row["min_value"] <= value <= row["max_value"]:
        return (
            f"OK: {metric_name} = {value:.3f} {row['unit']}{unit_note} is within the "
            f"plausible range [{row['min_value']}, {row['max_value']}] {row['unit']}. {row['notes']}"
        )
    direction = "above" if value > row["max_value"] else "below"
    bound = row["max_value"] if direction == "above" else row["min_value"]
    return (
        f"VIOLATION: {metric_name} = {value:.3f} {row['unit']}{unit_note} is {direction} the "
        f"plausible range [{row['min_value']}, {row['max_value']}] {row['unit']} "
        f"(off by {abs(value - bound):.3f} {row['unit']}). {row['notes']}"
    )


@mcp.tool
def audit_tactical_compactness(phase: str, block_length_m: float, block_width_m: float) -> str:
    """Audit a team's block depth/width in meters against professional compactness bounds.

    phase: one of high_press, mid_block, low_block, or any/general.
    """
    conn = _connect()
    try:
        depth_row = conn.execute(
            "SELECT * FROM tactical_benchmarks WHERE metric_name = 'block_depth'"
        ).fetchone()
        width_row = conn.execute(
            "SELECT * FROM tactical_benchmarks WHERE metric_name = 'block_width'"
        ).fetchone()
        line_row = conn.execute(
            "SELECT * FROM tactical_benchmarks WHERE phase = ?", (phase,)
        ).fetchone()
    finally:
        conn.close()

    lines: list[str] = [f"Compactness audit for phase '{phase}':"]

    if depth_row["min_value"] <= block_length_m <= depth_row["max_value"]:
        lines.append(f"  depth OK: {block_length_m}m within [{depth_row['min_value']}, {depth_row['max_value']}]m.")
    else:
        direction = "too deep (stretched)" if block_length_m > depth_row["max_value"] else "too shallow (compressed)"
        lines.append(
            f"  depth VIOLATION: {block_length_m}m is {direction} vs [{depth_row['min_value']}, {depth_row['max_value']}]m — "
            f"see tactical_anomaly_patterns.vertical_overextension if too deep."
        )

    if width_row["min_value"] <= block_width_m <= width_row["max_value"]:
        lines.append(f"  width OK: {block_width_m}m within [{width_row['min_value']}, {width_row['max_value']}]m.")
    else:
        direction = "too wide" if block_width_m > width_row["max_value"] else "too narrow"
        lines.append(
            f"  width VIOLATION: {block_width_m}m is {direction} vs [{width_row['min_value']}, {width_row['max_value']}]m."
        )

    if line_row is not None:
        lines.append(
            f"  reference line height for '{phase}': [{line_row['min_value']}, {line_row['max_value']}]m from own goal line."
        )

    return "\n".join(lines)


@mcp.tool
def query_ifab_rule(topic: str) -> str:
    """Retrieve IFAB Law text matching a topic keyword (e.g. 'offside', 'dogso', 'penalty', 'throw-in')."""
    conn = _connect()
    try:
        rows = conn.execute(
            "SELECT * FROM ifab_rules WHERE topic LIKE ? OR law_number LIKE ? OR rule_text LIKE ?",
            (f"%{topic}%", f"%{topic}%", f"%{topic}%"),
        ).fetchall()
    finally:
        conn.close()

    if not rows:
        known = _list_column(DB_PATH, "ifab_rules", "topic")
        return f"No IFAB rule matched '{topic}'. Known topics: {', '.join(known)}"

    return "\n\n".join(f"{r['law_number']} ({r['topic']}): {r['rule_text']}" for r in rows)


@mcp.tool
def audit_action_transition(previous_action: str, current_action: str, time_delta_sec: float) -> str:
    """Check whether the elapsed time between two discrete player states respects the
    minimum mechanical/physiological delay between them."""
    conn = _connect()
    try:
        row = conn.execute(
            "SELECT * FROM transition_latencies WHERE previous_action = ? AND current_action = ?",
            (previous_action, current_action),
        ).fetchone()
    finally:
        conn.close()

    if row is None:
        return (
            f"No recorded minimum latency for transition '{previous_action}' -> '{current_action}'. "
            f"Consider adding it to transition_latencies in scripts/build_football_kb.py."
        )

    if time_delta_sec >= row["min_delay_sec"]:
        return (
            f"OK: {previous_action} -> {current_action} took {time_delta_sec:.3f}s, "
            f">= minimum {row['min_delay_sec']}s. {row['notes']}"
        )
    return (
        f"VIOLATION: {previous_action} -> {current_action} took only {time_delta_sec:.3f}s, "
        f"below the minimum {row['min_delay_sec']}s ({row['min_delay_sec'] - time_delta_sec:.3f}s too fast). "
        f"{row['notes']}"
    )


@mcp.tool
def diagnose_tactical_deviation(observed_behavior: str, phase: str = "general") -> str:
    """Match a free-text description of match-AI misbehavior against known tactical
    anomaly patterns and return a grounded explanation citing the likely GDScript source.

    This is a keyword-overlap match against a small, hand-curated table — it is a
    starting hypothesis to investigate, not a certain diagnosis."""
    conn = _connect()
    try:
        rows = conn.execute("SELECT * FROM tactical_anomaly_patterns").fetchall()
    finally:
        conn.close()

    query_words = set(observed_behavior.lower().split())
    scored: list[tuple[int, sqlite3.Row]] = []
    for row in rows:
        haystack = f"{row['pattern_key']} {row['description']}".lower().replace("_", " ")
        overlap = sum(1 for w in query_words if w in haystack)
        if overlap > 0:
            scored.append((overlap, row))

    if not scored:
        keys = _list_column(DB_PATH, "tactical_anomaly_patterns", "pattern_key")
        return (
            f"No known anomaly pattern matched '{observed_behavior}' (phase: {phase}). "
            f"Known patterns: {', '.join(keys)}. Describe the specific on-pitch symptom "
            f"(e.g. 'defenders don't track runs', 'team stretches out too much') for a match."
        )

    scored.sort(key=lambda t: t[0], reverse=True)
    best = scored[0][1]
    return (
        f"Likely pattern: {best['pattern_key']} (phase: {phase})\n"
        f"(A) Real-world expectation: {best['real_world_expectation']}\n"
        f"(B) Observed deviation: {best['description']}\n"
        f"(C) Likely GDScript source: {best['likely_gdscript_source']}\n"
        f"This is a hypothesis from a small curated pattern table — confirm against the "
        f"actual code before changing tuning values."
    )


def _list_column(db_path: str, table: str, column: str) -> list[str]:
    conn = sqlite3.connect(db_path)
    try:
        return [r[0] for r in conn.execute(f"SELECT {column} FROM {table}").fetchall()]
    finally:
        conn.close()


if __name__ == "__main__":
    mcp.run()
