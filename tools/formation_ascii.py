#!/usr/bin/env python3
"""
formation_ascii.py — Terminal ASCII Tactical Pitch & Formation Spacing Renderer.

Renders high-resolution terminal ASCII pitch diagrams illustrating 11-player
spatial anchor distributions across match tactical phases:
- IN_POSSESSION (+attack line push & stretch)
- OUT_OF_POSSESSION (-defense line retreat & compression)
- TRANSITION (neutral base anchor layout)

Calculates line depth, horizontal width, and pairwise spacing metrics across
standard formations (4-4-2, 4-3-3, 3-5-2, 4-2-3-1, 5-3-2).

Usage:
    python tools/formation_ascii.py [--formation 4-4-2] [--phase IN_POSSESSION] [--all]
"""

from __future__ import annotations

import argparse
import math
import sys
from typing import Dict, List, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

# Base pitch dimension constants matching Godot engine
PITCH_W = 1920.0
PITCH_H = 1080.0
HALF_W = PITCH_W * 0.5
HALF_H = PITCH_H * 0.5

FORMATIONS = {
    "4-4-2": [
        ("GK", -750.0, 0.0, "GK"),
        ("LB", -520.0, -320.0, "DEF"),
        ("CB", -550.0, -120.0, "DEF"),
        ("CB", -550.0, 120.0, "DEF"),
        ("RB", -520.0, 320.0, "DEF"),
        ("LM", -100.0, -340.0, "MID"),
        ("CM", -150.0, -100.0, "MID"),
        ("CM", -150.0, 100.0, "MID"),
        ("RM", -100.0, 340.0, "MID"),
        ("ST", 500.0, -80.0, "ATT"),
        ("ST", 500.0, 80.0, "ATT"),
    ],
    "4-3-3": [
        ("GK", -750.0, 0.0, "GK"),
        ("LB", -520.0, -320.0, "DEF"),
        ("CB", -550.0, -120.0, "DEF"),
        ("CB", -550.0, 120.0, "DEF"),
        ("RB", -520.0, 320.0, "DEF"),
        ("DM", -250.0, 0.0, "MID"),
        ("CM", -50.0, -150.0, "MID"),
        ("CM", -50.0, 150.0, "MID"),
        ("LW", 400.0, -340.0, "ATT"),
        ("RW", 400.0, 340.0, "ATT"),
        ("ST", 550.0, 0.0, "ATT"),
    ],
    "3-5-2": [
        ("GK", -750.0, 0.0, "GK"),
        ("CB", -550.0, -200.0, "DEF"),
        ("CB", -570.0, 0.0, "DEF"),
        ("CB", -550.0, 200.0, "DEF"),
        ("LWB", -150.0, -380.0, "MID"),
        ("DM", -250.0, 0.0, "MID"),
        ("CM", -50.0, -120.0, "MID"),
        ("CM", -50.0, 120.0, "MID"),
        ("RWB", -150.0, 380.0, "MID"),
        ("ST", 480.0, -100.0, "ATT"),
        ("ST", 480.0, 100.0, "ATT"),
    ],
    "4-2-3-1": [
        ("GK", -750.0, 0.0, "GK"),
        ("LB", -520.0, -320.0, "DEF"),
        ("CB", -550.0, -120.0, "DEF"),
        ("CB", -550.0, 120.0, "DEF"),
        ("RB", -520.0, 320.0, "DEF"),
        ("DM", -280.0, -120.0, "MID"),
        ("DM", -280.0, 120.0, "MID"),
        ("LAM", 150.0, -280.0, "MID"),
        ("CAM", 180.0, 0.0, "MID"),
        ("RAM", 150.0, 280.0, "MID"),
        ("ST", 550.0, 0.0, "ATT"),
    ],
    "5-3-2": [
        ("GK", -750.0, 0.0, "GK"),
        ("LWB", -400.0, -360.0, "DEF"),
        ("CB", -560.0, -180.0, "DEF"),
        ("CB", -580.0, 0.0, "DEF"),
        ("CB", -560.0, 180.0, "DEF"),
        ("RWB", -400.0, 360.0, "DEF"),
        ("CM", -150.0, -160.0, "MID"),
        ("CM", -200.0, 0.0, "MID"),
        ("CM", -150.0, 160.0, "MID"),
        ("ST", 480.0, -90.0, "ATT"),
        ("ST", 480.0, 90.0, "ATT"),
    ]
}

PHASE_PUSH = {
    "IN_POSSESSION": 0.08,
    "OUT_OF_POSSESSION": -0.06,
    "TRANSITION": 0.0
}

ROLE_SENSITIVITY = {
    "GK": 0.15,
    "DEF": 0.60,
    "MID": 1.00,
    "ATT": 1.30
}


