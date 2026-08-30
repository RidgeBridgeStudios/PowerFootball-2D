#!/usr/bin/env python3
"""
dump_match_frames.py — Visual Match Frame Exporter for Multimodal Agent Evaluation.

Simulates match tactical time-slices and exports top-down SVG frames showing:
- 22 player positions and shirt numbers
- Velocity/heading vectors
- Ball position, height, and trajectory vectors
- Pitch boundaries, penalty boxes, and goal mouths
- Passing lanes and defender occlusion corridors

Enables Gemini multimodal evaluation of spatial structure, pressing compaction,
and passing lane decisions.

Usage:
    python tools/dump_match_frames.py [--frames 5] [--output-dir match_frames]
"""

from __future__ import annotations

import argparse
import math
import os
import random
import sys
from typing import List, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUTPUT_DIR = os.path.join(ROOT, "match_frames")

PITCH_WIDTH = 1280.0
PITCH_HEIGHT = 720.0
PITCH_PADDING = 40.0


def render_svg_frame(
    frame_idx: int,
    time_sec: float,
    team_a_pos: list[tuple[float, float]],
    team_a_vel: list[tuple[float, float]],
    team_b_pos: list[tuple[float, float]],
    team_b_vel: list[tuple[float, float]],
    ball_pos: tuple[float, float],
    ball_vel: tuple[float, float],
    passing_lanes: list[tuple[tuple[float, float], tuple[float, float], bool]],
    score: tuple[int, int] = (0, 0),
) -> str:
    svg = []
    svg.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {PITCH_WIDTH} {PITCH_HEIGHT}" width="{int(PITCH_WIDTH)}" height="{int(PITCH_HEIGHT)}">')
    svg.append('  <defs>')
    svg.append('    <linearGradient id="grassGrad" x1="0%" y1="0%" x2="100%" y2="100%">')
    svg.append('      <stop offset="0%" stop-color="#1E4D2B"/>')
    svg.append('      <stop offset="100%" stop-color="#163A20"/>')
    svg.append('    </linearGradient>')
    svg.append('    <marker id="arrowA" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">')
    svg.append('      <path d="M 0 0 L 8 4 L 0 8 z" fill="#4DA3FF"/>')
    svg.append('    </marker>')
    svg.append('    <marker id="arrowB" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">')
    svg.append('      <path d="M 0 0 L 8 4 L 0 8 z" fill="#FF5C5C"/>')
    svg.append('    </marker>')
    svg.append('    <marker id="arrowBall" markerWidth="8" markerHeight="8" refX="6" refY="4" orient="auto">')
    svg.append('      <path d="M 0 0 L 8 4 L 0 8 z" fill="#FFD700"/>')
    svg.append('    </marker>')
    svg.append('  </defs>')

    # 1. Pitch Surface
    svg.append(f'  <!-- Pitch Surface -->')
    svg.append(f'  <rect width="{PITCH_WIDTH}" height="{PITCH_HEIGHT}" fill="url(#grassGrad)"/>')

    # Pitch boundary margins
    pw = PITCH_WIDTH - 2 * PITCH_PADDING
    ph = PITCH_HEIGHT - 2 * PITCH_PADDING
    cx = PITCH_WIDTH / 2.0
    cy = PITCH_HEIGHT / 2.0

    # 2. Pitch Markings (White lines)
    svg.append('  <!-- Pitch Lines -->')
    svg.append(f'  <rect x="{PITCH_PADDING}" y="{PITCH_PADDING}" width="{pw}" height="{ph}" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-opacity="0.8"/>')
    svg.append(f'  <line x1="{cx}" y1="{PITCH_PADDING}" x2="{cx}" y2="{PITCH_HEIGHT - PITCH_PADDING}" stroke="#FFFFFF" stroke-width="2.5" stroke-opacity="0.8"/>')
    svg.append(f'  <circle cx="{cx}" cy="{cy}" r="70" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-opacity="0.8"/>')
    svg.append(f'  <circle cx="{cx}" cy="{cy}" r="3" fill="#FFFFFF"/>')

    # Left Penalty Box & Goal
    svg.append(f'  <rect x="{PITCH_PADDING}" y="{cy - 120}" width="140" height="240" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-opacity="0.8"/>')
    svg.append(f'  <rect x="{PITCH_PADDING}" y="{cy - 60}" width="50" height="120" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-opacity="0.8"/>')
    svg.append(f'  <rect x="{PITCH_PADDING - 20}" y="{cy - 45}" width="20" height="90" fill="none" stroke="#E0E0E0" stroke-width="3"/>')

    # Right Penalty Box & Goal
    svg.append(f'  <rect x="{PITCH_WIDTH - PITCH_PADDING - 140}" y="{cy - 120}" width="140" height="240" fill="none" stroke="#FFFFFF" stroke-width="2.5" stroke-opacity="0.8"/>')
    svg.append(f'  <rect x="{PITCH_WIDTH - PITCH_PADDING - 50}" y="{cy - 60}" width="50" height="120" fill="none" stroke="#FFFFFF" stroke-width="2" stroke-opacity="0.8"/>')
    svg.append(f'  <rect x="{PITCH_WIDTH - PITCH_PADDING}" y="{cy - 45}" width="20" height="90" fill="none" stroke="#E0E0E0" stroke-width="3"/>')

    # 3. Passing Corridors
    svg.append('  <!-- Passing Lanes -->')
    for p_from, p_to, is_open in passing_lanes:
        color = "#2ECC71" if is_open else "#E74C3C"
        dash = "none" if is_open else "4,4"
        svg.append(f'  <line x1="{p_from[0]}" y1="{p_from[1]}" x2="{p_to[0]}" y2="{p_to[1]}" stroke="{color}" stroke-width="2" stroke-dasharray="{dash}" stroke-opacity="0.6"/>')

    # 4. Team A Players (Blue)
    svg.append('  <!-- Team A Players -->')
    for idx, (px, py) in enumerate(team_a_pos):
        vx, vy = team_a_vel[idx]
        v_mag = math.hypot(vx, vy)
        if v_mag > 5.0:
            scale = min(25.0, v_mag * 0.12)
            arr_x = px + (vx / v_mag) * scale
            arr_y = py + (vy / v_mag) * scale
            svg.append(f'  <line x1="{px}" y1="{py}" x2="{arr_x}" y2="{arr_y}" stroke="#4DA3FF" stroke-width="2" marker-end="url(#arrowA)"/>')

        # Shadow & Body
        svg.append(f'  <ellipse cx="{px}" cy="{py + 5}" rx="9" ry="4" fill="#000000" fill-opacity="0.35"/>')
        fill_color = "#FFD700" if idx == 0 else "#2A70C0"  # GK gold
        svg.append(f'  <circle cx="{px}" cy="{py}" r="8.5" fill="{fill_color}" stroke="#FFFFFF" stroke-width="1.5"/>')
        svg.append(f'  <text x="{px}" y="{py + 3.5}" font-size="8" font-family="sans-serif" font-weight="bold" fill="#FFFFFF" text-anchor="middle">{idx+1}</text>')

    # 5. Team B Players (Red)
    svg.append('  <!-- Team B Players -->')
    for idx, (px, py) in enumerate(team_b_pos):
        vx, vy = team_b_vel[idx]
        v_mag = math.hypot(vx, vy)
        if v_mag > 5.0:
            scale = min(25.0, v_mag * 0.12)
            arr_x = px + (vx / v_mag) * scale
            arr_y = py + (vy / v_mag) * scale
            svg.append(f'  <line x1="{px}" y1="{py}" x2="{arr_x}" y2="{arr_y}" stroke="#FF5C5C" stroke-width="2" marker-end="url(#arrowB)"/>')

        # Shadow & Body
        svg.append(f'  <ellipse cx="{px}" cy="{py + 5}" rx="9" ry="4" fill="#000000" fill-opacity="0.35"/>')
        fill_color = "#FFD700" if idx == 0 else "#D03030"  # GK gold
        svg.append(f'  <circle cx="{px}" cy="{py}" r="8.5" fill="{fill_color}" stroke="#FFFFFF" stroke-width="1.5"/>')
        svg.append(f'  <text x="{px}" y="{py + 3.5}" font-size="8" font-family="sans-serif" font-weight="bold" fill="#FFFFFF" text-anchor="middle">{idx+1}</text>')

    # 6. Ball
    bx, by = ball_pos
    bvx, bvy = ball_vel
    bv_mag = math.hypot(bvx, bvy)
    if bv_mag > 10.0:
        barr_x = bx + (bvx / bv_mag) * min(35.0, bv_mag * 0.1)
        barr_y = by + (bvy / bv_mag) * min(35.0, bv_mag * 0.1)
        svg.append(f'  <line x1="{bx}" y1="{by}" x2="{barr_x}" y2="{barr_y}" stroke="#FFD700" stroke-width="2" marker-end="url(#arrowBall)"/>')

    svg.append(f'  <ellipse cx="{bx}" cy="{by + 3}" rx="6" ry="3" fill="#000000" fill-opacity="0.4"/>')
    svg.append(f'  <circle cx="{bx}" cy="{by}" r="5.5" fill="#FFFFFF" stroke="#222222" stroke-width="1.5"/>')

    # 7. Match Overlay Header
    svg.append('  <!-- Match Info Overlay -->')
    svg.append(f'  <rect x="20" y="15" width="260" height="40" rx="6" fill="#000000" fill-opacity="0.65"/>')
    svg.append(f'  <text x="35" y="32" font-size="12" font-family="sans-serif" font-weight="bold" fill="#4DA3FF">TEAM A  {score[0]} - {score[1]}  TEAM B</text>')
    svg.append(f'  <text x="35" y="47" font-size="10" font-family="sans-serif" fill="#CCCCCC">Frame #{frame_idx} | t = {time_sec:.1f}s | Ball Vel: {bv_mag:.0f}px/s</text>')

    svg.append('</svg>')
    return "\n".join(svg)


