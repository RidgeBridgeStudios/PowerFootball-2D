#!/usr/bin/env python3
"""
generate_db.py — Generates Layer 4 Club World JSON databases for PowerFootball 2D:
- res://data/league.json (8 teams, 18 players each, starters + subs, strictly bounded FM2D physics & traits)
- res://data/managers.json (10 managers, tactical profiles, traits bitmask, transfer/coaching biases)
- res://data/referees.json (8 referees, deep personality spectrums, career histories)
"""

import json
import os
import sys

def build_player(
    shirt_number: int,
    name: str,
    role: str,
    mass: float,
    top_speed: float,
    accel: float,
    frict: float,
    turn_pen: float,
    sprint_mult: float,
    stamina_max: float,
    vision: float,
    composure: float,
    aggression: float,
    close_control: float,
    reflexes: float,
    form: float = 6.5,
    ball_weight: float = 0.35,
    career_goals: int = 0,
    career_assists: int = 0,
    is_unavailable: bool = False
) -> dict:
    # Strict validation of invariant bounds
    assert 60.0 <= mass <= 95.0, f"mass out of bounds for {name}: {mass}"
    assert 170.0 <= top_speed <= 260.0, f"top_speed out of bounds for {name}: {top_speed}"
    assert 0.12 <= accel <= 0.38, f"accel out of bounds for {name}: {accel}"
    assert 0.18 <= turn_pen <= 0.55, f"turn_pen out of bounds for {name}: {turn_pen}"
    assert 75.0 <= stamina_max <= 125.0, f"stamina_max out of bounds for {name}: {stamina_max}"
    assert 0.0 <= vision <= 1.0, f"vision out of bounds for {name}: {vision}"
    assert 0.0 <= composure <= 1.0, f"composure out of bounds for {name}: {composure}"
    assert 0.0 <= aggression <= 1.0, f"aggression out of bounds for {name}: {aggression}"
    assert 0.0 <= close_control <= 1.0, f"close_control out of bounds for {name}: {close_control}"
    assert 0.0 <= reflexes <= 1.0, f"reflexes out of bounds for {name}: {reflexes}"

    return {
        "player_name": name,
        "shirt_number": shirt_number,
        "position_role": role,
        "mass": round(mass, 1),
        "top_speed": round(top_speed, 1),
        "acceleration_time": round(accel, 2),
        "friction_time": round(frict, 2),
        "turning_penalty": round(turn_pen, 2),
        "sprint_multiplier": round(sprint_mult, 2),
        "stamina_max": round(stamina_max, 1),
        "stamina_drain": 18.0,
        "stamina_recover": 9.0,
        "vision": round(vision, 2),
        "composure": round(composure, 2),
        "aggression": round(aggression, 2),
        "formation_ball_weight": round(ball_weight, 2),
        "close_control": round(close_control, 2),
        "reflexes": round(reflexes, 2),
        "form": round(form, 1),
        "career_goals": career_goals,
        "career_assists": career_assists,
        "last_match_rating": 0.0,
        "is_unavailable": is_unavailable
    }

