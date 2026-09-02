#!/usr/bin/env python3
"""
update_db_all.py — Overhauls the entire database generator (tools/generate_db.py) and
regenerates Layer 4 Club World JSON databases:
- res://data/league.json
- res://data/players.json
- res://data/managers.json
- res://data/referees.json
- res://data/staff.json

Assigns real-world nationalities, Football Manager-style spoken languages with proficiency levels,
and realistic full birth dates across all players, managers, referees, and backroom staff.
"""

import os
import sys
import json

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA_DIR = os.path.join(BASE_DIR, "data")
TOOLS_DIR = os.path.join(BASE_DIR, "tools")

# 1. Spoken languages resolution map
NAT_TO_PRIMARY_LANG = {
    "Norwegian": "Norwegian",
    "Swedish": "Swedish",
    "Danish": "Danish",
    "Spanish": "Spanish",
    "French": "French",
    "German": "German",
    "Italian": "Italian",
    "Scottish": "English",
    "English": "English",
    "Portuguese": "Portuguese",
    "Croatian": "Croatian",
    "Dutch": "Dutch",
    "Polish": "Polish",
    "Belgian": "French",
    "Argentine": "Spanish",
    "Brazilian": "Portuguese",
    "Austrian": "German",
    "Swiss": "German",
    "Irish": "English",
    "Romanian": "Romanian",
    "Japanese": "Japanese"
}

TEAM_TO_CLUB_LANG = {
    "FC Nordvik": "Norwegian",
    "CD Solano": "Spanish",
    "Valence Athletic": "French",
    "Real Maritimo": "Spanish",
    "Borussia Eisenwald": "German",
    "Aurora Calcio": "Italian",
    "Highland Thistle FC": "English",
    "Porto Sol Stella": "Portuguese"
}

