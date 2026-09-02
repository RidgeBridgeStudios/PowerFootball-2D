#!/usr/bin/env python3
"""
tools/expand_database.py

Generates 8 realistic Division 2 (Tier 2) clubs mirroring European second tiers:
- Olympique Montclair (France)
- SV Donau Wien (Austria)
- Athletic Bilbao Nova (Spain)
- Sporting Lisboa Norte (Portugal)
- Yorkshire United (England)
- Kjøbenhavn Boldklub (Denmark)
- Feyenoord Haven (Netherlands)
- AC Bergamo (Italy)

Each club has:
- 18 strictly bounded players (GK, DF, MF, FW) matching all physical/mental invariants
- 11 lineup_indices with GK at slot 0
- 5 staff members (Assistant Manager, Head Physio, Tactical Analyst, Fitness Coach, Chief Scout)
- 1 assigned manager with full personality/tactics
- Full entries in data/league.json, data/players.json, data/managers.json, data/staff.json
"""

import json
import os
import random

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")

random.seed(1337)

CLUBS_SPEC = [
    {
        "name": "Olympique Montclair",
        "nat": "French",
        "lang": "French",
        "rep": 0.48,
        "stature": "Lower League Underdog",
        "transfer_budget": 3500000,
        "wage_budget_weekly": 65000,
        "primary": "#1A3B6B",
        "secondary": "#E8B135",
        "color": [0.10, 0.23, 0.42],
        "formation": "4-3-3",
        "mgr_name": "Henri Laurent",
        "mgr_age": 49,
    },
    {
        "name": "SV Donau Wien",
        "nat": "Austrian",
        "lang": "German",
        "rep": 0.44,
        "stature": "Lower League Underdog",
        "transfer_budget": 2800000,
        "wage_budget_weekly": 55000,
        "primary": "#2D5A27",
        "secondary": "#FFFFFF",
        "color": [0.18, 0.35, 0.15],
        "formation": "4-4-2",
        "mgr_name": "Florian Gruber",
        "mgr_age": 45,
    },
    {
        "name": "Athletic Bilbao Nova",
        "nat": "Spanish",
        "lang": "Spanish",
        "rep": 0.50,
        "stature": "Lower League Underdog",
        "transfer_budget": 4200000,
        "wage_budget_weekly": 72000,
        "primary": "#C8102E",
        "secondary": "#FFFFFF",
        "color": [0.78, 0.06, 0.18],
        "formation": "4-2-3-1",
        "mgr_name": "Iker Echevarria",
        "mgr_age": 52,
    },
    {
        "name": "Sporting Lisboa Norte",
        "nat": "Portuguese",
        "lang": "Portuguese",
        "rep": 0.49,
        "stature": "Lower League Underdog",
        "transfer_budget": 3800000,
        "wage_budget_weekly": 68000,
        "primary": "#006633",
        "secondary": "#FFCC00",
        "color": [0.0, 0.40, 0.20],
        "formation": "4-3-3",
        "mgr_name": "Diogo Valente",
        "mgr_age": 43,
    },
    {
        "name": "Yorkshire United",
        "nat": "English",
        "lang": "English",
        "rep": 0.52,
        "stature": "Lower League Underdog",
        "transfer_budget": 5500000,
        "wage_budget_weekly": 85000,
        "primary": "#003399",
        "secondary": "#FFD700",
        "color": [0.0, 0.20, 0.60],
        "formation": "4-4-2",
        "mgr_name": "Callum Bennett",
        "mgr_age": 47,
    },
    {
        "name": "Kjøbenhavn Boldklub",
        "nat": "Danish",
        "lang": "Danish",
        "rep": 0.45,
        "stature": "Lower League Underdog",
        "transfer_budget": 3000000,
        "wage_budget_weekly": 58000,
        "primary": "#002B49",
        "secondary": "#E31B23",
        "color": [0.0, 0.17, 0.29],
        "formation": "3-5-2",
        "mgr_name": "Jesper Moller",
        "mgr_age": 51,
    },
    {
        "name": "Feyenoord Haven",
        "nat": "Dutch",
        "lang": "Dutch",
        "rep": 0.47,
        "stature": "Lower League Underdog",
        "transfer_budget": 3400000,
        "wage_budget_weekly": 62000,
        "primary": "#D00000",
        "secondary": "#000000",
        "color": [0.82, 0.0, 0.0],
        "formation": "4-3-3",
        "mgr_name": "Lars van Dijk",
        "mgr_age": 46,
    },
    {
        "name": "AC Bergamo",
        "nat": "Italian",
        "lang": "Italian",
        "rep": 0.51,
        "stature": "Lower League Underdog",
        "transfer_budget": 4800000,
        "wage_budget_weekly": 78000,
        "primary": "#1E2A38",
        "secondary": "#007ACC",
        "color": [0.12, 0.16, 0.22],
        "formation": "3-5-2",
        "mgr_name": "Matteo Moretti",
        "mgr_age": 48,
    },
]