def generate_league() -> dict:
    teams = []

    # 1. FC Nordvik (Navy & Ice Blue)
    nordvik_squad = [
        # Starting XI (0..10): GK, LB, CB, CB, RB, LM, CM, DM, RM, ST, ST
        build_player(1, "Mads Dahl", "GK", 82.0, 180.0, 0.32, 0.12, 0.50, 1.30, 95.0, 0.80, 0.85, 0.30, 0.50, 0.88, 7.0),
        build_player(3, "Erik Lund", "LB", 76.0, 215.0, 0.22, 0.12, 0.35, 1.44, 105.0, 0.70, 0.62, 0.58, 0.65, 0.40, 6.8),
        build_player(5, "Halvard Brann", "CB", 90.0, 188.0, 0.32, 0.12, 0.50, 1.28, 98.0, 0.62, 0.76, 0.82, 0.52, 0.35, 6.6),
        build_player(4, "Sigurd Voss", "CB", 88.0, 192.0, 0.32, 0.12, 0.50, 1.30, 96.0, 0.65, 0.72, 0.75, 0.55, 0.35, 6.5),
        build_player(2, "Torben Hauge", "RB", 75.0, 214.0, 0.22, 0.12, 0.35, 1.45, 102.0, 0.72, 0.64, 0.60, 0.66, 0.40, 6.7),
        build_player(11, "Jonas Elv", "LM", 69.0, 230.0, 0.15, 0.12, 0.25, 1.52, 100.0, 0.75, 0.58, 0.62, 0.80, 0.45, 7.2, career_goals=3, career_assists=5),
        build_player(8, "Olav Strand", "CM", 74.0, 210.0, 0.22, 0.12, 0.35, 1.40, 112.0, 0.85, 0.74, 0.62, 0.75, 0.45, 7.0, career_goals=2, career_assists=4),
        build_player(6, "Niklas Borg", "DM", 80.0, 202.0, 0.30, 0.12, 0.48, 1.36, 108.0, 0.80, 0.80, 0.78, 0.68, 0.40, 6.9, career_goals=1),
        build_player(7, "Rune Kval", "RM", 70.0, 226.0, 0.15, 0.12, 0.25, 1.50, 98.0, 0.74, 0.60, 0.65, 0.78, 0.45, 6.8, career_goals=4, career_assists=3),
        build_player(9, "Henrik Ask", "ST", 83.0, 222.0, 0.22, 0.12, 0.35, 1.50, 100.0, 0.70, 0.68, 0.85, 0.72, 0.45, 7.5, career_goals=8, career_assists=2),
        build_player(10, "Petter Naess", "ST", 72.0, 218.0, 0.16, 0.12, 0.26, 1.48, 96.0, 0.88, 0.82, 0.58, 0.84, 0.45, 7.1, career_goals=5, career_assists=6),
        # Substitutes (11..17)
        build_player(12, "Emil Lind", "GK", 84.0, 178.0, 0.33, 0.12, 0.50, 1.28, 90.0, 0.65, 0.70, 0.40, 0.48, 0.75, 6.2),
        build_player(14, "Rasmus Holst", "CB", 87.0, 190.0, 0.32, 0.12, 0.50, 1.28, 92.0, 0.58, 0.65, 0.72, 0.50, 0.35, 6.3),
        build_player(15, "Joakim Berg", "RB", 74.0, 212.0, 0.22, 0.12, 0.35, 1.42, 95.0, 0.64, 0.60, 0.55, 0.62, 0.40, 6.4),
        build_player(16, "Stian Mork", "CM", 75.0, 206.0, 0.22, 0.12, 0.35, 1.38, 102.0, 0.72, 0.68, 0.60, 0.70, 0.45, 6.5),
        build_player(17, "Magnus Rygg", "AM", 70.0, 216.0, 0.16, 0.12, 0.26, 1.46, 92.0, 0.80, 0.70, 0.52, 0.76, 0.45, 6.4),
        build_player(18, "Vidar Krog", "ST", 85.0, 212.0, 0.24, 0.12, 0.38, 1.44, 94.0, 0.62, 0.62, 0.80, 0.65, 0.40, 6.3, career_goals=1),
        build_player(19, "Andreas Solberg", "CB", 86.0, 186.0, 0.32, 0.12, 0.50, 1.26, 90.0, 0.55, 0.60, 0.70, 0.48, 0.35, 6.0),
    ]
    teams.append({
        "team_name": "FC Nordvik",
        "team_color": [0.05, 0.13, 0.25], # #0D2240
        "primary_color": "#0D2240",
        "secondary_color": "#4A90E2",
        "formation_override": "4-4-2",
        "lineup_indices": list(range(11)),
        "squad": nordvik_squad
    })

    # 2. CD Solano (Crimson & Amber)
    solano_squad = [
        # Starting XI (0..10): GK, LB, CB, CB, RB, DM, CM, AM, LW, ST, RW
        build_player(1, "Carlos Vega", "GK", 80.0, 180.0, 0.32, 0.12, 0.50, 1.28, 92.0, 0.78, 0.88, 0.25, 0.55, 0.90, 7.1),
        build_player(3, "Luis Ferrer", "LB", 73.0, 222.0, 0.20, 0.12, 0.32, 1.48, 106.0, 0.76, 0.66, 0.54, 0.72, 0.45, 6.9),
        build_player(5, "Mateo Ruiz", "CB", 86.0, 192.0, 0.30, 0.12, 0.48, 1.30, 96.0, 0.68, 0.74, 0.70, 0.60, 0.35, 6.7),
        build_player(4, "Diego Pons", "CB", 88.0, 188.0, 0.32, 0.12, 0.50, 1.28, 95.0, 0.62, 0.70, 0.74, 0.56, 0.35, 6.6),
        build_player(2, "Andres Mora", "RB", 74.0, 220.0, 0.20, 0.12, 0.32, 1.47, 104.0, 0.74, 0.65, 0.55, 0.70, 0.45, 6.8),
        build_player(6, "Pablo Cano", "DM", 78.0, 204.0, 0.28, 0.12, 0.45, 1.38, 110.0, 0.82, 0.78, 0.74, 0.72, 0.40, 7.0, career_goals=1, career_assists=2),
        build_player(8, "Rafael Soto", "CM", 72.0, 214.0, 0.20, 0.12, 0.32, 1.44, 114.0, 0.86, 0.78, 0.58, 0.82, 0.45, 7.3, career_goals=3, career_assists=7),
        build_player(10, "Marco Reyes", "AM", 69.0, 220.0, 0.15, 0.12, 0.24, 1.50, 102.0, 0.94, 0.84, 0.52, 0.90, 0.45, 7.6, career_goals=6, career_assists=8),
        build_player(11, "Javier Tur", "LW", 67.0, 240.0, 0.15, 0.12, 0.24, 1.56, 100.0, 0.72, 0.55, 0.68, 0.86, 0.45, 7.4, career_goals=7, career_assists=4),
        build_player(9, "Bruno Tena", "ST", 81.0, 224.0, 0.20, 0.12, 0.34, 1.52, 102.0, 0.74, 0.72, 0.84, 0.78, 0.45, 7.5, career_goals=9, career_assists=3),
        build_player(7, "Ivan Blasco", "RW", 68.0, 238.0, 0.15, 0.12, 0.24, 1.54, 98.0, 0.75, 0.58, 0.65, 0.84, 0.45, 7.2, career_goals=5, career_assists=5),
        # Substitutes (11..17)
        build_player(13, "Joaquin Giner", "GK", 81.0, 176.0, 0.33, 0.12, 0.50, 1.25, 90.0, 0.68, 0.72, 0.30, 0.50, 0.78, 6.3),
        build_player(14, "Felix Navarro", "CB", 85.0, 190.0, 0.32, 0.12, 0.50, 1.27, 92.0, 0.60, 0.66, 0.68, 0.54, 0.35, 6.4),
        build_player(15, "Santi Cordero", "LB", 72.0, 216.0, 0.21, 0.12, 0.34, 1.44, 98.0, 0.68, 0.62, 0.50, 0.68, 0.40, 6.3),
        build_player(16, "Alejandro Blesa", "CM", 71.0, 208.0, 0.21, 0.12, 0.34, 1.40, 104.0, 0.78, 0.70, 0.55, 0.76, 0.45, 6.6),
        build_player(17, "Dani Osorio", "RW", 66.0, 232.0, 0.15, 0.12, 0.25, 1.50, 94.0, 0.68, 0.52, 0.60, 0.78, 0.45, 6.5, career_goals=1),
        build_player(18, "Alvaro Ribera", "ST", 82.0, 218.0, 0.22, 0.12, 0.35, 1.48, 96.0, 0.65, 0.64, 0.76, 0.70, 0.40, 6.4, career_goals=2),
        build_player(19, "Mario Gil", "AM", 68.0, 214.0, 0.16, 0.12, 0.26, 1.45, 92.0, 0.82, 0.72, 0.48, 0.80, 0.45, 6.5),
    ]
    teams.append({
        "team_name": "CD Solano",
        "team_color": [0.64, 0.11, 0.11], # #A31D1D
        "primary_color": "#A31D1D",
        "secondary_color": "#E5A93C",
        "formation_override": "4-3-3",
        "lineup_indices": list(range(11)),
        "squad": solano_squad
    })

    # 3. Valence Athletic (Forest Green & Athletic Gold)
    valence_squad = [
        # Starting XI (0..10): GK, LB, CB, CB, RB, DM, DM, CAM, LM, RM, ST
        build_player(1, "Luc Renard", "GK", 83.0, 182.0, 0.32, 0.12, 0.50, 1.30, 96.0, 0.75, 0.84, 0.35, 0.52, 0.86, 6.8),
        build_player(3, "Clement Bastien", "LB", 75.0, 216.0, 0.21, 0.12, 0.34, 1.44, 108.0, 0.74, 0.68, 0.60, 0.68, 0.40, 6.7),
        build_player(4, "Henri Dupont", "CB", 89.0, 194.0, 0.31, 0.12, 0.48, 1.32, 100.0, 0.66, 0.78, 0.76, 0.58, 0.35, 6.9),
        build_player(5, "Maxime Laurent", "CB", 87.0, 196.0, 0.31, 0.12, 0.48, 1.32, 98.0, 0.64, 0.76, 0.78, 0.56, 0.35, 6.8),
        build_player(2, "Julien Mercier", "RB", 76.0, 214.0, 0.21, 0.12, 0.34, 1.43, 106.0, 0.72, 0.66, 0.62, 0.66, 0.40, 6.6),
        build_player(6, "Romain Vasseur", "DM", 81.0, 204.0, 0.28, 0.12, 0.45, 1.38, 116.0, 0.84, 0.82, 0.76, 0.74, 0.40, 7.1, career_goals=1, career_assists=3),
        build_player(8, "Theo Fontaine", "DM", 79.0, 208.0, 0.26, 0.12, 0.42, 1.40, 118.0, 0.82, 0.80, 0.72, 0.76, 0.40, 7.0, career_goals=2, career_assists=4),
        build_player(10, "Gabriel Moreau", "AM", 71.0, 218.0, 0.16, 0.12, 0.25, 1.48, 104.0, 0.90, 0.86, 0.54, 0.86, 0.45, 7.4, career_goals=5, career_assists=7),
        build_player(11, "Antoine Giraud", "LM", 70.0, 228.0, 0.16, 0.12, 0.26, 1.50, 102.0, 0.76, 0.64, 0.58, 0.80, 0.45, 6.9, career_goals=4, career_assists=5),
        build_player(7, "Sebastien Fabre", "RM", 71.0, 226.0, 0.16, 0.12, 0.26, 1.49, 100.0, 0.75, 0.65, 0.60, 0.78, 0.45, 6.8, career_goals=3, career_assists=4),
        build_player(9, "Alexandre Roche", "ST", 82.0, 222.0, 0.21, 0.12, 0.34, 1.50, 102.0, 0.72, 0.74, 0.80, 0.76, 0.40, 7.2, career_goals=7, career_assists=2),
        # Substitutes (11..17)
        build_player(16, "Nicolas Perrin", "GK", 82.0, 178.0, 0.33, 0.12, 0.50, 1.26, 92.0, 0.68, 0.74, 0.32, 0.50, 0.76, 6.1),
        build_player(14, "Florian Blanc", "CB", 86.0, 190.0, 0.32, 0.12, 0.50, 1.28, 94.0, 0.60, 0.68, 0.70, 0.52, 0.35, 6.3),
        build_player(15, "Mathieu Clement", "RB", 75.0, 210.0, 0.22, 0.12, 0.35, 1.40, 96.0, 0.66, 0.60, 0.58, 0.62, 0.40, 6.2),
        build_player(17, "Adrien Caron", "CM", 76.0, 204.0, 0.24, 0.12, 0.38, 1.38, 106.0, 0.76, 0.72, 0.65, 0.72, 0.40, 6.4),
        build_player(18, "Pierre Lefevre", "LW", 68.0, 224.0, 0.16, 0.12, 0.26, 1.48, 95.0, 0.70, 0.58, 0.55, 0.75, 0.45, 6.4, career_goals=1),
        build_player(19, "Tristan Bonnet", "ST", 84.0, 214.0, 0.23, 0.12, 0.36, 1.45, 96.0, 0.64, 0.66, 0.75, 0.68, 0.40, 6.3, career_goals=2),
        build_player(20, "Lucas Guerin", "AM", 69.0, 212.0, 0.17, 0.12, 0.28, 1.44, 94.0, 0.78, 0.70, 0.48, 0.78, 0.45, 6.2),
    ]
    teams.append({
        "team_name": "Valence Athletic",
        "team_color": [0.11, 0.30, 0.24], # #1B4D3E
        "primary_color": "#1B4D3E",
        "secondary_color": "#D4AF37",
        "formation_override": "4-2-3-1",
        "lineup_indices": list(range(11)),
        "squad": valence_squad
    })

    # 4. Real Maritimo (Sky Blue & Coral)
    maritimo_squad = [
        # Starting XI (0..10): GK, LCB, CB, RCB, LWB, DM, RWB, CM, CAM, ST, ST
        build_player(1, "Tiago Valente", "GK", 81.0, 184.0, 0.30, 0.12, 0.48, 1.32, 94.0, 0.82, 0.80, 0.30, 0.60, 0.84, 6.9),
        build_player(3, "Bernardo Paiva", "CB", 85.0, 198.0, 0.29, 0.12, 0.45, 1.34, 98.0, 0.68, 0.72, 0.72, 0.62, 0.35, 6.7),
        build_player(4, "Goncalo Couto", "CB", 89.0, 192.0, 0.32, 0.12, 0.50, 1.28, 96.0, 0.62, 0.78, 0.80, 0.54, 0.35, 6.8),
        build_player(5, "Diogo Pinho", "CB", 84.0, 200.0, 0.29, 0.12, 0.45, 1.35, 98.0, 0.66, 0.70, 0.70, 0.60, 0.35, 6.6),
        build_player(11, "Hugo Sampaio", "LB", 71.0, 234.0, 0.16, 0.12, 0.25, 1.52, 110.0, 0.78, 0.68, 0.60, 0.82, 0.45, 7.2, career_goals=2, career_assists=6),
        build_player(6, "Tomas Brandao", "DM", 79.0, 206.0, 0.26, 0.12, 0.40, 1.40, 114.0, 0.88, 0.84, 0.68, 0.80, 0.40, 7.3, career_goals=1, career_assists=5),
        build_player(2, "Nuno Matos", "RB", 72.0, 232.0, 0.16, 0.12, 0.25, 1.50, 108.0, 0.76, 0.66, 0.62, 0.80, 0.45, 7.0, career_goals=1, career_assists=4),
        build_player(8, "Fabio Gouveia", "CM", 73.0, 212.0, 0.20, 0.12, 0.32, 1.44, 112.0, 0.84, 0.76, 0.64, 0.80, 0.45, 7.1, career_goals=3, career_assists=5),
        build_player(10, "Rodrigo Lessa", "AM", 68.0, 222.0, 0.15, 0.12, 0.24, 1.50, 102.0, 0.92, 0.80, 0.50, 0.88, 0.45, 7.4, career_goals=4, career_assists=8),
        build_player(9, "Ricardo Trindade", "ST", 82.0, 228.0, 0.19, 0.12, 0.30, 1.54, 104.0, 0.74, 0.76, 0.82, 0.80, 0.45, 7.7, career_goals=10, career_assists=3),
        build_player(7, "Vasco Lourenco", "ST", 76.0, 232.0, 0.17, 0.12, 0.28, 1.55, 102.0, 0.78, 0.72, 0.70, 0.82, 0.45, 7.3, career_goals=6, career_assists=5),
        # Substitutes (11..17)
        build_player(12, "Afonso Vilar", "GK", 80.0, 180.0, 0.32, 0.12, 0.50, 1.28, 90.0, 0.70, 0.72, 0.30, 0.52, 0.76, 6.2),
        build_player(13, "Miguel Ramalho", "CB", 86.0, 192.0, 0.32, 0.12, 0.50, 1.28, 92.0, 0.60, 0.66, 0.74, 0.54, 0.35, 6.3),
        build_player(14, "Joao Faria", "CM", 74.0, 208.0, 0.22, 0.12, 0.35, 1.40, 102.0, 0.76, 0.70, 0.58, 0.74, 0.45, 6.5),
        build_player(15, "Leandro Neves", "RB", 71.0, 224.0, 0.18, 0.12, 0.28, 1.46, 96.0, 0.68, 0.60, 0.55, 0.72, 0.45, 6.4),
        build_player(16, "Pedro Quaresma", "AM", 67.0, 218.0, 0.16, 0.12, 0.26, 1.48, 94.0, 0.82, 0.68, 0.48, 0.82, 0.45, 6.5, career_goals=1),
        build_player(17, "Bruno Peixoto", "ST", 80.0, 220.0, 0.21, 0.12, 0.34, 1.48, 96.0, 0.68, 0.65, 0.72, 0.72, 0.40, 6.4, career_goals=2),
        build_player(18, "Andre Caires", "LB", 70.0, 222.0, 0.18, 0.12, 0.28, 1.45, 96.0, 0.70, 0.60, 0.52, 0.72, 0.45, 6.2),
    ]
    teams.append({
        "team_name": "Real Maritimo",
        "team_color": [0.0, 0.47, 0.71], # #0077B6
        "primary_color": "#0077B6",
        "secondary_color": "#FF6B6B",
        "formation_override": "3-5-2",
        "lineup_indices": list(range(11)),
        "squad": maritimo_squad
    })

    # 5. Borussia Eisenwald (Iron Charcoal & Steel Silver)
    eisenwald_squad = [
        # Starting XI (0..10): GK, LWB, LCB, CB, RCB, RWB, DM, CM, CM, ST, ST
        build_player(1, "Stefan Vogel", "GK", 86.0, 176.0, 0.34, 0.12, 0.52, 1.25, 95.0, 0.70, 0.88, 0.40, 0.48, 0.86, 7.0),
        build_player(3, "Florian Richter", "LB", 78.0, 210.0, 0.24, 0.12, 0.38, 1.40, 106.0, 0.68, 0.70, 0.72, 0.64, 0.40, 6.6),
        build_player(4, "Markus Brandt", "CB", 92.0, 186.0, 0.34, 0.12, 0.52, 1.25, 98.0, 0.58, 0.80, 0.88, 0.48, 0.35, 7.0),
        build_player(5, "Torsten Becker", "CB", 94.0, 184.0, 0.35, 0.12, 0.54, 1.24, 100.0, 0.56, 0.82, 0.92, 0.46, 0.35, 7.1),
        build_player(6, "Hanno Schultheiss", "CB", 90.0, 188.0, 0.33, 0.12, 0.50, 1.26, 96.0, 0.60, 0.76, 0.84, 0.50, 0.35, 6.8),
        build_player(2, "Dirk Lindemann", "RB", 79.0, 212.0, 0.24, 0.12, 0.38, 1.40, 104.0, 0.66, 0.68, 0.74, 0.62, 0.40, 6.7),
        build_player(8, "Lars Krumm", "DM", 84.0, 198.0, 0.30, 0.12, 0.48, 1.34, 114.0, 0.78, 0.82, 0.86, 0.68, 0.40, 7.2, career_goals=1),
        build_player(10, "Volker Hahn", "CM", 78.0, 206.0, 0.24, 0.12, 0.38, 1.40, 112.0, 0.82, 0.78, 0.70, 0.74, 0.45, 6.9, career_goals=2, career_assists=4),
        build_player(7, "Jupp Sauer", "CM", 77.0, 208.0, 0.24, 0.12, 0.38, 1.40, 110.0, 0.80, 0.76, 0.72, 0.72, 0.45, 6.8, career_goals=3, career_assists=3),
        build_player(9, "Gunnar Holtz", "ST", 89.0, 214.0, 0.26, 0.12, 0.42, 1.46, 102.0, 0.65, 0.70, 0.90, 0.66, 0.40, 7.3, career_goals=8, career_assists=2),
        build_player(11, "Max Brecht", "ST", 80.0, 224.0, 0.20, 0.12, 0.32, 1.50, 102.0, 0.72, 0.68, 0.78, 0.74, 0.45, 7.0, career_goals=6, career_assists=4),
        # Substitutes (11..17)
        build_player(12, "Jens Eberlein", "GK", 85.0, 174.0, 0.34, 0.12, 0.52, 1.24, 90.0, 0.62, 0.74, 0.35, 0.45, 0.74, 6.0),
        build_player(13, "Moritz Reuter", "CB", 89.0, 184.0, 0.34, 0.12, 0.52, 1.24, 92.0, 0.54, 0.70, 0.80, 0.46, 0.35, 6.2),
        build_player(14, "Janosch Pfeifer", "RB", 77.0, 208.0, 0.25, 0.12, 0.40, 1.38, 96.0, 0.62, 0.62, 0.68, 0.58, 0.40, 6.1),
        build_player(15, "Timo Eckert", "DM", 82.0, 196.0, 0.31, 0.12, 0.49, 1.32, 102.0, 0.70, 0.72, 0.78, 0.62, 0.40, 6.3),
        build_player(16, "Christoph Kroll", "CM", 76.0, 202.0, 0.25, 0.12, 0.40, 1.36, 100.0, 0.74, 0.68, 0.65, 0.68, 0.45, 6.3),
        build_player(17, "Kilian Graf", "ST", 86.0, 210.0, 0.27, 0.12, 0.44, 1.42, 94.0, 0.58, 0.62, 0.82, 0.60, 0.40, 6.2, career_goals=1),
        build_player(18, "Sascha Wendt", "LB", 76.0, 206.0, 0.25, 0.12, 0.40, 1.38, 94.0, 0.60, 0.62, 0.66, 0.58, 0.40, 6.0),
    ]
    teams.append({
        "team_name": "Borussia Eisenwald",
        "team_color": [0.13, 0.15, 0.16], # #212529
        "primary_color": "#212529",
        "secondary_color": "#ADB5BD",
        "formation_override": "5-3-2",
        "lineup_indices": list(range(11)),
        "squad": eisenwald_squad
    })

    # 6. Aurora Calcio (Royal Plum & Neon Tangerine)
    aurora_squad = [
        # Starting XI (0..10): GK, LB, CB, CB, RB, DM, CM, AM, LW, ST, RW
        build_player(1, "Lorenzo Galli", "GK", 81.0, 182.0, 0.31, 0.12, 0.49, 1.30, 94.0, 0.84, 0.86, 0.28, 0.58, 0.88, 7.2),
        build_player(3, "Matteo De Rosa", "LB", 72.0, 220.0, 0.19, 0.12, 0.30, 1.48, 106.0, 0.78, 0.72, 0.52, 0.76, 0.45, 7.0),
        build_player(4, "Alessandro Moretti", "CB", 86.0, 194.0, 0.30, 0.12, 0.46, 1.32, 98.0, 0.72, 0.82, 0.68, 0.66, 0.35, 7.1),
        build_player(5, "Claudio Vieri", "CB", 87.0, 192.0, 0.31, 0.12, 0.48, 1.30, 96.0, 0.70, 0.80, 0.72, 0.64, 0.35, 7.0),
        build_player(2, "Daniele Conti", "RB", 73.0, 218.0, 0.19, 0.12, 0.30, 1.46, 104.0, 0.76, 0.70, 0.54, 0.74, 0.45, 6.9),
        build_player(6, "Pietro Donati", "DM", 77.0, 206.0, 0.26, 0.12, 0.40, 1.40, 114.0, 0.88, 0.86, 0.66, 0.80, 0.40, 7.4, career_goals=1, career_assists=4),
        build_player(8, "Giorgio Barbieri", "CM", 73.0, 214.0, 0.19, 0.12, 0.30, 1.44, 112.0, 0.90, 0.84, 0.56, 0.86, 0.45, 7.5, career_goals=4, career_assists=7),
        build_player(10, "Leonardo Rinaldi", "AM", 69.0, 222.0, 0.15, 0.12, 0.24, 1.52, 104.0, 0.96, 0.88, 0.48, 0.92, 0.45, 7.8, career_goals=7, career_assists=9),
        build_player(11, "Filippo Monti", "LW", 68.0, 236.0, 0.15, 0.12, 0.24, 1.54, 100.0, 0.80, 0.68, 0.58, 0.88, 0.45, 7.3, career_goals=6, career_assists=5),
        build_player(9, "Stefano Leone", "ST", 80.0, 226.0, 0.19, 0.12, 0.30, 1.52, 104.0, 0.78, 0.80, 0.76, 0.82, 0.45, 7.6, career_goals=11, career_assists=3),
        build_player(7, "Niccolo Bardi", "RW", 68.0, 234.0, 0.15, 0.12, 0.24, 1.52, 98.0, 0.82, 0.70, 0.54, 0.86, 0.45, 7.2, career_goals=5, career_assists=6),
        # Substitutes (11..17)
        build_player(12, "Federico Greco", "GK", 82.0, 178.0, 0.32, 0.12, 0.50, 1.28, 90.0, 0.72, 0.76, 0.26, 0.52, 0.78, 6.3),
        build_player(13, "Vincenzo Silvestri", "CB", 85.0, 190.0, 0.32, 0.12, 0.50, 1.28, 92.0, 0.64, 0.70, 0.66, 0.58, 0.35, 6.4),
        build_player(14, "Jacopo Costa", "LB", 71.0, 216.0, 0.20, 0.12, 0.32, 1.44, 96.0, 0.70, 0.64, 0.50, 0.70, 0.40, 6.3),
        build_player(15, "Edoardo Marini", "CM", 72.0, 210.0, 0.20, 0.12, 0.32, 1.42, 104.0, 0.82, 0.74, 0.52, 0.78, 0.45, 6.6),
        build_player(16, "Alessio Santoro", "RW", 67.0, 228.0, 0.16, 0.12, 0.26, 1.50, 94.0, 0.74, 0.62, 0.50, 0.80, 0.45, 6.4, career_goals=1),
        build_player(17, "Marco Ferri", "ST", 81.0, 220.0, 0.21, 0.12, 0.34, 1.48, 96.0, 0.70, 0.70, 0.70, 0.74, 0.40, 6.5, career_goals=2),
        build_player(18, "Giulio Lombardi", "AM", 68.0, 216.0, 0.16, 0.12, 0.26, 1.46, 92.0, 0.84, 0.76, 0.45, 0.82, 0.45, 6.4),
    ]
    teams.append({
        "team_name": "Aurora Calcio",
        "team_color": [0.29, 0.08, 0.29], # #4A154B
        "primary_color": "#4A154B",
        "secondary_color": "#FF5722",
        "formation_override": "4-3-3",
        "lineup_indices": list(range(11)),
        "squad": aurora_squad
    })

    # 7. Highland Thistle FC (Tartan Maroon & Off-White)
    highland_squad = [
        # Starting XI (0..10): GK, LB, CB, CB, RB, LM, CM, CM, RM, ST, ST
        build_player(1, "Craig MacIntyre", "GK", 85.0, 178.0, 0.33, 0.12, 0.50, 1.28, 98.0, 0.72, 0.80, 0.45, 0.50, 0.85, 6.9),
        build_player(3, "Ewan Sinclair", "LB", 77.0, 214.0, 0.22, 0.12, 0.36, 1.44, 110.0, 0.70, 0.64, 0.75, 0.65, 0.40, 6.8),
        build_player(4, "Duncan Brogan", "CB", 91.0, 188.0, 0.33, 0.12, 0.52, 1.26, 102.0, 0.60, 0.74, 0.90, 0.50, 0.35, 7.1),
        build_player(5, "Callum MacLeod", "CB", 89.0, 190.0, 0.32, 0.12, 0.50, 1.28, 100.0, 0.62, 0.72, 0.88, 0.52, 0.35, 7.0),
        build_player(2, "Archie Crawford", "RB", 78.0, 212.0, 0.22, 0.12, 0.36, 1.43, 108.0, 0.68, 0.62, 0.76, 0.64, 0.40, 6.7),
        build_player(11, "Ross Finlay", "LM", 73.0, 226.0, 0.17, 0.12, 0.28, 1.50, 112.0, 0.74, 0.62, 0.78, 0.74, 0.45, 7.0, career_goals=3, career_assists=6),
        build_player(8, "Hamish Boyd", "CM", 80.0, 208.0, 0.24, 0.12, 0.38, 1.40, 120.0, 0.80, 0.76, 0.85, 0.72, 0.45, 7.3, career_goals=3, career_assists=4),
        build_player(6, "Fraser Gillespie", "CM", 82.0, 204.0, 0.26, 0.12, 0.42, 1.38, 118.0, 0.78, 0.78, 0.88, 0.70, 0.40, 7.2, career_goals=2, career_assists=3),
        build_player(7, "Brodie Sutherland", "RM", 74.0, 224.0, 0.18, 0.12, 0.28, 1.48, 110.0, 0.72, 0.60, 0.76, 0.72, 0.45, 6.8, career_goals=2, career_assists=5),
        build_player(9, "Colin Menzies", "ST", 86.0, 218.0, 0.23, 0.12, 0.38, 1.48, 106.0, 0.66, 0.68, 0.92, 0.68, 0.40, 7.4, career_goals=9, career_assists=2),
        build_player(10, "Jamie Lorimer", "ST", 78.0, 224.0, 0.20, 0.12, 0.32, 1.52, 104.0, 0.74, 0.70, 0.80, 0.76, 0.45, 7.2, career_goals=7, career_assists=5),
        # Substitutes (11..17)
        build_player(12, "Stewart Nairn", "GK", 84.0, 176.0, 0.33, 0.12, 0.50, 1.26, 92.0, 0.65, 0.72, 0.38, 0.46, 0.76, 6.1),
        build_player(13, "Blair Urquhart", "CB", 88.0, 186.0, 0.33, 0.12, 0.50, 1.26, 94.0, 0.56, 0.68, 0.82, 0.48, 0.35, 6.3),
        build_player(14, "Gregor Mathieson", "RB", 76.0, 210.0, 0.23, 0.12, 0.37, 1.40, 98.0, 0.62, 0.58, 0.70, 0.60, 0.40, 6.2),
        build_player(15, "Rory Dunbar", "CM", 78.0, 202.0, 0.25, 0.12, 0.40, 1.36, 106.0, 0.72, 0.68, 0.76, 0.66, 0.40, 6.4),
        build_player(16, "Murdo Garrow", "LM", 72.0, 220.0, 0.19, 0.12, 0.30, 1.46, 98.0, 0.68, 0.56, 0.70, 0.68, 0.45, 6.3, career_goals=1),
        build_player(17, "Douglas Renwick", "ST", 85.0, 212.0, 0.25, 0.12, 0.40, 1.44, 96.0, 0.60, 0.62, 0.84, 0.62, 0.40, 6.3, career_goals=2),
        build_player(18, "Angus MacBeath", "CB", 87.0, 184.0, 0.33, 0.12, 0.50, 1.25, 92.0, 0.54, 0.65, 0.80, 0.46, 0.35, 6.0),
    ]
    teams.append({
        "team_name": "Highland Thistle FC",
        "team_color": [0.36, 0.11, 0.14], # #5C1D24
        "primary_color": "#5C1D24",
        "secondary_color": "#F8F9FA",
        "formation_override": "4-4-2",
        "lineup_indices": list(range(11)),
        "squad": highland_squad
    })

    # 8. Porto Sol Stella (Teal & Sunlight Gold)
    portosol_squad = [
        # Starting XI (0..10): GK, LB, CB, CB, RB, DM, CM, CAM, LW, RW, ST
        build_player(1, "Marcelo Candeias", "GK", 80.0, 182.0, 0.31, 0.12, 0.49, 1.30, 94.0, 0.80, 0.82, 0.25, 0.62, 0.86, 7.0),
        build_player(3, "Paulo Serpa", "LB", 72.0, 224.0, 0.18, 0.12, 0.28, 1.50, 104.0, 0.76, 0.68, 0.50, 0.80, 0.45, 7.1),
        build_player(4, "Tiago Guimaraes", "CB", 86.0, 194.0, 0.30, 0.12, 0.48, 1.32, 96.0, 0.68, 0.76, 0.70, 0.62, 0.35, 6.9),
        build_player(5, "Everton Morais", "CB", 88.0, 190.0, 0.32, 0.12, 0.50, 1.28, 96.0, 0.64, 0.74, 0.76, 0.58, 0.35, 6.8),
        build_player(2, "Caio Belmonte", "RB", 73.0, 222.0, 0.18, 0.12, 0.28, 1.48, 102.0, 0.74, 0.66, 0.52, 0.78, 0.45, 7.0),
        build_player(6, "Nilton Arantes", "DM", 78.0, 206.0, 0.26, 0.12, 0.40, 1.40, 112.0, 0.84, 0.80, 0.72, 0.78, 0.40, 7.2, career_goals=1, career_assists=3),
        build_player(8, "Danilo Fogaca", "CM", 73.0, 216.0, 0.18, 0.12, 0.28, 1.46, 110.0, 0.88, 0.82, 0.58, 0.88, 0.45, 7.5, career_goals=4, career_assists=6),
        build_player(10, "Zico Valadares", "AM", 68.0, 226.0, 0.15, 0.12, 0.22, 1.54, 102.0, 0.95, 0.86, 0.46, 0.94, 0.45, 7.9, career_goals=8, career_assists=10),
        build_player(11, "Renan Junqueira", "LW", 67.0, 238.0, 0.15, 0.12, 0.23, 1.56, 98.0, 0.78, 0.64, 0.60, 0.90, 0.45, 7.6, career_goals=7, career_assists=5),
        build_player(7, "Giba Santana", "RW", 68.0, 236.0, 0.15, 0.12, 0.23, 1.54, 98.0, 0.80, 0.66, 0.56, 0.88, 0.45, 7.4, career_goals=6, career_assists=6),
        build_player(9, "Robson Barreto", "ST", 81.0, 226.0, 0.19, 0.12, 0.30, 1.52, 102.0, 0.76, 0.78, 0.78, 0.82, 0.45, 7.6, career_goals=10, career_assists=4),
        # Substitutes (11..17)
        build_player(12, "Edilson Prates", "GK", 81.0, 178.0, 0.32, 0.12, 0.50, 1.28, 90.0, 0.70, 0.74, 0.28, 0.54, 0.76, 6.2),
        build_player(13, "Wanderson Lima", "CB", 85.0, 188.0, 0.32, 0.12, 0.50, 1.28, 92.0, 0.60, 0.68, 0.70, 0.56, 0.35, 6.3),
        build_player(14, "Henrique Pato", "RB", 72.0, 218.0, 0.20, 0.12, 0.30, 1.44, 96.0, 0.68, 0.60, 0.48, 0.72, 0.45, 6.2),
        build_player(15, "Clodoaldo Brito", "DM", 79.0, 202.0, 0.28, 0.12, 0.44, 1.36, 104.0, 0.78, 0.72, 0.70, 0.72, 0.40, 6.5),
        build_player(16, "Tarcisio Lins", "AM", 67.0, 220.0, 0.16, 0.12, 0.25, 1.50, 94.0, 0.84, 0.74, 0.44, 0.84, 0.45, 6.6, career_goals=1),
        build_player(17, "Beto Fagundes", "LW", 66.0, 230.0, 0.15, 0.12, 0.24, 1.52, 92.0, 0.72, 0.58, 0.52, 0.82, 0.45, 6.4, career_goals=1),
        build_player(18, "Wagner Carioca", "ST", 82.0, 218.0, 0.22, 0.12, 0.34, 1.46, 94.0, 0.68, 0.68, 0.72, 0.74, 0.40, 6.4, career_goals=2),
    ]
    teams.append({
        "team_name": "Porto Sol Stella",
        "team_color": [0.0, 0.50, 0.50], # #008080
        "primary_color": "#008080",
        "secondary_color": "#FFD700",
        "formation_override": "4-2-3-1",
        "lineup_indices": list(range(11)),
        "squad": portosol_squad
    })

    return {
        "league_name": "Continental Championship",
        "teams": teams
    }