# 2. Player Nationality & Dual Nationality map
PLAYER_BIO = {
    # FC Nordvik (Norway)
    "Mads Dahl": ("Norwegian", ""),
    "Erik Lund": ("Norwegian", ""),
    "Halvard Brann": ("Norwegian", ""),
    "Sigurd Voss": ("Norwegian", ""),
    "Torben Hauge": ("Norwegian", ""),
    "Jonas Elv": ("Swedish", ""),
    "Olav Strand": ("Norwegian", ""),
    "Niklas Borg": ("Norwegian", ""),
    "Rune Kval": ("Norwegian", ""),
    "Henrik Ask": ("Norwegian", ""),
    "Petter Naess": ("Norwegian", ""),
    "Emil Lind": ("Danish", ""),
    "Rasmus Holst": ("Danish", ""),
    "Joakim Berg": ("Swedish", ""),
    "Stian Mork": ("Norwegian", ""),
    "Magnus Rygg": ("Norwegian", ""),
    "Vidar Krog": ("Norwegian", ""),
    "Andreas Solberg": ("Norwegian", ""),

    # CD Solano (Spain)
    "Carlos Vega": ("Spanish", ""),
    "Luis Ferrer": ("Spanish", ""),
    "Mateo Ruiz": ("Argentine", "Spanish"),
    "Diego Pons": ("Spanish", ""),
    "Andres Mora": ("Spanish", ""),
    "Pablo Cano": ("Spanish", ""),
    "Rafael Soto": ("Spanish", ""),
    "Marco Reyes": ("Spanish", ""),
    "Javier Tur": ("Spanish", ""),
    "Bruno Tena": ("Spanish", ""),
    "Ivan Blasco": ("Spanish", ""),
    "Joaquin Giner": ("Spanish", ""),
    "Felix Navarro": ("Spanish", ""),
    "Santi Cordero": ("Spanish", ""),
    "Alejandro Blesa": ("Spanish", ""),
    "Dani Osorio": ("Portuguese", "Spanish"),
    "Alvaro Ribera": ("Spanish", ""),
    "Mario Gil": ("Spanish", ""),

    # Valence Athletic (France)
    "Luc Renard": ("Belgian", "French"),
    "Clement Bastien": ("French", ""),
    "Henri Dupont": ("French", ""),
    "Maxime Laurent": ("French", ""),
    "Julien Mercier": ("French", ""),
    "Romain Vasseur": ("French", ""),
    "Theo Fontaine": ("French", ""),
    "Gabriel Moreau": ("French", ""),
    "Antoine Giraud": ("French", "Spanish"),
    "Sebastien Fabre": ("French", ""),
    "Alexandre Roche": ("French", ""),
    "Nicolas Perrin": ("French", ""),
    "Florian Blanc": ("French", ""),
    "Mathieu Clement": ("French", ""),
    "Adrien Caron": ("French", ""),
    "Tristan Colin": ("French", ""),
    "Valentin Rey": ("French", ""),
    "Loic Dumas": ("French", ""),

    # Real Maritimo (Spain)
    "Inigo Sola": ("Spanish", ""),
    "Sergio Calvo": ("Spanish", ""),
    "Tiago Trindade": ("Portuguese", ""),
    "Marcos Roldan": ("Spanish", ""),
    "Borja Lledo": ("Spanish", ""),
    "Nuno Sequeira": ("Portuguese", ""),
    "Lucas Andrade": ("Brazilian", "Portuguese"),
    "Adrian Beltran": ("Spanish", ""),
    "Gabriel Faria": ("Brazilian", "Spanish"),
    "Felipe Matos": ("Brazilian", ""),
    "Ruben Gines": ("Spanish", ""),
    "Bernardo Pais": ("Portuguese", ""),
    "Alvaro Quiles": ("Spanish", ""),
    "Hector Soler": ("Spanish", ""),
    "Goncalo Esteves": ("Portuguese", ""),
    "Victor Baeza": ("Spanish", ""),
    "Caio Silveira": ("Brazilian", ""),
    "Cesar Alarcon": ("Spanish", ""),

    # Borussia Eisenwald (Germany)
    "Lukas Weber": ("German", ""),
    "Max Richter": ("German", ""),
    "Stefan Brandt": ("German", ""),
    "Tobias Keller": ("German", ""),
    "Jonas Bauer": ("German", ""),
    "Felix Schmidt": ("German", ""),
    "Florian Wolf": ("German", ""),
    "Marcel Becker": ("German", ""),
    "Christoph Gruber": ("Austrian", "German"),
    "Jan Hoffmann": ("German", ""),
    "David Wagner": ("German", ""),
    "Tim Lehmann": ("German", ""),
    "Leon Zimmermann": ("German", ""),
    "Moritz Frank": ("German", ""),
    "Nico Hartmann": ("German", ""),
    "Julian Hofer": ("Austrian", ""),
    "Philipp Krause": ("German", ""),
    "Sven Meier": ("Swiss", "German"),

    # Aurora Calcio (Italy)
    "Lorenzo Ricci": ("Italian", ""),
    "Matteo Rossi": ("Italian", ""),
    "Andrea Conti": ("Italian", ""),
    "Marco Esposito": ("Italian", ""),
    "Davide Russo": ("Italian", ""),
    "Filippo Ferrari": ("Italian", ""),
    "Luca Bianchi": ("Italian", ""),
    "Simone Romano": ("Italian", ""),
    "Federico Marini": ("Italian", ""),
    "Dario Lovric": ("Croatian", "Italian"),
    "Gabriele Moretti": ("Italian", ""),
    "Tommaso Rinaldi": ("Italian", ""),
    "Edoardo Costa": ("Italian", ""),
    "Christian De Luca": ("Italian", ""),
    "Alessandro Bruno": ("Italian", ""),
    "Mattia Vitale": ("Italian", ""),
    "Nicolas Benitez": ("Argentine", "Italian"),
    "Jacopo Serra": ("Italian", ""),

    # Highland Thistle FC (Scotland)
    "Callum Ross": ("Scottish", ""),
    "Scott MacLeod": ("Scottish", ""),
    "Craig Ferguson": ("Scottish", ""),
    "Fraser Boyd": ("Scottish", ""),
    "Euan Campbell": ("Scottish", ""),
    "Ross Stewart": ("Scottish", ""),
    "Cameron Blair": ("Scottish", ""),
    "Kieran MacIntyre": ("Scottish", ""),
    "Bradley Walker": ("English", "Scottish"),
    "Liam Morrison": ("Scottish", ""),
    "Jamie Fletcher": ("Scottish", ""),
    "Lewis Sinclair": ("Scottish", ""),
    "Douglas Kerr": ("Scottish", ""),
    "Gregor Forsyth": ("Scottish", ""),
    "Rory MacLean": ("Scottish", ""),
    "Declan Ward": ("English", ""),
    "Connor Gallagher": ("Irish", ""),
    "Murray Henderson": ("Scottish", ""),

    # Porto Sol Stella (Portugal)
    "Andre Pinto": ("Portuguese", ""),
    "Diogo Ramos": ("Portuguese", ""),
    "Tiago Neves": ("Portuguese", ""),
    "Miguel Rocha": ("Portuguese", ""),
    "Joao Pedro Silva": ("Portuguese", ""),
    "Bruno Carvalho": ("Portuguese", ""),
    "Pedro Fonseca": ("Portuguese", ""),
    "Rafael Teixeira": ("Portuguese", ""),
    "Leonardo Santos": ("Brazilian", "Portuguese"),
    "Goncalo Barreto": ("Portuguese", ""),
    "Afonso Duarte": ("Portuguese", ""),
    "Rui Coutinho": ("Portuguese", ""),
    "Martim Peixoto": ("Portuguese", ""),
    "Tomas Brandao": ("Portuguese", ""),
    "Matheus Lima": ("Brazilian", ""),
    "Fabio Antunes": ("Portuguese", ""),
    "Rodrigo Pinho": ("Brazilian", ""),
    "Henrique Seixas": ("Portuguese", "")
}