ROLES_18 = ["GK", "LB", "CB", "CB", "RB", "LM", "CM", "DM", "RM", "ST", "ST", "GK", "CB", "RB", "CM", "AM", "ST", "CB"]

FIRST_NAMES = {
    "French": ["Lucas", "Maxime", "Antoine", "Theo", "Alexandre", "Julien", "Clement", "Nicolas", "Romain", "Mathieu", "Hugo", "Adrien", "Florian", "Bastien", "Leo", "Gabin", "Valentin", "Arthur"],
    "Austrian": ["Lukas", "Tobias", "Maximilian", "Paul", "Florian", "Felix", "David", "Simon", "Fabian", "Julian", "Moritz", "Sebastian", "Philipp", "Elias", "Alexander", "Jakob", "Jonas", "Niklas"],
    "Spanish": ["Alejandro", "Daniel", "Pablo", "Alvaro", "Adrian", "David", "Diego", "Javier", "Mario", "Sergio", "Marcos", "Manuel", "Carlos", "Ivan", "Ruben", "Gonzalo", "Raul", "Jorge"],
    "Portuguese": ["Joao", "Rodrigo", "Martim", "Afonso", "Francisco", "Tomas", "Duarte", "Miguel", "Tiago", "Diogo", "Pedro", "Goncalo", "Guilherme", "Lucas", "Santiago", "Bernardo", "Rafael", "Andre"],
    "English": ["Oliver", "George", "Harry", "Jack", "Jacob", "Noah", "Charlie", "Thomas", "Oscar", "William", "James", "Henry", "Alfie", "Leo", "Archie", "Arthur", "Logan", "Freddie"],
    "Danish": ["William", "Noah", "Lucas", "Victor", "Emil", "Oliver", "Magnus", "Frederik", "Alexander", "Christian", "Elias", "Mads", "Mikkel", "Valdemar", "Oscar", "Malthe", "Mathias", "Sebastian"],
    "Dutch": ["Daan", "Sem", "Lucas", "Milan", "Levi", "Finn", "Jesse", "Liam", "Thomas", "Bram", "Luuk", "Sam", "Thijs", "Tim", "Jayden", "Lars", "Ruben", "Mees"],
    "Italian": ["Francesco", "Alessandro", "Leonardo", "Lorenzo", "Mattia", "Andrea", "Gabriele", "Matteo", "Tommaso", "Riccardo", "Edoardo", "Federico", "Giuseppe", "Antonio", "Marco", "Pietro", "Davide", "Christian"],
}