def generate_managers() -> dict:
    managers = [
        # 1. Branimir Skok (FC Nordvik)
        {
            "name": "Branimir Skok",
            "nationality": "Dalmatian",
            "experience": 28,
            "current_team": "FC Nordvik",
            "defensive_line": 0.35,
            "tempo": 0.40,
            "width": 0.42,
            "pressing_intensity": 0.30,
            "physicality": 0.72,
            "preferred_formation": "4-4-2",
            "attacking_formation": "4-3-3",
            "defensive_formation": "5-3-2",
            "youth_trust": 0.25,
            "loyalty_bias": 0.80,
            "form_sensitivity": 0.30,
            "preferred_min_age": 23,
            "preferred_max_age": 33,
            "budget_flexibility": 0.30,
            "preferred_mass_min": 74.0,
            "preferred_mass_max": 95.0,
            "prized_attribute": "aggression",
            "preferred_playstyle": "physical",
            "traits": 1 | 2 | 4, # HotHead | Loyalist | Pragmatist (7)
            "matches_managed": 142,
            "wins": 68,
            "draws": 38,
            "losses": 36,
            "goals_scored": 210,
            "goals_conceded": 160
        },
        # 2. Sebastián Larrarte (CD Solano)
        {
            "name": "Sebastián Larrarte",
            "nationality": "Platense",
            "experience": 41,
            "current_team": "CD Solano",
            "defensive_line": 0.72,
            "tempo": 0.78,
            "width": 0.82,
            "pressing_intensity": 0.88,
            "physicality": 0.32,
            "preferred_formation": "4-3-3",
            "attacking_formation": "4-3-3",
            "defensive_formation": "4-4-2",
            "youth_trust": 0.80,
            "loyalty_bias": 0.30,
            "form_sensitivity": 0.75,
            "preferred_min_age": 17,
            "preferred_max_age": 26,
            "budget_flexibility": 0.65,
            "preferred_mass_min": 60.0,
            "preferred_mass_max": 80.0,
            "prized_attribute": "vision",
            "preferred_playstyle": "technical",
            "traits": 8 | 128 | 32, # Visionary | MediaSavvy | MindGames (168)
            "matches_managed": 220,
            "wins": 134,
            "draws": 42,
            "losses": 44,
            "goals_scored": 420,
            "goals_conceded": 215
        },
        # 3. Raivo Peet (Valence Athletic)
        {
            "name": "Raivo Peet",
            "nationality": "Hanseatic",
            "experience": 19,
            "current_team": "Valence Athletic",
            "defensive_line": 0.55,
            "tempo": 0.58,
            "width": 0.50,
            "pressing_intensity": 0.62,
            "physicality": 0.55,
            "preferred_formation": "4-2-3-1",
            "attacking_formation": "4-3-3",
            "defensive_formation": "4-4-2",
            "youth_trust": 0.50,
            "loyalty_bias": 0.40,
            "form_sensitivity": 0.72,
            "preferred_min_age": 19,
            "preferred_max_age": 29,
            "budget_flexibility": 0.50,
            "preferred_mass_min": 67.0,
            "preferred_mass_max": 85.0,
            "prized_attribute": "composure",
            "preferred_playstyle": "engine",
            "traits": 16 | 4, # Disciplinarian | Pragmatist (20)
            "matches_managed": 95,
            "wins": 48,
            "draws": 26,
            "losses": 21,
            "goals_scored": 145,
            "goals_conceded": 98
        },
        # 4. Yuki Tsurumoto (Real Maritimo)
        {
            "name": "Yuki Tsurumoto",
            "nationality": "Far Eastern",
            "experience": 35,
            "current_team": "Real Maritimo",
            "defensive_line": 0.60,
            "tempo": 0.55,
            "width": 0.70,
            "pressing_intensity": 0.50,
            "physicality": 0.25,
            "preferred_formation": "3-5-2",
            "attacking_formation": "3-5-2",
            "defensive_formation": "5-3-2",
            "youth_trust": 0.70,
            "loyalty_bias": 0.55,
            "form_sensitivity": 0.45,
            "preferred_min_age": 21,
            "preferred_max_age": 30,
            "budget_flexibility": 0.82,
            "preferred_mass_min": 62.0,
            "preferred_mass_max": 82.0,
            "prized_attribute": "vision",
            "preferred_playstyle": "pace",
            "traits": 64 | 128 | 8, # Sentimental | MediaSavvy | Visionary (200)
            "matches_managed": 178,
            "wins": 92,
            "draws": 44,
            "losses": 42,
            "goals_scored": 305,
            "goals_conceded": 195
        },
        # 5. Dietrich Klausner (Borussia Eisenwald)
        {
            "name": "Dietrich Klausner",
            "nationality": "Germanic",
            "experience": 32,
            "current_team": "Borussia Eisenwald",
            "defensive_line": 0.28,
            "tempo": 0.45,
            "width": 0.38,
            "pressing_intensity": 0.40,
            "physicality": 0.85,
            "preferred_formation": "5-3-2",
            "attacking_formation": "4-3-3",
            "defensive_formation": "5-3-2",
            "youth_trust": 0.30,
            "loyalty_bias": 0.75,
            "form_sensitivity": 0.40,
            "preferred_min_age": 24,
            "preferred_max_age": 34,
            "budget_flexibility": 0.40,
            "preferred_mass_min": 78.0,
            "preferred_mass_max": 96.0,
            "prized_attribute": "aggression",
            "preferred_playstyle": "physical",
            "traits": 16 | 2 | 4, # Disciplinarian | Loyalist | Pragmatist (22)
            "matches_managed": 164,
            "wins": 76,
            "draws": 52,
            "losses": 36,
            "goals_scored": 198,
            "goals_conceded": 132
        },
        # 6. Giancarlo Bellini (Aurora Calcio)
        {
            "name": "Giancarlo Bellini",
            "nationality": "Ligurian",
            "experience": 38,
            "current_team": "Aurora Calcio",
            "defensive_line": 0.68,
            "tempo": 0.65,
            "width": 0.75,
            "pressing_intensity": 0.70,
            "physicality": 0.35,
            "preferred_formation": "4-3-3",
            "attacking_formation": "4-3-3",
            "defensive_formation": "4-4-2",
            "youth_trust": 0.65,
            "loyalty_bias": 0.35,
            "form_sensitivity": 0.60,
            "preferred_min_age": 20,
            "preferred_max_age": 29,
            "budget_flexibility": 0.75,
            "preferred_mass_min": 64.0,
            "preferred_mass_max": 84.0,
            "prized_attribute": "vision",
            "preferred_playstyle": "technical",
            "traits": 8 | 128 | 512, # Visionary | MediaSavvy | Idealist (648)
            "matches_managed": 195,
            "wins": 108,
            "draws": 46,
            "losses": 41,
            "goals_scored": 350,
            "goals_conceded": 190
        },
        # 7. Alistair MacCallum (Highland Thistle FC)
        {
            "name": "Alistair MacCallum",
            "nationality": "Caledonian",
            "experience": 26,
            "current_team": "Highland Thistle FC",
            "defensive_line": 0.48,
            "tempo": 0.75,
            "width": 0.55,
            "pressing_intensity": 0.85,
            "physicality": 0.90,
            "preferred_formation": "4-4-2",
            "attacking_formation": "4-4-2",
            "defensive_formation": "5-3-2",
            "youth_trust": 0.40,
            "loyalty_bias": 0.65,
            "form_sensitivity": 0.50,
            "preferred_min_age": 22,
            "preferred_max_age": 32,
            "budget_flexibility": 0.35,
            "preferred_mass_min": 74.0,
            "preferred_mass_max": 94.0,
            "prized_attribute": "aggression",
            "preferred_playstyle": "engine",
            "traits": 1 | 16 | 4, # HotHead | Disciplinarian | Pragmatist (21)
            "matches_managed": 130,
            "wins": 58,
            "draws": 34,
            "losses": 38,
            "goals_scored": 182,
            "goals_conceded": 156
        },
        # 8. Valdemar Cruz (Porto Sol Stella)
        {
            "name": "Valdemar Cruz",
            "nationality": "Sulista",
            "experience": 29,
            "current_team": "Porto Sol Stella",
            "defensive_line": 0.62,
            "tempo": 0.70,
            "width": 0.78,
            "pressing_intensity": 0.65,
            "physicality": 0.40,
            "preferred_formation": "4-2-3-1",
            "attacking_formation": "4-3-3",
            "defensive_formation": "4-4-2",
            "youth_trust": 0.75,
            "loyalty_bias": 0.30,
            "form_sensitivity": 0.65,
            "preferred_min_age": 18,
            "preferred_max_age": 28,
            "budget_flexibility": 0.70,
            "preferred_mass_min": 63.0,
            "preferred_mass_max": 82.0,
            "prized_attribute": "composure",
            "preferred_playstyle": "technical",
            "traits": 256 | 8 | 32, # Volatile | Visionary | MindGames (296)
            "matches_managed": 148,
            "wins": 82,
            "draws": 32,
            "losses": 34,
            "goals_scored": 274,
            "goals_conceded": 178
        },
        # 9. Free Agent 1: Arthur Pendelton
        {
            "name": "Arthur Pendelton",
            "nationality": "Albion",
            "experience": 45,
            "current_team": "",
            "defensive_line": 0.42,
            "tempo": 0.50,
            "width": 0.48,
            "pressing_intensity": 0.45,
            "physicality": 0.65,
            "preferred_formation": "4-4-2",
            "attacking_formation": "4-3-3",
            "defensive_formation": "5-4-1",
            "youth_trust": 0.35,
            "loyalty_bias": 0.85,
            "form_sensitivity": 0.25,
            "preferred_min_age": 25,
            "preferred_max_age": 35,
            "budget_flexibility": 0.45,
            "preferred_mass_min": 72.0,
            "preferred_mass_max": 92.0,
            "prized_attribute": "composure",
            "preferred_playstyle": "physical",
            "traits": 2 | 4 | 64, # Loyalist | Pragmatist | Sentimental (70)
            "matches_managed": 310,
            "wins": 142,
            "draws": 88,
            "losses": 80,
            "goals_scored": 420,
            "goals_conceded": 330
        },
        # 10. Free Agent 2: Mateusz Wilczek
        {
            "name": "Mateusz Wilczek",
            "nationality": "Sarmatian",
            "experience": 22,
            "current_team": "",
            "defensive_line": 0.65,
            "tempo": 0.80,
            "width": 0.60,
            "pressing_intensity": 0.92,
            "physicality": 0.68,
            "preferred_formation": "4-3-3",
            "attacking_formation": "4-3-3",
            "defensive_formation": "4-4-2",
            "youth_trust": 0.85,
            "loyalty_bias": 0.20,
            "form_sensitivity": 0.80,
            "preferred_min_age": 18,
            "preferred_max_age": 26,
            "budget_flexibility": 0.60,
            "preferred_mass_min": 66.0,
            "preferred_mass_max": 86.0,
            "prized_attribute": "aggression",
            "preferred_playstyle": "engine",
            "traits": 1 | 8 | 128, # HotHead | Visionary | MediaSavvy (137)
            "matches_managed": 80,
            "wins": 42,
            "draws": 16,
            "losses": 22,
            "goals_scored": 150,
            "goals_conceded": 105
        }
    ]
    return {"managers": managers}