def make_player_dob(name: str, shirt_number: int) -> str:
    h = sum(ord(c) for c in name) + shirt_number * 37
    is_starter = shirt_number <= 11
    if is_starter:
        birth_year = 1995 + (h % 9)  # ages 23-31
    elif shirt_number <= 16:
        birth_year = 2000 + (h % 5)  # ages 22-26
    else:
        birth_year = 2005 + (h % 4)  # ages 18-21
    birth_month = 1 + (h * 3 % 12)
    birth_day = 1 + (h * 7 % 28)
    return f"{birth_year:04d}-{birth_month:02d}-{birth_day:02d}"

def make_player_languages(nat: str, sec_nat: str, team_name: str, shirt_number: int) -> list:
    prim_lang = NAT_TO_PRIMARY_LANG.get(nat, "English")
    club_lang = TEAM_TO_CLUB_LANG.get(team_name, "English")
    is_starter = shirt_number <= 11

    langs = []
    # 1. Native mother tongue
    langs.append({"language": prim_lang, "proficiency": 1.0, "level": "Native"})

    # 2. Club language if living in a different country
    if club_lang != prim_lang:
        langs.append({"language": club_lang, "proficiency": 0.85 if is_starter else 0.70, "level": "Fluent" if is_starter else "Basic"})

    # 3. Secondary nationality language
    if sec_nat:
        sec_lang = NAT_TO_PRIMARY_LANG.get(sec_nat, "English")
        if sec_lang != prim_lang and sec_lang != club_lang:
            langs.append({"language": sec_lang, "proficiency": 0.85, "level": "Fluent"})

    # 4. English (lingua franca)
    has_english = any(l["language"] == "English" for l in langs)
    if not has_english:
        langs.append({"language": "English", "proficiency": 0.80 if is_starter else 0.65, "level": "Fluent" if is_starter else "Basic"})

    return langs