LAST_NAMES = {
    "French": ["Dubois", "Moreau", "Laurent", "Simon", "Michel", "Lefebvre", "Leroy", "Roux", "David", "Bertrand", "Morel", "Fournier", "Girard", "Bonnet", "Dupont", "Lambert", "Fontaine", "Rousseau"],
    "Austrian": ["Gruber", "Bauer", "Pichler", "Steiner", "Moser", "Mayer", "Hofer", "Leitner", "Berger", "Fuchs", "Eder", "Fischer", "Schmid", "Weber", "Schwarz", "Maier", "Schneider", "Reiter"],
    "Spanish": ["Garcia", "Rodriguez", "Gonzalez", "Fernandez", "Lopez", "Martinez", "Sanchez", "Perez", "Gomez", "Martin", "Jimenez", "Ruiz", "Hernandez", "Diaz", "Moreno", "Alvarez", "Romero", "Alonso"],
    "Portuguese": ["Silva", "Santos", "Ferreira", "Pereira", "Oliveira", "Costa", "Rodrigues", "Martins", "Jesus", "Sousa", "Fernandes", "Goncalves", "Gomes", "Lopes", "Marques", "Alves", "Almeida", "Ribeiro"],
    "English": ["Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson", "Davies", "Robinson", "Wright", "Thompson", "Evans", "Walker", "White", "Roberts", "Green", "Hall", "Wood"],
    "Danish": ["Nielsen", "Jensen", "Hansen", "Pedersen", "Andersen", "Christensen", "Larsen", "Sorensen", "Rasmussen", "Jorgensen", "Petersen", "Madsen", "Kristensen", "Olsen", "Thomsen", "Christiansen", "Poulsen", "Johansen"],
    "Dutch": ["de Jong", "Jansen", "de Vries", "van den Berg", "van Dijk", "Bakker", "Janssen", "Visser", "Smit", "Meijer", "de Boer", "Mulder", "de Groot", "Bos", "Vos", "Peters", "Hendriks", "van Leeuwen"],
    "Italian": ["Rossi", "Russo", "Ferrari", "Esposito", "Bianchi", "Romano", "Colombo", "Ricci", "Marino", "Greco", "Bruno", "Gallo", "Conti", "De Luca", "Mancini", "Costa", "Giordano", "Rizzo"],
}

def generate_player(p_idx, role, nat, lang, team_name):
    first = FIRST_NAMES[nat][p_idx % len(FIRST_NAMES[nat])]
    last = LAST_NAMES[nat][p_idx % len(LAST_NAMES[nat])]
    pname = f"{first} {last}"
    shirt_num = p_idx + 1 if p_idx < 11 else p_idx + 10

    # Attributes tailored for solid Tier 2 competition
    is_starter = p_idx < 11
    quality_mult = random.uniform(0.55, 0.72) if is_starter else random.uniform(0.48, 0.65)
    
    mass = 80.0 if role == "GK" else (78.0 if "CB" in role else random.uniform(68.0, 78.0))
    top_speed = 185.0 if role == "GK" else random.uniform(205.0, 235.0)
    accel = 0.28 if role == "GK" else random.uniform(0.20, 0.28)
    stamina = 90.0 if role == "GK" else random.uniform(92.0, 108.0)
    reflexes = random.uniform(0.68, 0.82) if role == "GK" else random.uniform(0.40, 0.60)
    close_ctrl = random.uniform(0.40, 0.55) if role == "GK" else random.uniform(0.58, 0.76)
    vision = random.uniform(0.40, 0.55) if role == "GK" else random.uniform(0.52, 0.75)
    composure = random.uniform(0.55, 0.75)
    aggression = random.uniform(0.40, 0.70)
    form = round(random.uniform(6.0, 7.5), 1)

    det = round(random.uniform(0.50, 0.80), 2)
    work = round(random.uniform(0.50, 0.80), 2)
    lead = round(random.uniform(0.40, 0.75), 2)
    temp = round(random.uniform(0.50, 0.90), 2)
    prof = round(random.uniform(0.55, 0.85), 2)
    amb = round(random.uniform(0.50, 0.80), 2)
    loy = round(random.uniform(0.50, 0.80), 2)
    adapt = round(random.uniform(0.55, 0.85), 2)
    rep = round(quality_mult, 2)

    wage = int(round(random.uniform(2500, 6500) / 100.0) * 100)
    mval = int(round(wage * 52 * random.uniform(3.0, 6.0) / 500.0) * 500)

    dob_year = random.randint(1996, 2005)
    dob_month = random.randint(1, 12)
    dob_day = random.randint(1, 28)
    dob = f"{dob_year}-{dob_month:02d}-{dob_day:02d}"

    spoken = [{"language": lang, "proficiency": 1.0, "level": "Native"}]
    if lang != "English":
        spoken.append({"language": "English", "proficiency": 0.75, "level": "Fluent"})

    squad_status = "Regular Starter" if is_starter else "Squad Player"
    if p_idx in (2, 9):
        squad_status = "Important"

    return {
        "player_name": pname,
        "shirt_number": shirt_num,
        "position_role": role,
        "mass": round(mass, 1),
        "top_speed": round(top_speed, 1),
        "acceleration_time": round(accel, 2),
        "friction_time": 0.12,
        "turning_penalty": 0.35,
        "sprint_multiplier": 1.40,
        "stamina_max": round(stamina, 1),
        "stamina_drain": 18.0,
        "stamina_recover": 9.0,
        "vision": round(vision, 2),
        "composure": round(composure, 2),
        "aggression": round(aggression, 2),
        "formation_ball_weight": 0.35,
        "close_control": round(close_ctrl, 2),
        "reflexes": round(reflexes, 2),
        "determination": det,
        "work_rate": work,
        "leadership": lead,
        "temperament": temp,
        "professionalism": prof,
        "ambition": amb,
        "loyalty": loy,
        "adaptability": adapt,
        "traits": 0,
        "player_reputation": rep,
        "wage_weekly": wage,
        "contract_years": random.randint(2, 4),
        "release_clause": 0,
        "squad_status": squad_status,
        "morale": round(random.uniform(0.60, 0.78), 2),
        "market_value": mval,
        "form": form,
        "career_goals": 0,
        "career_assists": 0,
        "last_match_rating": 0.0,
        "is_unavailable": False,
        "nationality": nat,
        "secondary_nationality": "",
        "date_of_birth": dob,
        "spoken_languages": spoken,
        "is_captain": (p_idx == 2),
    }