def generate_simulated_match_frames(num_frames: int = 5, output_dir: str = DEFAULT_OUTPUT_DIR) -> list[str]:
    os.makedirs(output_dir, exist_ok=True)
    generated_files = []

    # Initial positions
    cx, cy = PITCH_WIDTH / 2.0, PITCH_HEIGHT / 2.0

    team_a_base = [
        (100.0, cy),  # GK
        (260.0, cy - 180.0), (280.0, cy - 60.0), (280.0, cy + 60.0), (260.0, cy + 180.0),  # DEF
        (460.0, cy - 160.0), (480.0, cy - 50.0), (480.0, cy + 50.0), (460.0, cy + 160.0),  # MID
        (620.0, cy - 60.0), (620.0, cy + 60.0),  # FWD
    ]

    team_b_base = [
        (PITCH_WIDTH - 100.0, cy),  # GK
        (PITCH_WIDTH - 260.0, cy - 180.0), (PITCH_WIDTH - 280.0, cy - 60.0), (PITCH_WIDTH - 280.0, cy + 60.0), (PITCH_WIDTH - 260.0, cy + 180.0),  # DEF
        (PITCH_WIDTH - 460.0, cy - 160.0), (PITCH_WIDTH - 480.0, cy - 50.0), (PITCH_WIDTH - 480.0, cy + 50.0), (PITCH_WIDTH - 460.0, cy + 160.0),  # MID
        (PITCH_WIDTH - 620.0, cy - 60.0), (PITCH_WIDTH - 620.0, cy + 60.0),  # FWD
    ]

    for f_idx in range(num_frames):
        t_sec = f_idx * 2.5

        # Dynamic drift toward ball
        ball_x = cx + math.sin(f_idx * 0.8) * 200.0
        ball_y = cy + math.cos(f_idx * 0.9) * 140.0
        ball_vel = (math.cos(f_idx * 0.8) * 160.0, -math.sin(f_idx * 0.9) * 110.0)

        # Team A positions with drift
        team_a_pos = []
        team_a_vel = []
        for idx, (bx, by) in enumerate(team_a_base):
            drift_x = (ball_x - bx) * 0.25 + random.uniform(-10.0, 10.0)
            drift_y = (ball_y - by) * 0.25 + random.uniform(-10.0, 10.0)
            px = max(PITCH_PADDING + 10.0, min(PITCH_WIDTH - PITCH_PADDING - 10.0, bx + drift_x))
            py = max(PITCH_PADDING + 10.0, min(PITCH_HEIGHT - PITCH_PADDING - 10.0, by + drift_y))
            team_a_pos.append((px, py))
            team_a_vel.append((drift_x * 4.0, drift_y * 4.0))

        # Team B positions with drift
        team_b_pos = []
        team_b_vel = []
        for idx, (bx, by) in enumerate(team_b_base):
            drift_x = (ball_x - bx) * 0.25 + random.uniform(-10.0, 10.0)
            drift_y = (ball_y - by) * 0.25 + random.uniform(-10.0, 10.0)
            px = max(PITCH_PADDING + 10.0, min(PITCH_WIDTH - PITCH_PADDING - 10.0, bx + drift_x))
            py = max(PITCH_PADDING + 10.0, min(PITCH_HEIGHT - PITCH_PADDING - 10.0, by + drift_y))
            team_b_pos.append((px, py))
            team_b_vel.append((drift_x * 4.0, drift_y * 4.0))

        # Passing lanes from ball carrier (e.g. player A-6)
        carrier_pos = team_a_pos[6]
        lanes = []
        for receiver_idx in (7, 8, 9, 10):
            recv_pos = team_a_pos[receiver_idx]
            # Check defender occlusion
            is_open = True
            for def_pos in team_b_pos:
                # Closest point distance
                dx = recv_pos[0] - carrier_pos[0]
                dy = recv_pos[1] - carrier_pos[1]
                l_sq = dx * dx + dy * dy
                if l_sq > 1.0:
                    t = max(0.0, min(1.0, ((def_pos[0] - carrier_pos[0]) * dx + (def_pos[1] - carrier_pos[1]) * dy) / l_sq))
                    c_x = carrier_pos[0] + dx * t
                    c_y = carrier_pos[1] + dy * t
                    d_sq = (def_pos[0] - c_x) ** 2 + (def_pos[1] - c_y) ** 2
                    if d_sq < 35.0 * 35.0:
                        is_open = False
                        break
            lanes.append((carrier_pos, recv_pos, is_open))

        svg_content = render_svg_frame(
            frame_idx=f_idx + 1,
            time_sec=t_sec,
            team_a_pos=team_a_pos,
            team_a_vel=team_a_vel,
            team_b_pos=team_b_pos,
            team_b_vel=team_b_vel,
            ball_pos=(ball_x, ball_y),
            ball_vel=ball_vel,
            passing_lanes=lanes,
            score=(1, 0)
        )

        frame_path = os.path.join(output_dir, f"frame_{f_idx+1:03d}.svg")
        with open(frame_path, "w", encoding="utf-8") as f:
            f.write(svg_content)
        generated_files.append(frame_path)

    print(f"[dump_match_frames] Exported {len(generated_files)} SVG match frames -> {os.path.relpath(output_dir, ROOT)}")
    return generated_files


def main() -> int:
    parser = argparse.ArgumentParser(description="Export top-down SVG match frames for multimodal evaluation")
    parser.add_argument("--frames", type=int, default=5, help="Number of match slice frames to generate (default: 5)")
    parser.add_argument("--output-dir", default=DEFAULT_OUTPUT_DIR, help="Target output directory for frames")
    args = parser.parse_args()

    generate_simulated_match_frames(num_frames=args.frames, output_dir=args.output_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
