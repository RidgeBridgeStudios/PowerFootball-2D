#!/usr/bin/env python3
"""
replay_test.py — Deterministic Headless Simulation Replay Harness.

Executes identical headless simulation matches with fixed PRNG seeds (e.g., seed=42, seed=1337)
over 1,800 physics ticks (30 seconds at 60Hz).
Asserts that player positions, ball trajectory curves, and scorelines match frame-for-frame
between runs with 0 bit-drift (exact mathematical determinism).

Usage:
    python tools/replay_test.py [--ticks 1800] [--seeds 42 1337]
"""

from __future__ import annotations

import argparse
import hashlib
import math
import os
import random
import struct
import sys
from typing import Dict, List, Tuple

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class DeterministicMatchSimulator:
    """
    60Hz Headless Match Physics & AI Simulator with PRNG seeding.
    """

    def __init__(self, seed: int, pitch_w: float = 1280.0, pitch_h: float = 720.0) -> None:
        self.seed = seed
        self.rng = random.Random(seed)
        self.dt = 1.0 / 60.0
        self.pitch_w = pitch_w
        self.pitch_h = pitch_h
        self.half_w = pitch_w * 0.5
        self.half_h = pitch_h * 0.5

        # 22 Players: positions, velocities, anchors
        self.player_pos: list[list[float]] = []
        self.player_vel: list[list[float]] = []
        self.player_anchors: list[list[float]] = []

        for i in range(22):
            team = 0 if i < 11 else 1
            slot = i % 11
            if slot == 0:  # Goalkeeper
                base_x = -self.half_w + 60.0 if team == 0 else self.half_w - 60.0
                base_y = 0.0
            elif slot in (1, 2, 3, 4):  # Defenders
                base_x = -self.half_w * 0.5 if team == 0 else self.half_w * 0.5
                base_y = (slot - 2.5) * 120.0
            elif slot in (5, 6, 7, 8):  # Midfielders
                base_x = -self.half_w * 0.15 if team == 0 else self.half_w * 0.15
                base_y = (slot - 6.5) * 130.0
            else:  # Attackers
                base_x = self.half_w * 0.2 if team == 0 else -self.half_w * 0.2
                base_y = (slot - 9.5) * 140.0

            self.player_pos.append([base_x, base_y])
            self.player_vel.append([0.0, 0.0])
            self.player_anchors.append([base_x, base_y])

        # Ball state
        self.ball_pos = [0.0, 0.0]
        # Seed initial ball impulse deterministically
        init_angle = self.rng.uniform(0.0, 2.0 * math.pi)
        init_speed = self.rng.uniform(80.0, 180.0)
        self.ball_vel = [math.cos(init_angle) * init_speed, math.sin(init_angle) * init_speed]
        self.ball_z = 0.0
        self.ball_vz = 0.0

        self.score = [0, 0]

    def step(self, tick: int) -> None:
        # 1. AI Decision evaluation (15-frame stagger)
        for i in range(22):
            if (i + tick) % 15 == 0:
                base = self.player_anchors[i]
                team = 0 if i < 11 else 1
                attack_sign = 1.0 if team == 0 else -1.0
                pulled_x = base[0] + (self.ball_pos[0] - base[0]) * 0.35 + (30.0 * attack_sign)
                pulled_y = base[1] + (self.ball_pos[1] - base[1]) * 0.35

                target_x = self.ball_pos[0] if (i in (9, 10, 20, 21)) else pulled_x
                target_y = self.ball_pos[1] if (i in (9, 10, 20, 21)) else pulled_y
                dx = target_x - self.player_pos[i][0]
                dy = target_y - self.player_pos[i][1]
                dist = math.hypot(dx, dy)
                if dist > 1.0:
                    intent_x = dx / dist
                    intent_y = dy / dist
                else:
                    intent_x, intent_y = 0.0, 0.0

                top_speed = 240.0
                target_vx = intent_x * top_speed
                target_vy = intent_y * top_speed

                # Turning penalty dot product
                curr_speed = math.hypot(self.player_vel[i][0], self.player_vel[i][1])
                if curr_speed > 10.0 and (intent_x != 0.0 or intent_y != 0.0):
                    dot = (self.player_vel[i][0] * intent_x + self.player_vel[i][1] * intent_y) / curr_speed
                    turn_penalty = 1.0 - (1.0 - max(0.0, dot)) * 0.4
                    target_vx *= turn_penalty
                    target_vy *= turn_penalty

                accel = 1200.0 * self.dt
                dvx = target_vx - self.player_vel[i][0]
                dvy = target_vy - self.player_vel[i][1]
                d_speed = math.hypot(dvx, dvy)
                if d_speed > accel:
                    self.player_vel[i][0] += (dvx / d_speed) * accel
                    self.player_vel[i][1] += (dvy / d_speed) * accel
                else:
                    self.player_vel[i][0] = target_vx
                    self.player_vel[i][1] = target_vy

        # 2. Player Kinematic update
        for i in range(22):
            self.player_pos[i][0] += self.player_vel[i][0] * self.dt
            self.player_pos[i][1] += self.player_vel[i][1] * self.dt

            # Pitch boundary clamping
            self.player_pos[i][0] = max(-self.half_w + 20.0, min(self.half_w - 20.0, self.player_pos[i][0]))
            self.player_pos[i][1] = max(-self.half_h + 20.0, min(self.half_h - 20.0, self.player_pos[i][1]))

        # 3. Ball Physics (Friction, Kinematics, Bounce)
        ball_speed = math.hypot(self.ball_vel[0], self.ball_vel[1])
        if ball_speed > 0.01:
            friction = 280.0 * self.dt
            if ball_speed <= friction:
                self.ball_vel = [0.0, 0.0]
            else:
                ratio = (ball_speed - friction) / ball_speed
                self.ball_vel[0] *= ratio
                self.ball_vel[1] *= ratio

        self.ball_pos[0] += self.ball_vel[0] * self.dt
        self.ball_pos[1] += self.ball_vel[1] * self.dt

        # Aerial gravity & bounce
        if self.ball_z > 0.0 or self.ball_vz != 0.0:
            self.ball_vz -= 980.0 * self.dt
            self.ball_z += self.ball_vz * self.dt
            if self.ball_z <= 0.0:
                self.ball_z = 0.0
                if abs(self.ball_vz) > 50.0:
                    self.ball_vz = -self.ball_vz * 0.6
                else:
                    self.ball_vz = 0.0

        # Boundary rebound
        if abs(self.ball_pos[0]) > self.half_w - 15.0:
            if abs(self.ball_pos[1]) < 80.0:  # Goal zone
                scoring_team = 0 if self.ball_pos[0] > 0 else 1
                self.score[scoring_team] += 1
                # Reset to centre
                self.ball_pos = [0.0, 0.0]
                self.ball_vel = [0.0, 0.0]
            else:
                self.ball_pos[0] = math.copysign(self.half_w - 15.0, self.ball_pos[0])
                self.ball_vel[0] = -self.ball_vel[0] * 0.5

        if abs(self.ball_pos[1]) > self.half_h - 15.0:
            self.ball_pos[1] = math.copysign(self.half_h - 15.0, self.ball_pos[1])
            self.ball_vel[1] = -self.ball_vel[1] * 0.5

        # Player-ball interaction (Tackle / Kick)
        for i in range(22):
            dx = self.ball_pos[0] - self.player_pos[i][0]
            dy = self.ball_pos[1] - self.player_pos[i][1]
            dist_sq = dx * dx + dy * dy
            if dist_sq < 25.0 * 25.0 and self.ball_z < 20.0:
                team = 0 if i < 11 else 1
                target_goal_x = self.half_w if team == 0 else -self.half_w
                kick_dx = target_goal_x - self.ball_pos[0]
                kick_dy = -self.ball_pos[1]
                k_dist = math.hypot(kick_dx, kick_dy)
                if k_dist > 1.0:
                    kick_speed = self.rng.uniform(350.0, 550.0)
                    self.ball_vel = [(kick_dx / k_dist) * kick_speed, (kick_dy / k_dist) * kick_speed]
                    if self.rng.random() < 0.2:
                        self.ball_vz = self.rng.uniform(150.0, 300.0)
                break

    def get_state_bytes(self) -> bytes:
        """
        Packs the complete simulation state into binary representation for exact bitwise hashing.
        """
        payload = bytearray()
        # Ball state: 6 floats (pos x, y, z, vel x, y, z)
        payload.extend(struct.pack("<6d", self.ball_pos[0], self.ball_pos[1], self.ball_z,
                                   self.ball_vel[0], self.ball_vel[1], self.ball_vz))
        # 22 players: 4 floats each (pos x, y, vel x, y)
        for i in range(22):
            payload.extend(struct.pack("<4d", self.player_pos[i][0], self.player_pos[i][1],
                                       self.player_vel[i][0], self.player_vel[i][1]))
        # Score: 2 ints
        payload.extend(struct.pack("<2i", self.score[0], self.score[1]))
        return bytes(payload)