def generate_staff(spec):
    nat = spec["nat"]
    lang = spec["lang"]
    tname = spec["name"]
    roles = [
        ("Assistant Manager", 0.72, 0.68, 0.50, 0.75, 4500),
        ("Head Physio", 0.45, 0.55, 0.85, 0.45, 3800),
        ("Tactical Analyst", 0.55, 0.65, 0.40, 0.82, 3400),
        ("Fitness Coach", 0.78, 0.50, 0.65, 0.50, 3200),
        ("Chief Scout", 0.50, 0.82, 0.40, 0.65, 3600),
    ]
    out = []
    for s_idx, (role_name, coach, judge, physio, tact, sal) in enumerate(roles):
        first = FIRST_NAMES[nat][(s_idx + 3) % len(FIRST_NAMES[nat])]
        last = LAST_NAMES[nat][(s_idx + 3) % len(LAST_NAMES[nat])]
        dob = f"{1975 + s_idx}-04-{10 + s_idx}"
        spoken = [{"language": lang, "proficiency": 1.0, "level": "Native"}]
        if lang != "English":
            spoken.append({"language": "English", "proficiency": 0.75, "level": "Fluent"})
        out.append({
            "staff_name": f"{first} {last}",
            "role": role_name,
            "team_name": tname,
            "nationality": nat,
            "secondary_nationality": "",
            "date_of_birth": dob,
            "experience": random.randint(15, 28),
            "coaching": coach,
            "judging_ability": judge,
            "physiotherapy": physio,
            "tactical_knowledge": tact,
            "salary_weekly": sal,
            "contract_years": 3,
            "spoken_languages": spoken,
        })
    return out