def get_club_staff(team_name: str) -> list:
    # 5 staff members per team: Assistant Manager, Head Physio, Tactical Analyst, Fitness Coach, Chief Scout
    staff_registry = {
        "FC Nordvik": [
            {"staff_name": "Knut Eide", "role": "Assistant Manager", "team_name": "FC Nordvik", "nationality": "Norwegian", "secondary_nationality": "", "date_of_birth": "1974-05-12", "experience": 28, "coaching": 0.84, "judging_ability": 0.78, "physiotherapy": 0.60, "tactical_knowledge": 0.82, "salary_weekly": 7500, "contract_years": 3},
            {"staff_name": "Dr. Thomas Holm", "role": "Head Physio", "team_name": "FC Nordvik", "nationality": "Norwegian", "secondary_nationality": "", "date_of_birth": "1979-09-22", "experience": 22, "coaching": 0.50, "judging_ability": 0.60, "physiotherapy": 0.94, "tactical_knowledge": 0.55, "salary_weekly": 6200, "contract_years": 3},
            {"staff_name": "Simen Aas", "role": "Tactical Analyst", "team_name": "FC Nordvik", "nationality": "Norwegian", "secondary_nationality": "", "date_of_birth": "1990-03-14", "experience": 14, "coaching": 0.72, "judging_ability": 0.85, "physiotherapy": 0.50, "tactical_knowledge": 0.90, "salary_weekly": 5500, "contract_years": 2},
            {"staff_name": "Lars Bakke", "role": "Fitness Coach", "team_name": "FC Nordvik", "nationality": "Norwegian", "secondary_nationality": "", "date_of_birth": "1984-11-04", "experience": 18, "coaching": 0.82, "judging_ability": 0.65, "physiotherapy": 0.78, "tactical_knowledge": 0.60, "salary_weekly": 4800, "contract_years": 2},
            {"staff_name": "Geir Hansen", "role": "Chief Scout", "team_name": "FC Nordvik", "nationality": "Norwegian", "secondary_nationality": "Swedish", "date_of_birth": "1968-07-19", "experience": 32, "coaching": 0.65, "judging_ability": 0.92, "physiotherapy": 0.50, "tactical_knowledge": 0.80, "salary_weekly": 6000, "contract_years": 3}
        ],
        "CD Solano": [
            {"staff_name": "Eduardo Barba", "role": "Assistant Manager", "team_name": "CD Solano", "nationality": "Spanish", "secondary_nationality": "", "date_of_birth": "1975-02-18", "experience": 25, "coaching": 0.85, "judging_ability": 0.80, "physiotherapy": 0.55, "tactical_knowledge": 0.86, "salary_weekly": 8000, "contract_years": 2},
            {"staff_name": "Dr. Marcos Rey", "role": "Head Physio", "team_name": "CD Solano", "nationality": "Spanish", "secondary_nationality": "", "date_of_birth": "1981-06-11", "experience": 20, "coaching": 0.50, "judging_ability": 0.55, "physiotherapy": 0.92, "tactical_knowledge": 0.50, "salary_weekly": 6000, "contract_years": 3},
            {"staff_name": "Alvaro Saez", "role": "Tactical Analyst", "team_name": "CD Solano", "nationality": "Spanish", "secondary_nationality": "Argentine", "date_of_birth": "1988-10-29", "experience": 16, "coaching": 0.75, "judging_ability": 0.86, "physiotherapy": 0.45, "tactical_knowledge": 0.88, "salary_weekly": 5800, "contract_years": 2},
            {"staff_name": "Pau Soler", "role": "Fitness Coach", "team_name": "CD Solano", "nationality": "Spanish", "secondary_nationality": "", "date_of_birth": "1985-04-03", "experience": 17, "coaching": 0.80, "judging_ability": 0.60, "physiotherapy": 0.80, "tactical_knowledge": 0.60, "salary_weekly": 5000, "contract_years": 2},
            {"staff_name": "Vicente Mallo", "role": "Chief Scout", "team_name": "CD Solano", "nationality": "Spanish", "secondary_nationality": "", "date_of_birth": "1970-12-08", "experience": 30, "coaching": 0.60, "judging_ability": 0.90, "physiotherapy": 0.45, "tactical_knowledge": 0.82, "salary_weekly": 6500, "contract_years": 2}
        ],
        "Valence Athletic": [
            {"staff_name": "Christophe Bernard", "role": "Assistant Manager", "team_name": "Valence Athletic", "nationality": "French", "secondary_nationality": "", "date_of_birth": "1976-08-30", "experience": 24, "coaching": 0.82, "judging_ability": 0.78, "physiotherapy": 0.50, "tactical_knowledge": 0.84, "salary_weekly": 7200, "contract_years": 2},
            {"staff_name": "Dr. Jean Marchal", "role": "Head Physio", "team_name": "Valence Athletic", "nationality": "French", "secondary_nationality": "", "date_of_birth": "1978-01-19", "experience": 23, "coaching": 0.45, "judging_ability": 0.50, "physiotherapy": 0.95, "tactical_knowledge": 0.50, "salary_weekly": 6400, "contract_years": 3},
            {"staff_name": "Fabrice Roux", "role": "Tactical Analyst", "team_name": "Valence Athletic", "nationality": "French", "secondary_nationality": "", "date_of_birth": "1992-05-24", "experience": 12, "coaching": 0.70, "judging_ability": 0.82, "physiotherapy": 0.45, "tactical_knowledge": 0.89, "salary_weekly": 5200, "contract_years": 2},
            {"staff_name": "Guillaume Denis", "role": "Fitness Coach", "team_name": "Valence Athletic", "nationality": "French", "secondary_nationality": "", "date_of_birth": "1986-09-15", "experience": 16, "coaching": 0.84, "judging_ability": 0.55, "physiotherapy": 0.82, "tactical_knowledge": 0.58, "salary_weekly": 4900, "contract_years": 2},
            {"staff_name": "Thierry Blanc", "role": "Chief Scout", "team_name": "Valence Athletic", "nationality": "French", "secondary_nationality": "Belgian", "date_of_birth": "1971-03-07", "experience": 29, "coaching": 0.60, "judging_ability": 0.91, "physiotherapy": 0.45, "tactical_knowledge": 0.78, "salary_weekly": 6200, "contract_years": 3}
        ],
        "Real Maritimo": [
            {"staff_name": "Esteban Carro", "role": "Assistant Manager", "team_name": "Real Maritimo", "nationality": "Spanish", "secondary_nationality": "", "date_of_birth": "1973-11-20", "experience": 27, "coaching": 0.83, "judging_ability": 0.82, "physiotherapy": 0.50, "tactical_knowledge": 0.85, "salary_weekly": 7000, "contract_years": 2},
            {"staff_name": "Dr. Gonzalo Varela", "role": "Head Physio", "team_name": "Real Maritimo", "nationality": "Portuguese", "secondary_nationality": "Spanish", "date_of_birth": "1980-07-04", "experience": 21, "coaching": 0.45, "judging_ability": 0.50, "physiotherapy": 0.93, "tactical_knowledge": 0.52, "salary_weekly": 6100, "contract_years": 2},
            {"staff_name": "Joao Cabral", "role": "Tactical Analyst", "team_name": "Real Maritimo", "nationality": "Portuguese", "secondary_nationality": "", "date_of_birth": "1989-12-16", "experience": 15, "coaching": 0.72, "judging_ability": 0.84, "physiotherapy": 0.45, "tactical_knowledge": 0.87, "salary_weekly": 5400, "contract_years": 2},
            {"staff_name": "Enrique Lomba", "role": "Fitness Coach", "team_name": "Real Maritimo", "nationality": "Spanish", "secondary_nationality": "", "date_of_birth": "1987-03-22", "experience": 15, "coaching": 0.81, "judging_ability": 0.58, "physiotherapy": 0.79, "tactical_knowledge": 0.60, "salary_weekly": 4700, "contract_years": 2},
            {"staff_name": "Rodrigo Valente", "role": "Chief Scout", "team_name": "Real Maritimo", "nationality": "Brazilian", "secondary_nationality": "Portuguese", "date_of_birth": "1972-04-15", "experience": 28, "coaching": 0.62, "judging_ability": 0.93, "physiotherapy": 0.45, "tactical_knowledge": 0.80, "salary_weekly": 6600, "contract_years": 3}
        ],
        "Borussia Eisenwald": [
            {"staff_name": "Torsten Reuter", "role": "Assistant Manager", "team_name": "Borussia Eisenwald", "nationality": "German", "secondary_nationality": "", "date_of_birth": "1972-02-14", "experience": 29, "coaching": 0.86, "judging_ability": 0.82, "physiotherapy": 0.55, "tactical_knowledge": 0.87, "salary_weekly": 8200, "contract_years": 3},
            {"staff_name": "Dr. Hans-Peter Koch", "role": "Head Physio", "team_name": "Borussia Eisenwald", "nationality": "German", "secondary_nationality": "", "date_of_birth": "1975-10-08", "experience": 26, "coaching": 0.50, "judging_ability": 0.55, "physiotherapy": 0.96, "tactical_knowledge": 0.50, "salary_weekly": 6700, "contract_years": 3},
            {"staff_name": "Sven Lindemann", "role": "Tactical Analyst", "team_name": "Borussia Eisenwald", "nationality": "German", "secondary_nationality": "Austrian", "date_of_birth": "1991-07-27", "experience": 13, "coaching": 0.74, "judging_ability": 0.86, "physiotherapy": 0.48, "tactical_knowledge": 0.91, "salary_weekly": 5700, "contract_years": 2},
            {"staff_name": "Matthias Beck", "role": "Fitness Coach", "team_name": "Borussia Eisenwald", "nationality": "German", "secondary_nationality": "", "date_of_birth": "1983-06-19", "experience": 19, "coaching": 0.85, "judging_ability": 0.60, "physiotherapy": 0.82, "tactical_knowledge": 0.62, "salary_weekly": 5200, "contract_years": 2},
            {"staff_name": "Juergen Voigt", "role": "Chief Scout", "team_name": "Borussia Eisenwald", "nationality": "German", "secondary_nationality": "", "date_of_birth": "1967-01-23", "experience": 33, "coaching": 0.62, "judging_ability": 0.93, "physiotherapy": 0.45, "tactical_knowledge": 0.82, "salary_weekly": 6800, "contract_years": 3}
        ],
        "Aurora Calcio": [
            {"staff_name": "Massimo Ferrara", "role": "Assistant Manager", "team_name": "Aurora Calcio", "nationality": "Italian", "secondary_nationality": "", "date_of_birth": "1974-06-17", "experience": 27, "coaching": 0.84, "judging_ability": 0.81, "physiotherapy": 0.50, "tactical_knowledge": 0.86, "salary_weekly": 7800, "contract_years": 2},
            {"staff_name": "Dr. Claudio Marchetti", "role": "Head Physio", "team_name": "Aurora Calcio", "nationality": "Italian", "secondary_nationality": "", "date_of_birth": "1977-12-05", "experience": 24, "coaching": 0.45, "judging_ability": 0.50, "physiotherapy": 0.94, "tactical_knowledge": 0.50, "salary_weekly": 6300, "contract_years": 3},
            {"staff_name": "Daniele Raggi", "role": "Tactical Analyst", "team_name": "Aurora Calcio", "nationality": "Italian", "secondary_nationality": "", "date_of_birth": "1990-09-02", "experience": 14, "coaching": 0.73, "judging_ability": 0.84, "physiotherapy": 0.46, "tactical_knowledge": 0.89, "salary_weekly": 5500, "contract_years": 2},
            {"staff_name": "Valerio De Santis", "role": "Fitness Coach", "team_name": "Aurora Calcio", "nationality": "Italian", "secondary_nationality": "", "date_of_birth": "1984-08-21", "experience": 18, "coaching": 0.82, "judging_ability": 0.58, "physiotherapy": 0.80, "tactical_knowledge": 0.60, "salary_weekly": 5100, "contract_years": 2},
            {"staff_name": "Pietro Barone", "role": "Chief Scout", "team_name": "Aurora Calcio", "nationality": "Italian", "secondary_nationality": "Croatian", "date_of_birth": "1969-04-18", "experience": 31, "coaching": 0.60, "judging_ability": 0.92, "physiotherapy": 0.45, "tactical_knowledge": 0.81, "salary_weekly": 6500, "contract_years": 3}
        ],
        "Highland Thistle FC": [
            {"staff_name": "Gordon Strachan Jr.", "role": "Assistant Manager", "team_name": "Highland Thistle FC", "nationality": "Scottish", "secondary_nationality": "", "date_of_birth": "1975-03-11", "experience": 26, "coaching": 0.82, "judging_ability": 0.79, "physiotherapy": 0.50, "tactical_knowledge": 0.83, "salary_weekly": 6800, "contract_years": 2},
            {"staff_name": "Dr. Neil Mackay", "role": "Head Physio", "team_name": "Highland Thistle FC", "nationality": "Scottish", "secondary_nationality": "", "date_of_birth": "1980-08-14", "experience": 21, "coaching": 0.45, "judging_ability": 0.50, "physiotherapy": 0.92, "tactical_knowledge": 0.50, "salary_weekly": 5800, "contract_years": 2},
            {"staff_name": "Craig Robertson", "role": "Tactical Analyst", "team_name": "Highland Thistle FC", "nationality": "Scottish", "secondary_nationality": "", "date_of_birth": "1993-01-20", "experience": 11, "coaching": 0.71, "judging_ability": 0.82, "physiotherapy": 0.45, "tactical_knowledge": 0.86, "salary_weekly": 4900, "contract_years": 2},
            {"staff_name": "Finlay Grant", "role": "Fitness Coach", "team_name": "Highland Thistle FC", "nationality": "Scottish", "secondary_nationality": "", "date_of_birth": "1986-10-09", "experience": 16, "coaching": 0.83, "judging_ability": 0.56, "physiotherapy": 0.79, "tactical_knowledge": 0.58, "salary_weekly": 4600, "contract_years": 2},
            {"staff_name": "Archie Macintyre", "role": "Chief Scout", "team_name": "Highland Thistle FC", "nationality": "Scottish", "secondary_nationality": "English", "date_of_birth": "1967-11-28", "experience": 33, "coaching": 0.58, "judging_ability": 0.89, "physiotherapy": 0.45, "tactical_knowledge": 0.78, "salary_weekly": 5900, "contract_years": 3}
        ],
        "Porto Sol Stella": [
            {"staff_name": "Manuel Coentrao", "role": "Assistant Manager", "team_name": "Porto Sol Stella", "nationality": "Portuguese", "secondary_nationality": "", "date_of_birth": "1977-05-09", "experience": 24, "coaching": 0.83, "judging_ability": 0.80, "physiotherapy": 0.52, "tactical_knowledge": 0.84, "salary_weekly": 7100, "contract_years": 2},
            {"staff_name": "Dr. Bernardo Teles", "role": "Head Physio", "team_name": "Porto Sol Stella", "nationality": "Portuguese", "secondary_nationality": "", "date_of_birth": "1979-02-23", "experience": 22, "coaching": 0.45, "judging_ability": 0.52, "physiotherapy": 0.93, "tactical_knowledge": 0.50, "salary_weekly": 6100, "contract_years": 3},
            {"staff_name": "Gilberto Faria", "role": "Tactical Analyst", "team_name": "Porto Sol Stella", "nationality": "Portuguese", "secondary_nationality": "Brazilian", "date_of_birth": "1991-08-12", "experience": 13, "coaching": 0.72, "judging_ability": 0.83, "physiotherapy": 0.45, "tactical_knowledge": 0.88, "salary_weekly": 5300, "contract_years": 2},
            {"staff_name": "Nelson Sobral", "role": "Fitness Coach", "team_name": "Porto Sol Stella", "nationality": "Portuguese", "secondary_nationality": "", "date_of_birth": "1985-06-30", "experience": 17, "coaching": 0.82, "judging_ability": 0.56, "physiotherapy": 0.80, "tactical_knowledge": 0.60, "salary_weekly": 4800, "contract_years": 2},
            {"staff_name": "Cristiano Simoes", "role": "Chief Scout", "team_name": "Porto Sol Stella", "nationality": "Portuguese", "secondary_nationality": "", "date_of_birth": "1971-10-03", "experience": 30, "coaching": 0.60, "judging_ability": 0.91, "physiotherapy": 0.45, "tactical_knowledge": 0.80, "salary_weekly": 6300, "contract_years": 3}
        ]
    }
    staff_list = staff_registry.get(team_name, [])
    for s in staff_list:
        s["spoken_languages"] = make_player_languages(s["nationality"], s["secondary_nationality"], team_name, 1)
    return staff_list