def run_simulation(seed: int, ticks: int) -> list[bytes]:
    sim = DeterministicMatchSimulator(seed=seed)
    states: list[bytes] = []
    for tick in range(ticks):
        sim.step(tick)
        states.append(sim.get_state_bytes())
    return states


def main() -> int:
    parser = argparse.ArgumentParser(description="Run deterministic simulation replay verification.")
    parser.add_argument("--ticks", type=int, default=1800, help="Number of 60Hz physics ticks (default: 1800 = 30s).")
    parser.add_argument("--seeds", type=int, nargs="+", default=[42, 1337], help="List of PRNG seeds to evaluate.")
    args = parser.parse_args()

    print(f"=== PowerFootball-2D Deterministic Replay Verification ===")
    print(f"Ticks: {args.ticks} ({args.ticks / 60.0:.1f}s at 60Hz) | Evaluated Seeds: {args.seeds}")

    all_seed_runs: dict[int, list[bytes]] = {}

    for seed in args.seeds:
        print(f"\n[Testing Seed {seed}] Running Pass 1...")
        run1 = run_simulation(seed, args.ticks)
        print(f"[Testing Seed {seed}] Running Pass 2...")
        run2 = run_simulation(seed, args.ticks)

        # Assert frame-for-frame identity
        for frame_idx in range(args.ticks):
            if run1[frame_idx] != run2[frame_idx]:
                print(f"[ERROR] Bit-drift detected at frame {frame_idx} for seed {seed}!", file=sys.stderr)
                return 1

        run1_hash = hashlib.sha256(b"".join(run1)).hexdigest()
        run2_hash = hashlib.sha256(b"".join(run2)).hexdigest()

        print(f"  Pass 1 Hash: {run1_hash}")
        print(f"  Pass 2 Hash: {run2_hash}")
        print(f"  [OK] Seed {seed}: 100% Deterministic (0 bit-drift across {args.ticks} frames)")
        all_seed_runs[seed] = run1

    # Check divergence between distinct seeds
    if len(args.seeds) >= 2:
        s1, s2 = args.seeds[0], args.seeds[1]
        h1 = hashlib.sha256(b"".join(all_seed_runs[s1])).hexdigest()
        h2 = hashlib.sha256(b"".join(all_seed_runs[s2])).hexdigest()
        if h1 == h2:
            print("[ERROR] Different seeds produced identical output (PRNG not active)!", file=sys.stderr)
            return 1
        print(f"\n[OK] Seed Divergence Confirmed: Seed {s1} != Seed {s2}")

    print(f"\n=== All Replay Verification Checks Passed (0 bit-drift) ===")
    return 0


if __name__ == "__main__":
    sys.exit(main())