def generate_manager(spec):
    nat = spec["nat"]
    lang = spec["lang"]
    tname = spec["name"]
    mname = spec["mgr_name"]
    dob = f"{2026 - spec['mgr_age']}-03-15"
    spoken = [{"language": lang, "proficiency": 1.0, "level": "Native"}]
    if lang != "English":
        spoken.append({"language": "English", "proficiency": 0.80, "level": "Fluent"})
    return {
        "name": mname,
        "nationality": nat,
        "experience": random.randint(18, 30),
        "current_team": tname,
        "reputation": round(spec["rep"] - 0.02, 2),
        "board_confidence": 0.70,
        "contract_years": 3,
        "salary_weekly": 15000,
        "referee_respect": 0.60,
        "defensive_line": 0.45,
        "tempo": 0.50,
        "width": 0.50,
        "pressing_intensity": 0.50,
        "physicality": 0.60,
        "preferred_formation": spec["formation"],
        "attacking_formation": "4-3-3",
        "defensive_formation": "5-3-2",
        "youth_trust": 0.55,
        "loyalty_bias": 0.60,
        "form_sensitivity": 0.50,
        "preferred_min_age": 20,
        "preferred_max_age": 32,
        "budget_flexibility": 0.40,
        "preferred_mass_min": 70.0,
        "preferred_mass_max": 90.0,
        "prized_attribute": "vision",
        "preferred_playstyle": "technical",
        "traits": 3,
        "matches_managed": 80,
        "wins": 34,
        "draws": 22,
        "losses": 24,
        "goals_scored": 110,
        "goals_conceded": 95,
        "secondary_nationality": "",
        "date_of_birth": dob,
        "spoken_languages": spoken,
    }

def main():
    league_path = os.path.join(DATA_DIR, "league.json")
    players_path = os.path.join(DATA_DIR, "players.json")
    managers_path = os.path.join(DATA_DIR, "managers.json")
    staff_path = os.path.join(DATA_DIR, "staff.json")

    with open(league_path, "r", encoding="utf-8") as f:
        league_data = json.load(f)
    with open(players_path, "r", encoding="utf-8") as f:
        players_data = json.load(f)
    with open(managers_path, "r", encoding="utf-8") as f:
        managers_data = json.load(f)
    with open(staff_path, "r", encoding="utf-8") as f:
        staff_data = json.load(f)

    existing_team_names = {t["team_name"] for t in league_data["teams"]}

    new_teams = []
    all_new_players = []
    all_new_staff = []
    all_new_managers = []

    for spec in CLUBS_SPEC:
        if spec["name"] in existing_team_names:
            print(f"Skipping {spec['name']}, already in database.")
            continue

        squad = []
        for p_idx in range(18):
            role = ROLES_18[p_idx]
            p = generate_player(p_idx, role, spec["nat"], spec["lang"], spec["name"])
            squad.append(p)
            flat_p = dict(p)
            flat_p["team_name"] = spec["name"]
            all_new_players.append(flat_p)

        staff_list = generate_staff(spec)
        all_new_staff.extend(staff_list)

        mgr = generate_manager(spec)
        all_new_managers.append(mgr)

        lineup = [i for i in range(11)]  # Indices 0..10

        team_dict = {
            "team_name": spec["name"],
            "team_color": spec["color"],
            "primary_color": spec["primary"],
            "secondary_color": spec["secondary"],
            "formation_override": spec["formation"],
            "lineup_indices": lineup,
            "reputation": spec["rep"],
            "stature": spec["stature"],
            "transfer_budget": spec["transfer_budget"],
            "wage_budget_weekly": spec["wage_budget_weekly"],
            "squad": squad,
            "staff": staff_list,
        }
        new_teams.append(team_dict)

    if new_teams:
        league_data["teams"].extend(new_teams)
        players_data["players"].extend(all_new_players)
        managers_data["managers"].extend(all_new_managers)
        staff_data["staff"].extend(all_new_staff)

        with open(league_path, "w", encoding="utf-8") as f:
            json.dump(league_data, f, indent=2, ensure_ascii=False)
        with open(players_path, "w", encoding="utf-8") as f:
            json.dump(players_data, f, indent=2, ensure_ascii=False)
        with open(managers_path, "w", encoding="utf-8") as f:
            json.dump(managers_data, f, indent=2, ensure_ascii=False)
        with open(staff_path, "w", encoding="utf-8") as f:
            json.dump(staff_data, f, indent=2, ensure_ascii=False)

        print(f"Successfully added {len(new_teams)} new clubs, {len(all_new_players)} players, {len(all_new_managers)} managers, {len(all_new_staff)} staff.")
    else:
        print("No new teams needed to be added.")

if __name__ == "__main__":
    main()