def calculate_phase_positions(
    formation_name: str,
    phase: str,
    ball_x: float = 0.0,
    ball_y: float = 0.0,
    ball_weight: float = 0.25
) -> list[tuple[str, float, float, str]]:
    slots = FORMATIONS.get(formation_name, FORMATIONS["4-4-2"])
    push = PHASE_PUSH.get(phase, 0.0)

    dynamic_players = []
    for role_name, base_x, base_y, cat in slots:
        norm_base_x = base_x / HALF_W
        norm_base_y = base_y / HALF_H
        norm_ball_x = max(-1.0, min(1.0, ball_x / HALF_W))
        norm_ball_y = max(-1.0, min(1.0, ball_y / HALF_H))

        # Ball lerp
        pulled_x = norm_base_x + (norm_ball_x - norm_base_x) * ball_weight
        pulled_y = norm_base_y + (norm_ball_y - norm_base_y) * ball_weight

        # Phase push
        sens = ROLE_SENSITIVITY.get(cat, 1.0)
        final_norm_x = max(-1.0, min(1.0, pulled_x + push * sens))
        final_norm_y = max(-1.0, min(1.0, pulled_y))

        world_x = final_norm_x * HALF_W
        world_y = final_norm_y * HALF_H
        dynamic_players.append((role_name, world_x, world_y, cat))

    return dynamic_players


def render_ascii_pitch(formation_name: str, phase: str, players: list[tuple[str, float, float, str]]) -> str:
    # Grid dimensions: 65 cols x 25 rows
    cols = 65
    rows = 23
    grid = [[" " for _ in range(cols)] for _ in range(rows)]

    # Draw border
    for c in range(cols):
        grid[0][c] = "-"
        grid[rows - 1][c] = "-"
    for r in range(rows):
        grid[r][0] = "|"
        grid[r][cols - 1] = "|"

    # Halfway line
    mid_c = cols // 2
    for r in range(1, rows - 1):
        grid[r][mid_c] = ":"

    # Center circle
    mid_r = rows // 2
    grid[mid_r][mid_c] = "O"

    # Goals
    for r in range(mid_r - 2, mid_r + 3):
        grid[r][0] = "#"
        grid[r][cols - 1] = "#"

    # Place players
    # Map world X [-HALF_W, HALF_W] -> [2, cols-3]
    # Map world Y [-HALF_H, HALF_H] -> [2, rows-3]
    for role, wx, wy, _cat in players:
        gx = int(round(2 + ((wx + HALF_W) / PITCH_W) * (cols - 5)))
        gy = int(round(2 + ((wy + HALF_H) / PITCH_H) * (rows - 5)))
        gx = max(1, min(cols - 3, gx))
        gy = max(1, min(rows - 2, gy))

        # Put 2-letter role tag
        tag = role[:2].upper()
        if len(tag) == 1:
            tag += " "
        grid[gy][gx] = tag[0]
        if gx + 1 < cols - 1:
            grid[gy][gx + 1] = tag[1]

    # Build ASCII string
    lines = []
    lines.append(f"\n[FORMATION: {formation_name} | PHASE: {phase}]")
    lines.append("+" + "-" * (cols - 2) + "+")
    for r in range(rows):
        lines.append("".join(grid[r]))
    lines.append("+" + "-" * (cols - 2) + "+")

    # Spacing Analytics
    defenders = [p for p in players if p[3] == "DEF"]
    midfielders = [p for p in players if p[3] == "MID"]
    attackers = [p for p in players if p[3] == "ATT"]

    def_depth = sum(p[1] for p in defenders) / max(1, len(defenders))
    mid_depth = sum(p[1] for p in midfielders) / max(1, len(midfielders))
    att_depth = sum(p[1] for p in attackers) / max(1, len(attackers))

    lines.append(f" Tactical Lines Depth (X): DEF = {def_depth:+.0f}px | MID = {mid_depth:+.0f}px | ATT = {att_depth:+.0f}px")
    lines.append(f" Team Vertical Compactness: {att_depth - def_depth:.0f}px (Back-to-Front Spread)")
    return "\n".join(lines)


def display_all_phases(formation: str) -> None:
    print("=" * 70)
    print(f"       TACTICAL SPACING & FORMATION AUDIT: {formation}       ")
    print("=" * 70)

    for phase in ("IN_POSSESSION", "OUT_OF_POSSESSION", "TRANSITION"):
        players = calculate_phase_positions(formation, phase)
        diagram = render_ascii_pitch(formation, phase, players)
        print(diagram)
    print("=" * 70 + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Terminal ASCII Pitch & Formation Spacing Renderer")
    parser.add_argument("--formation", default="4-4-2", choices=list(FORMATIONS.keys()), help="Formation to render")
    parser.add_argument("--phase", default="IN_POSSESSION", choices=["IN_POSSESSION", "OUT_OF_POSSESSION", "TRANSITION"], help="Tactical phase")
    parser.add_argument("--all", action="store_true", help="Render all tactical phases for the formation")
    args = parser.parse_args()

    if args.all:
        display_all_phases(args.formation)
    else:
        players = calculate_phase_positions(args.formation, args.phase)
        print(render_ascii_pitch(args.formation, args.phase, players))

    return 0


if __name__ == "__main__":
    sys.exit(main())