def get_free_agent_staff() -> list:
    free_agents = [
        {"staff_name": "David O'Connor", "role": "Assistant Manager", "team_name": "", "nationality": "Irish", "secondary_nationality": "English", "date_of_birth": "1970-04-25", "experience": 30, "coaching": 0.81, "judging_ability": 0.78, "physiotherapy": 0.50, "tactical_knowledge": 0.82, "salary_weekly": 5500, "contract_years": 0},
        {"staff_name": "Dr. Stefan Lindqvist", "role": "Head Physio", "team_name": "", "nationality": "Swedish", "secondary_nationality": "", "date_of_birth": "1978-11-14", "experience": 22, "coaching": 0.45, "judging_ability": 0.50, "physiotherapy": 0.91, "tactical_knowledge": 0.48, "salary_weekly": 4800, "contract_years": 0},
        {"staff_name": "Marco D'Angelo", "role": "Tactical Analyst", "team_name": "", "nationality": "Italian", "secondary_nationality": "", "date_of_birth": "1992-02-18", "experience": 12, "coaching": 0.70, "judging_ability": 0.80, "physiotherapy": 0.45, "tactical_knowledge": 0.86, "salary_weekly": 4200, "contract_years": 0},
        {"staff_name": "Janusz Kowalczyk", "role": "Chief Scout", "team_name": "", "nationality": "Polish", "secondary_nationality": "German", "date_of_birth": "1969-09-09", "experience": 31, "coaching": 0.58, "judging_ability": 0.89, "physiotherapy": 0.45, "tactical_knowledge": 0.79, "salary_weekly": 5000, "contract_years": 0}
    ]
    for s in free_agents:
        s["spoken_languages"] = make_player_languages(s["nationality"], s["secondary_nationality"], "", 1)
    return free_agents