def generate_referees() -> dict:
    referees = [
        # 1. Domagoj Vrban — Authoritative veteran, highly composed, consistent
        {
            "name": "Domagoj Vrban",
            "nationality": "Dalmatian",
            "experience": 34,
            "strictness": 0.72,
            "consistency": 0.85,
            "composure": 0.88,
            "unprofessionalism": 0.04,
            "incoherence": 0.08,
            "reputation": 0.90,
            "matches_officiated": 185,
            "fouls_awarded": 420,
            "penalties_awarded": 32,
            "red_cards_issued": 14,
            "matchup_history": {}
        },
        # 2. Ingrid Vaarmo — World-class elite official, razor-sharp consistency and iron composure
        {
            "name": "Ingrid Vaarmo",
            "nationality": "Nordlandic",
            "experience": 42,
            "strictness": 0.88,
            "consistency": 0.94,
            "composure": 0.96,
            "unprofessionalism": 0.01,
            "incoherence": 0.03,
            "reputation": 0.98,
            "matches_officiated": 240,
            "fouls_awarded": 560,
            "penalties_awarded": 48,
            "red_cards_issued": 22,
            "matchup_history": {}
        },
        # 3. Kjetil Ornseth — Lenient, easily confused under pressure, low strictness
        {
            "name": "Kjetil Ornseth",
            "nationality": "Nordlandic",
            "experience": 12,
            "strictness": 0.32,
            "consistency": 0.42,
            "composure": 0.35,
            "unprofessionalism": 0.18,
            "incoherence": 0.65,
            "reputation": 0.40,
            "matches_officiated": 52,
            "fouls_awarded": 88,
            "penalties_awarded": 6,
            "red_cards_issued": 2,
            "matchup_history": {}
        },
        # 4. Tomas Errecarte — Fiery, volatile, prone to emotion and heat-of-the-moment cards
        {
            "name": "Tomas Errecarte",
            "nationality": "Platense",
            "experience": 24,
            "strictness": 0.65,
            "consistency": 0.58,
            "composure": 0.48,
            "unprofessionalism": 0.42,
            "incoherence": 0.35,
            "reputation": 0.62,
            "matches_officiated": 118,
            "fouls_awarded": 310,
            "penalties_awarded": 26,
            "red_cards_issued": 18,
            "matchup_history": {}
        },
        # 5. Arjun Dharmaraj — Calm, balanced, highly composed middle-of-the-road referee
        {
            "name": "Arjun Dharmaraj",
            "nationality": "Subcontinental",
            "experience": 20,
            "strictness": 0.50,
            "consistency": 0.68,
            "composure": 0.78,
            "unprofessionalism": 0.10,
            "incoherence": 0.30,
            "reputation": 0.68,
            "matches_officiated": 95,
            "fouls_awarded": 210,
            "penalties_awarded": 16,
            "red_cards_issued": 7,
            "matchup_history": {}
        },
        # 6. Petru Balint — Strict card-happy arbiter with erratic penalty calls
        {
            "name": "Petru Balint",
            "nationality": "Carpathian",
            "experience": 11,
            "strictness": 0.82,
            "consistency": 0.35,
            "composure": 0.42,
            "unprofessionalism": 0.30,
            "incoherence": 0.55,
            "reputation": 0.45,
            "matches_officiated": 46,
            "fouls_awarded": 140,
            "penalties_awarded": 15,
            "red_cards_issued": 9,
            "matchup_history": {}
        },
        # 7. Jean-Luc Vaneck — Veteran laissez-faire referee, lets the game flow, rarely whistles
        {
            "name": "Jean-Luc Vaneck",
            "nationality": "Gallic",
            "experience": 38,
            "strictness": 0.24,
            "consistency": 0.78,
            "composure": 0.82,
            "unprofessionalism": 0.08,
            "incoherence": 0.15,
            "reputation": 0.82,
            "matches_officiated": 210,
            "fouls_awarded": 340,
            "penalties_awarded": 18,
            "red_cards_issued": 6,
            "matchup_history": {}
        },
        # 8. Kenzo Takahashi — Methodical, disciplined, uncompromising rulebook follower
        {
            "name": "Kenzo Takahashi",
            "nationality": "Far Eastern",
            "experience": 29,
            "strictness": 0.78,
            "consistency": 0.90,
            "composure": 0.86,
            "unprofessionalism": 0.02,
            "incoherence": 0.06,
            "reputation": 0.85,
            "matches_officiated": 155,
            "fouls_awarded": 390,
            "penalties_awarded": 28,
            "red_cards_issued": 11,
            "matchup_history": {}
        }
    ]
    return {"referees": referees}

def main():
    base_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    data_dir = os.path.join(base_dir, "data")
    os.makedirs(data_dir, exist_ok=True)

    league = generate_league()
    managers = generate_managers()
    referees = generate_referees()

    league_path = os.path.join(data_dir, "league.json")
    with open(league_path, "w", encoding="utf-8") as f:
        json.dump(league, f, indent=2, ensure_ascii=False)
    print(f"Generated {league_path}: {len(league['teams'])} teams, {sum(len(t['squad']) for t in league['teams'])} players total.")

    managers_path = os.path.join(data_dir, "managers.json")
    with open(managers_path, "w", encoding="utf-8") as f:
        json.dump(managers, f, indent=2, ensure_ascii=False)
    print(f"Generated {managers_path}: {len(managers['managers'])} managers.")

    referees_path = os.path.join(data_dir, "referees.json")
    with open(referees_path, "w", encoding="utf-8") as f:
        json.dump(referees, f, indent=2, ensure_ascii=False)
    print(f"Generated {referees_path}: {len(referees['referees'])} referees.")

if __name__ == "__main__":
    main()