def run_update():
    # 1. Read generate_db.py
    gen_db_path = os.path.join(TOOLS_DIR, "generate_db.py")
    with open(gen_db_path, "r", encoding="utf-8") as f:
        code = f.read()

    # We will invoke generate_db module functions to get the existing structures
    import importlib.util
    spec = importlib.util.spec_from_file_location("generate_db", gen_db_path)
    gen_mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen_mod)

    # 2. Generate updated league
    league = gen_mod.generate_league()
    for team in league["teams"]:
        tname = team["team_name"]
        # Update each player in squad with nationality, DOB, languages
        for p in team["squad"]:
            pname = p["player_name"]
            snum = p["shirt_number"]
            bio = PLAYER_BIO.get(pname, ("Norwegian", ""))
            p["nationality"] = bio[0]
            p["secondary_nationality"] = bio[1]
            p["date_of_birth"] = make_player_dob(pname, snum)
            p["spoken_languages"] = make_player_languages(bio[0], bio[1], tname, snum)

        # Attach staff to team
        team["staff"] = get_club_staff(tname)

    # 3. Generate updated managers
    managers_data = gen_mod.generate_managers()
    managers = managers_data["managers"]

    MGR_MAP = {
        "Branimir Skok": ("Croatian", "", "1970-08-14", [
            {"language": "Croatian", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.85, "level": "Fluent"},
            {"language": "German", "proficiency": 0.60, "level": "Basic"}
        ]),
        "Sebastián Larrarte": ("Argentine", "Spanish", "1968-03-22", [
            {"language": "Spanish", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.85, "level": "Fluent"},
            {"language": "Italian", "proficiency": 0.80, "level": "Fluent"}
        ]),
        "Raivo Peet": ("Dutch", "", "1978-11-05", [
            {"language": "Dutch", "proficiency": 1.0, "level": "Native"},
            {"language": "French", "proficiency": 0.85, "level": "Fluent"},
            {"language": "English", "proficiency": 0.90, "level": "Fluent"},
            {"language": "German", "proficiency": 0.75, "level": "Fluent"}
        ]),
        "Yuki Tsurumoto": ("Japanese", "", "1973-06-18", [
            {"language": "Japanese", "proficiency": 1.0, "level": "Native"},
            {"language": "Spanish", "proficiency": 0.85, "level": "Fluent"},
            {"language": "English", "proficiency": 0.80, "level": "Fluent"}
        ]),
        "Dietrich Klausner": ("German", "", "1974-09-30", [
            {"language": "German", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.85, "level": "Fluent"}
        ]),
        "Giancarlo Bellini": ("Italian", "", "1971-04-12", [
            {"language": "Italian", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.85, "level": "Fluent"},
            {"language": "Spanish", "proficiency": 0.60, "level": "Basic"}
        ]),
        "Alistair MacCallum": ("Scottish", "", "1975-01-25", [
            {"language": "English", "proficiency": 1.0, "level": "Native"}
        ]),
        "Valdemar Cruz": ("Portuguese", "Spanish", "1976-10-09", [
            {"language": "Portuguese", "proficiency": 1.0, "level": "Native"},
            {"language": "Spanish", "proficiency": 0.85, "level": "Fluent"},
            {"language": "English", "proficiency": 0.80, "level": "Fluent"}
        ]),
        "Arthur Pendelton": ("English", "", "1963-12-04", [
            {"language": "English", "proficiency": 1.0, "level": "Native"},
            {"language": "French", "proficiency": 0.50, "level": "Basic"}
        ]),
        "Mateusz Wilczek": ("Polish", "", "1983-05-17", [
            {"language": "Polish", "proficiency": 1.0, "level": "Native"},
            {"language": "German", "proficiency": 0.85, "level": "Fluent"},
            {"language": "English", "proficiency": 0.80, "level": "Fluent"}
        ])
    }

    for m in managers:
        mname = m["name"]
        if mname in MGR_MAP:
            info = MGR_MAP[mname]
            m["nationality"] = info[0]
            m["secondary_nationality"] = info[1]
            m["date_of_birth"] = info[2]
            m["spoken_languages"] = info[3]

    # 4. Generate updated referees
    referees_data = gen_mod.generate_referees()
    referees = referees_data["referees"]

    REF_MAP = {
        "Domagoj Vrban": ("Croatian", "", "1978-04-12", [
            {"language": "Croatian", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.85, "level": "Fluent"},
            {"language": "German", "proficiency": 0.60, "level": "Basic"}
        ]),
        "Ingrid Vaarmo": ("Norwegian", "", "1975-09-24", [
            {"language": "Norwegian", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.90, "level": "Fluent"},
            {"language": "French", "proficiency": 0.60, "level": "Basic"}
        ]),
        "Kjetil Ornseth": ("Norwegian", "", "1988-02-19", [
            {"language": "Norwegian", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.80, "level": "Fluent"}
        ]),
        "Tomas Errecarte": ("Argentine", "", "1984-11-08", [
            {"language": "Spanish", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.80, "level": "Fluent"},
            {"language": "Portuguese", "proficiency": 0.60, "level": "Basic"}
        ]),
        "Arjun Dharmaraj": ("English", "", "1983-07-30", [
            {"language": "English", "proficiency": 1.0, "level": "Native"},
            {"language": "French", "proficiency": 0.50, "level": "Basic"}
        ]),
        "Petru Balint": ("Romanian", "", "1989-10-15", [
            {"language": "Romanian", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.80, "level": "Fluent"},
            {"language": "Italian", "proficiency": 0.60, "level": "Basic"}
        ]),
        "Jean-Luc Vaneck": ("French", "", "1977-03-05", [
            {"language": "French", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.85, "level": "Fluent"},
            {"language": "Spanish", "proficiency": 0.75, "level": "Fluent"}
        ]),
        "Kenzo Takahashi": ("Japanese", "", "1981-12-14", [
            {"language": "Japanese", "proficiency": 1.0, "level": "Native"},
            {"language": "English", "proficiency": 0.85, "level": "Fluent"}
        ])
    }

    for r in referees:
        rname = r["name"]
        if rname in REF_MAP:
            info = REF_MAP[rname]
            r["nationality"] = info[0]
            r["secondary_nationality"] = info[1]
            r["date_of_birth"] = info[2]
            r["spoken_languages"] = info[3]

    # 5. Generate all staff pool (40 club + 4 free agents)
    all_staff = []
    for team in league["teams"]:
        all_staff.extend(team["staff"])
    all_staff.extend(get_free_agent_staff())

    # 6. Write JSON files
    league_path = os.path.join(DATA_DIR, "league.json")
    with open(league_path, "w", encoding="utf-8") as f:
        json.dump(league, f, indent=2, ensure_ascii=False)
    print(f"Wrote {league_path}: {len(league['teams'])} teams")

    players_flat = []
    for t in league["teams"]:
        for p in t["squad"]:
            p_flat = dict(p)
            p_flat["team_name"] = t["team_name"]
            players_flat.append(p_flat)
    players_path = os.path.join(DATA_DIR, "players.json")
    with open(players_path, "w", encoding="utf-8") as f:
        json.dump({"players": players_flat}, f, indent=2, ensure_ascii=False)
    print(f"Wrote {players_path}: {len(players_flat)} players")

    managers_path = os.path.join(DATA_DIR, "managers.json")
    with open(managers_path, "w", encoding="utf-8") as f:
        json.dump({"managers": managers}, f, indent=2, ensure_ascii=False)
    print(f"Wrote {managers_path}: {len(managers)} managers")

    referees_path = os.path.join(DATA_DIR, "referees.json")
    with open(referees_path, "w", encoding="utf-8") as f:
        json.dump({"referees": referees}, f, indent=2, ensure_ascii=False)
    print(f"Wrote {referees_path}: {len(referees)} referees")

    staff_path = os.path.join(DATA_DIR, "staff.json")
    with open(staff_path, "w", encoding="utf-8") as f:
        json.dump({"staff": all_staff}, f, indent=2, ensure_ascii=False)
    print(f"Wrote {staff_path}: {len(all_staff)} staff members")

if __name__ == "__main__":
    run_update()
