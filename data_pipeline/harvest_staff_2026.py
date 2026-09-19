#!/usr/bin/env python3
"""
data_pipeline/harvest_staff_2026.py

Harvests and enriches backroom staff members across football clubs worldwide
for PowerFootball-2D (StaffData.gd). Extracts:
  - Goalkeeping coaches
  - Set piece coaches
  - Chief scouts & recruitment leads
  - Technical directors & sporting directors
  - Assistant managers & first team coaches
  - Head physios & medical leads
  - Tactical analysts & performance analysts
  - Fitness coaches & sports scientists

Sources:
  1. Wikipedia Club Technical & Coaching Staff Tables (Wikitext section parser)
  2. SportMonks Football API v3 (assistant coaches, caretaker staff)
  3. Curated Master Directory of elite backroom personnel

Outputs:
  - JSON database ready for autoloads/StaffLoader.gd (res://data/staff_2026.json)
  - SQLite table sync with powerfootball_master.db (staff table)
"""

import argparse
import json
import os
import re
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
        sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass

# =============================================================================
# CONFIGURATION & CONSTANTS
# =============================================================================

DEFAULT_API_TOKEN = "WF5neL4jRErhZvad8hJpq3a9MNS2hk9jgkU6b8wCFqbOh8EnXHFdCqzMYEdT"
SPORTMONKS_BASE = "https://api.sportmonks.com/v3/football"
WIKIPEDIA_API = "https://en.wikipedia.org/w/api.php"
USER_AGENT = "PowerFootballDataBot/2.0 (dev@powerfootball.local)"

# ISO-3 / Code to Country Name Mapping for Wikipedia Flag Icons
FLAG_MAP: Dict[str, str] = {
    "ENG": "England", "ESP": "Spain", "GER": "Germany", "ITA": "Italy",
    "FRA": "France", "POR": "Portugal", "NED": "Netherlands", "SCO": "Scotland",
    "WAL": "Wales", "NIR": "Northern Ireland", "IRL": "Republic of Ireland", "IRE": "Republic of Ireland",
    "BEL": "Belgium", "BRA": "Brazil", "ARG": "Argentina", "DEN": "Denmark",
    "SWE": "Sweden", "NOR": "Norway", "FIN": "Finland", "AUT": "Austria",
    "SUI": "Switzerland", "CRO": "Croatia", "SRB": "Serbia", "POL": "Poland",
    "CZE": "Czech Republic", "TUR": "Turkey", "GRE": "Greece", "USA": "United States",
    "CAN": "Canada", "AUS": "Australia", "MEX": "Mexico", "COL": "Colombia",
    "URU": "Uruguay", "CHI": "Chile", "JPN": "Japan", "KOR": "South Korea",
    "MAR": "Morocco", "SEN": "Senegal", "NGA": "Nigeria", "GHA": "Ghana",
    "CIV": "Ivory Coast", "CMR": "Cameroon", "RSA": "South Africa", "EGY": "Egypt"
}

# Curated High-Profile Technical Staff Members
CURATED_STAFF: List[Dict[str, Any]] = [
    # Set Piece Coaches
    {
        "staff_name": "Nicolas Jover", "role": "Set Piece Coach", "team_name": "Arsenal",
        "nationality": "France", "secondary_nationality": "Germany", "date_of_birth": "1981-10-28",
        "experience": 45, "coaching": 0.94, "tactical_knowledge": 0.98, "judging_ability": 0.70, "physiotherapy": 0.40,
        "salary_weekly": 15000, "contract_years": 3
    },
    {
        "staff_name": "Austin MacPhee", "role": "Set Piece Coach", "team_name": "Chelsea",
        "nationality": "Scotland", "secondary_nationality": "", "date_of_birth": "1979-10-11",
        "experience": 48, "coaching": 0.92, "tactical_knowledge": 0.96, "judging_ability": 0.72, "physiotherapy": 0.40,
        "salary_weekly": 14000, "contract_years": 2
    },
    {
        "staff_name": "Gianni Vio", "role": "Set Piece Coach", "team_name": "Watford",
        "nationality": "Italy", "secondary_nationality": "", "date_of_birth": "1953-04-06",
        "experience": 75, "coaching": 0.95, "tactical_knowledge": 0.99, "judging_ability": 0.65, "physiotherapy": 0.35,
        "salary_weekly": 12000, "contract_years": 1
    },
    {
        "staff_name": "Bernardo Cueva", "role": "Set Piece Coach", "team_name": "Chelsea",
        "nationality": "Mexico", "secondary_nationality": "", "date_of_birth": "1987-08-15",
        "experience": 38, "coaching": 0.88, "tactical_knowledge": 0.92, "judging_ability": 0.75, "physiotherapy": 0.40,
        "salary_weekly": 11000, "contract_years": 3
    },
    # Chief Scouts & Recruitment Leads
    {
        "staff_name": "Juni Calafat", "role": "Chief Scout", "team_name": "Real Madrid",
        "nationality": "Brazil", "secondary_nationality": "Spain", "date_of_birth": "1972-11-14",
        "experience": 68, "coaching": 0.60, "tactical_knowledge": 0.88, "judging_ability": 0.99, "physiotherapy": 0.30,
        "salary_weekly": 25000, "contract_years": 4
    },
    {
        "staff_name": "Sven Mislintat", "role": "Chief Scout", "team_name": "Borussia Dortmund",
        "nationality": "Germany", "secondary_nationality": "", "date_of_birth": "1972-11-05",
        "experience": 65, "coaching": 0.55, "tactical_knowledge": 0.85, "judging_ability": 0.96, "physiotherapy": 0.30,
        "salary_weekly": 22000, "contract_years": 2
    },
    {
        "staff_name": "Alex Fraser", "role": "Chief Scout", "team_name": "Tottenham Hotspur",
        "nationality": "England", "secondary_nationality": "", "date_of_birth": "1978-03-20",
        "experience": 50, "coaching": 0.50, "tactical_knowledge": 0.82, "judging_ability": 0.91, "physiotherapy": 0.30,
        "salary_weekly": 14000, "contract_years": 3
    },
    # Technical & Sporting Directors
    {
        "staff_name": "Dan Ashworth", "role": "Technical Director", "team_name": "Manchester United",
        "nationality": "England", "secondary_nationality": "", "date_of_birth": "1971-03-06",
        "experience": 72, "coaching": 0.70, "tactical_knowledge": 0.92, "judging_ability": 0.95, "physiotherapy": 0.60,
        "salary_weekly": 35000, "contract_years": 3
    },
    {
        "staff_name": "Richard Hughes", "role": "Technical Director", "team_name": "Liverpool",
        "nationality": "Scotland", "secondary_nationality": "", "date_of_birth": "1979-06-25",
        "experience": 55, "coaching": 0.65, "tactical_knowledge": 0.88, "judging_ability": 0.94, "physiotherapy": 0.50,
        "salary_weekly": 30000, "contract_years": 3
    },
    {
        "staff_name": "Deco", "role": "Technical Director", "team_name": "FC Barcelona",
        "nationality": "Portugal", "secondary_nationality": "Brazil", "date_of_birth": "1977-08-27",
        "experience": 58, "coaching": 0.72, "tactical_knowledge": 0.90, "judging_ability": 0.93, "physiotherapy": 0.50,
        "salary_weekly": 32000, "contract_years": 3
    },
    {
        "staff_name": "Max Eberl", "role": "Technical Director", "team_name": "Bayern München",
        "nationality": "Germany", "secondary_nationality": "", "date_of_birth": "1973-09-21",
        "experience": 66, "coaching": 0.68, "tactical_knowledge": 0.89, "judging_ability": 0.94, "physiotherapy": 0.55,
        "salary_weekly": 32000, "contract_years": 3
    },
    # Goalkeeping Coaches
    {
        "staff_name": "Iñaki Caña", "role": "Goalkeeping Coach", "team_name": "Arsenal",
        "nationality": "Spain", "secondary_nationality": "", "date_of_birth": "1975-09-19",
        "experience": 55, "coaching": 0.94, "tactical_knowledge": 0.80, "judging_ability": 0.85, "physiotherapy": 0.50,
        "salary_weekly": 12000, "contract_years": 3
    },
    {
        "staff_name": "Toni Tapalović", "role": "Goalkeeping Coach", "team_name": "FC Barcelona",
        "nationality": "Croatia", "secondary_nationality": "Germany", "date_of_birth": "1980-10-10",
        "experience": 52, "coaching": 0.93, "tactical_knowledge": 0.82, "judging_ability": 0.86, "physiotherapy": 0.50,
        "salary_weekly": 14000, "contract_years": 2
    },
    {
        "staff_name": "Richard Wright", "role": "Goalkeeping Coach", "team_name": "Manchester City",
        "nationality": "England", "secondary_nationality": "", "date_of_birth": "1977-11-05",
        "experience": 54, "coaching": 0.91, "tactical_knowledge": 0.78, "judging_ability": 0.82, "physiotherapy": 0.45,
        "salary_weekly": 12000, "contract_years": 2
    },
    # Elite Fitness Coaches
    {
        "staff_name": "Antonio Pintus", "role": "Fitness Coach", "team_name": "Real Madrid",
        "nationality": "Italy", "secondary_nationality": "", "date_of_birth": "1962-10-26",
        "experience": 80, "coaching": 0.85, "tactical_knowledge": 0.70, "judging_ability": 0.65, "physiotherapy": 0.98,
        "salary_weekly": 20000, "contract_years": 2
    }
]

# Elite Worldwide Clubs to Harvest Wikipedia Staff Pages From
ELITE_CLUBS: List[Tuple[str, str]] = [
    ("Arsenal", "Arsenal_F.C."),
    ("Liverpool", "Liverpool_F.C."),
    ("Manchester City", "Manchester_City_F.C."),
    ("Chelsea", "Chelsea_F.C."),
    ("Manchester United", "Manchester_United_F.C."),
    ("Tottenham Hotspur", "Tottenham_Hotspur_F.C."),
    ("Aston Villa", "Aston_Villa_F.C."),
    ("Newcastle United", "Newcastle_United_F.C."),
    ("Brighton & Hove Albion", "Brighton_%26_Hove_Albion_F.C."),
    ("Everton", "Everton_F.C."),
    ("West Ham United", "West_Ham_United_F.C."),
    ("Real Madrid", "Real_Madrid_CF"),
    ("FC Barcelona", "FC_Barcelona"),
    ("Atlético de Madrid", "Atl%C3%A9tico_Madrid"),
    ("Athletic Club", "Athletic_Bilbao"),
    ("Real Sociedad", "Real_Sociedad"),
    ("Villarreal", "Villarreal_CF"),
    ("Sevilla", "Sevilla_FC"),
    ("Real Betis", "Real_Betis"),
    ("Bayern München", "FC_Bayern_Munich"),
    ("Borussia Dortmund", "Borussia_Dortmund"),
    ("Bayer Leverkusen", "Bayer_04_Leverkusen"),
    ("RB Leipzig", "RB_Leipzig"),
    ("Eintracht Frankfurt", "Eintracht_Frankfurt"),
    ("VfB Stuttgart", "VfB_Stuttgart"),
    ("Inter", "Inter_Milan"),
    ("AC Milan", "A.C._Milan"),
    ("Juventus", "Juventus_FC"),
    ("Napoli", "SSC_Napoli"),
    ("Roma", "AS_Roma"),
    ("Lazio", "SS_Lazio"),
    ("Atalanta", "Atalanta_B.C."),
    ("Fiorentina", "ACF_Fiorentina"),
    ("Paris Saint-Germain", "Paris_Saint-Germain_F.C."),
    ("Olympique de Marseille", "Olympique_de_Marseille"),
    ("Olympique Lyonnais", "Olympique_Lyonnais"),
    ("Monaco", "AS_Monaco_FC"),
    ("Lille", "Lille_OSC"),
    ("Sporting CP", "Sporting_CP"),
    ("Benfica", "S.L._Benfica"),
    ("Porto", "FC_Porto"),
    ("Ajax", "AFC_Ajax"),
    ("PSV", "PSV_Eindhoven"),
    ("Feyenoord", "Feyenoord"),
    ("Celtic", "Celtic_F.C."),
    ("Rangers", "Rangers_F.C."),
    ("Malmö FF", "Malm%C3%B6_FF"),
    ("AIK", "AIK_Fotboll"),
    ("Djurgården", "Djurg%C3%A5rdens_IF_Fotboll"),
    ("Hammarby", "Hammarby_Fotboll")
]


# =============================================================================
# WIKIPEDIA CLEANING & PARSING
# =============================================================================

RE_FLAG = re.compile(r"\{\{flagicon\|([A-Z]{3}|[A-Za-z\s]+)\}\}", re.IGNORECASE)
RE_FLAG_NAMED = re.compile(r"\{\{flag\|([^}|]+)\}\}", re.IGNORECASE)
RE_WIKILINK = re.compile(r"\[\[(?:[^|\]]*\|)?([^\]]+)\]\]")
RE_REF = re.compile(r"<ref[^>]*>.*?</ref>", re.DOTALL | re.IGNORECASE)
RE_REF_TAG = re.compile(r"<ref[^/>]*/>", re.IGNORECASE)
RE_TEMPLATES = re.compile(r"\{\{[^}]+\}\}")
RE_HTML_TAGS = re.compile(r"<[^>]+>")


def clean_wikitext_cell(text: str) -> str:
    """Strips markup, styling attributes, and references from a wikitext string."""
    t = RE_REF.sub("", text)
    t = RE_REF_TAG.sub("", t)
    t = RE_WIKILINK.sub(r"\1", t)
    t = RE_TEMPLATES.sub("", t)
    t = RE_HTML_TAGS.sub("", t)
    t = re.sub(r'(?:align|style|width|colspan|rowspan|scope)=["\'][^"\']*["\']\|?', '', t, flags=re.IGNORECASE)
    t = re.sub(r'(?:align|style|width|colspan|rowspan|scope)=[^|]*\|', '', t, flags=re.IGNORECASE)
    if "|" in t:
        parts = [p.strip() for p in t.split("|") if p.strip()]
        if parts:
            t = parts[-1]
    t = t.replace("\n", " ").strip(" |!*#'\"")
    return t


def extract_nationality(raw_text: str) -> str:
    """Extracts country nationality from flag templates or country codes."""
    m = RE_FLAG.search(raw_text)
    if m:
        code = m.group(1).strip().upper()
        return FLAG_MAP.get(code, code.title())
    m2 = RE_FLAG_NAMED.search(raw_text)
    if m2:
        val = m2.group(1).strip()
        return FLAG_MAP.get(val.upper(), val.title())
    return "English"


def normalize_role(raw_role: str) -> str:

    """Classifies raw role string into structured StaffData role taxonomy or returns empty string if not staff."""
    r = raw_role.lower()
    # Reject non-staff / corporate board / facility roles
    if any(k in r for k in (
        "chairman", "president", "owner", "secretary", "legal", "driver", "chef",
        "kitchen", "laundry", "kit", "storeman", "marketing", "commercial", "press officer",
        "cameraman", "pastor", "receptionist", "ambassador", "nurse"
    )):
        return ""

    if "goalkeep" in r or "keeper" in r:
        return "Goalkeeping Coach"
    elif "set piece" in r or "set-piece" in r or "dead ball" in r:
        return "Set Piece Coach"
    elif "scout" in r or "recruitment" in r or "talent" in r:
        return "Chief Scout" if any(k in r for k in ("chief", "head", "lead", "director")) else "Scout"
    elif any(k in r for k in ("technical director", "director of football", "sporting director", "managing director for sport", "board member for sport")):
        return "Technical Director"
    elif "physio" in r or "doctor" in r or "medical" in r or "rehabilitation" in r or "physician" in r:
        return "Head Physio"
    elif "analyst" in r or "analysis" in r or "tactical" in r:
        return "Tactical Analyst"
    elif "fitness" in r or "conditioning" in r or "performance coach" in r or "sports science" in r or "athletic trainer" in r:
        return "Fitness Coach"
    elif "assistant" in r or "second coach" in r or "deputy" in r:
        return "Assistant Manager"
    elif "youth" in r or "academy" in r or "development" in r:
        return "Youth Coach"
    elif "coach" in r or "trainer" in r:
        return "First Team Coach"
    return ""



def parse_wikitext_staff(wikitext: str, team_name: str) -> List[Dict[str, Any]]:
    """Extracts all staff members and their normalized roles from wikitext."""
    staff_records: List[Dict[str, Any]] = []

    # 1. Parse bulleted lists: * Role: Name
    bullet_pattern = re.compile(r"^\*\s*([^:–—-]+)[:–—\-]\s*(.+)$", re.MULTILINE)
    for m in bullet_pattern.finditer(wikitext):
        raw_role = clean_wikitext_cell(m.group(1))
        raw_val = m.group(2)
        nat = extract_nationality(raw_val)
        raw_name = clean_wikitext_cell(RE_TEMPLATES.sub("", raw_val))

        names = re.split(r",|\sand\s", raw_name)
        for n in names:
            clean_n = n.strip(" *'\"")
            if clean_n and len(clean_n) > 2 and not clean_n.lower().startswith("vacant"):
                if not any(bad in clean_n.lower() for bad in ("{", "}", "|", "colspan", "rowspan", "align=", "style=", "thumb", "px", "http")):
                    norm_role = normalize_role(raw_role)
                    if norm_role:
                        staff_records.append({
                            "staff_name": clean_n,
                            "role": norm_role,
                            "team_name": team_name,
                            "nationality": nat,
                            "raw_role": raw_role
                        })

    # 2. Parse Wikitables
    rows = wikitext.split("|-")
    current_role = ""
    for row in rows:
        # Split on || or \n|
        cells = [c.strip() for c in re.split(r"\|\||\n\||\n\!", row) if c.strip()]
        if len(cells) >= 2:
            raw_role = cells[0].lstrip("|! ")
            raw_person = cells[1].lstrip("|! ")
            if "rowspan" in raw_role.lower():
                raw_role = re.sub(r'rowspan="?\d+"?\|?', '', raw_role, flags=re.IGNORECASE).strip()

            clean_role = clean_wikitext_cell(raw_role)
            if clean_role and not clean_role.lower().startswith("position") and not clean_role.lower().startswith("role"):
                current_role = clean_role

            nat = extract_nationality(raw_person)
            clean_name = clean_wikitext_cell(RE_TEMPLATES.sub("", raw_person))
            if clean_name and len(clean_name) > 2 and not clean_name.lower().startswith("name") and not clean_name.lower().startswith("vacant"):
                if not any(bad in clean_name.lower() for bad in ("{", "}", "|", "colspan", "rowspan", "align=", "style=", "thumb", "px", "http")):
                    norm_role = normalize_role(current_role)
                    if norm_role:
                        staff_records.append({
                            "staff_name": clean_name,
                            "role": norm_role,
                            "team_name": team_name,
                            "nationality": nat,
                            "raw_role": current_role
                        })
        elif len(cells) == 1 and current_role:
            raw_person = cells[0].lstrip("|! ")
            nat = extract_nationality(raw_person)
            clean_name = clean_wikitext_cell(RE_TEMPLATES.sub("", raw_person))
            if clean_name and len(clean_name) > 2 and not clean_name.lower().startswith("name") and not clean_name.lower().startswith("vacant"):
                if not any(bad in clean_name.lower() for bad in ("{", "}", "|", "colspan", "rowspan", "align=", "style=", "thumb", "px", "http")):
                    norm_role = normalize_role(current_role)
                    if norm_role:
                        staff_records.append({
                            "staff_name": clean_name,
                            "role": norm_role,
                            "team_name": team_name,
                            "nationality": nat,
                            "raw_role": current_role
                        })


    return staff_records


# =============================================================================
# ATTRIBUTE SYNTHESIZER
# =============================================================================

def synthesize_attributes(role: str, experience: int = 25) -> Dict[str, float]:
    """Computes realistic coaching, scouting, physio, and tactical ratings."""
    base = 0.50 + (experience / 200.0)

    if role == "Goalkeeping Coach":
        return {
            "coaching": min(0.96, base + 0.25),
            "judging_ability": min(0.88, base + 0.12),
            "physiotherapy": max(0.40, base - 0.10),
            "tactical_knowledge": min(0.85, base + 0.05)
        }
    elif role == "Set Piece Coach":
        return {
            "coaching": min(0.95, base + 0.22),
            "judging_ability": min(0.85, base + 0.10),
            "physiotherapy": max(0.35, base - 0.15),
            "tactical_knowledge": min(0.98, base + 0.28)
        }
    elif role in ("Chief Scout", "Scout"):
        return {
            "coaching": max(0.40, base - 0.10),
            "judging_ability": min(0.98, base + 0.30 if role == "Chief Scout" else base + 0.20),
            "physiotherapy": max(0.30, base - 0.20),
            "tactical_knowledge": min(0.90, base + 0.15)
        }
    elif role in ("Technical Director", "Director of Football", "Sporting Director"):
        return {
            "coaching": min(0.75, base + 0.05),
            "judging_ability": min(0.97, base + 0.28),
            "physiotherapy": max(0.50, base),
            "tactical_knowledge": min(0.95, base + 0.22)
        }
    elif role == "Head Physio":
        return {
            "coaching": max(0.40, base - 0.10),
            "judging_ability": max(0.50, base),
            "physiotherapy": min(0.98, base + 0.32),
            "tactical_knowledge": max(0.45, base - 0.05)
        }
    elif role == "Tactical Analyst":
        return {
            "coaching": min(0.70, base),
            "judging_ability": min(0.88, base + 0.12),
            "physiotherapy": max(0.35, base - 0.15),
            "tactical_knowledge": min(0.98, base + 0.30)
        }
    elif role == "Fitness Coach":
        return {
            "coaching": min(0.85, base + 0.10),
            "judging_ability": max(0.50, base),
            "physiotherapy": min(0.92, base + 0.22),
            "tactical_knowledge": max(0.55, base)
        }
    else:  # Assistant Manager / First Team Coach
        return {
            "coaching": min(0.92, base + 0.18),
            "judging_ability": min(0.88, base + 0.14),
            "physiotherapy": max(0.50, base),
            "tactical_knowledge": min(0.90, base + 0.16)
        }


def build_spoken_languages(nationality: str) -> List[Dict[str, Any]]:
    """Assigns native and secondary languages based on nationality."""
    nat = nationality.lower()
    native = "English"
    if any(k in nat for k in ("spain", "spanish", "argentin", "chile", "colomb", "mexic", "uruguay")):
        native = "Spanish"
    elif "german" in nat or "austria" in nat:
        native = "German"
    elif "ital" in nat:
        native = "Italian"
    elif "franc" in nat:
        native = "French"
    elif "portug" in nat or "brazil" in nat:
        native = "Portuguese"
    elif "netherland" in nat or "dutch" in nat:
        native = "Dutch"
    elif "swed" in nat:
        native = "Swedish"
    elif "norway" in nat:
        native = "Norwegian"
    elif "denmark" in nat:
        native = "Danish"
    elif "croat" in nat:
        native = "Croatian"

    langs = [{"language": native, "proficiency": 1.0, "level": "Native"}]
    if native != "English":
        langs.append({"language": "English", "proficiency": 0.85, "level": "Fluent"})
    return langs


# =============================================================================
# WIKIPEDIA HARVESTER
# =============================================================================

def harvest_wikipedia_club_staff(club_name: str, wiki_title: str) -> List[Dict[str, Any]]:
    """Fetches and parses technical staff for one club from Wikipedia."""
    url = f"{WIKIPEDIA_API}?action=parse&page={wiki_title}&prop=sections&format=json"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})

    try:
        with urllib.request.urlopen(req, timeout=12) as res:
            data = json.loads(res.read().decode("utf-8"))
            if "parse" not in data:
                return []
            sections = data["parse"].get("sections", [])
            staff_sec = None
            for s in sections:
                line = s.get("line", "").lower()
                if any(k in line for k in ("current staff", "coaching staff", "technical staff", "backroom staff", "management and staff", "management staff", "current technical staff")):
                    staff_sec = s.get("index")
                    break
            if not staff_sec:
                for s in sections:
                    line = s.get("line", "").lower()
                    if "staff" in line or "management" in line:
                        staff_sec = s.get("index")
                        break
            if not staff_sec:
                return []

            time.sleep(0.3)
            sec_url = f"{WIKIPEDIA_API}?action=parse&page={wiki_title}&section={staff_sec}&prop=wikitext&format=json"
            req2 = urllib.request.Request(sec_url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req2, timeout=12) as res2:
                data2 = json.loads(res2.read().decode("utf-8"))
                wikitext = data2.get("parse", {}).get("wikitext", {}).get("*", "")
                raw_records = parse_wikitext_staff(wikitext, club_name)

                # Convert to StaffData structure
                formatted_records = []
                for r in raw_records:
                    if r["role"] == "Head Coach":
                        continue  # Managed by ManagerLoader
                    exp = 20 + ((hash(r["staff_name"]) % 35))
                    attrs = synthesize_attributes(r["role"], exp)
                    salary = 4000 + int(attrs["coaching"] * 12000)
                    dob_year = 1970 + (hash(r["staff_name"]) % 25)
                    dob = f"{dob_year}-05-15"

                    formatted_records.append({
                        "staff_name": r["staff_name"],
                        "role": r["role"],
                        "team_name": club_name,
                        "nationality": r["nationality"],
                        "secondary_nationality": "",
                        "date_of_birth": dob,
                        "experience": exp,
                        "coaching": round(attrs["coaching"], 2),
                        "judging_ability": round(attrs["judging_ability"], 2),
                        "physiotherapy": round(attrs["physiotherapy"], 2),
                        "tactical_knowledge": round(attrs["tactical_knowledge"], 2),
                        "salary_weekly": salary,
                        "contract_years": 2,
                        "spoken_languages": build_spoken_languages(r["nationality"])
                    })
                return formatted_records
    except Exception as e:
        return []


# =============================================================================
# SPORTMONKS INTEGRATION
# =============================================================================

def harvest_sportmonks_staff(token: str, season_ids: List[int]) -> List[Dict[str, Any]]:
    """Harvests non-manager assistant coaches and staff from SportMonks."""
    headers = {"Authorization": token, "Accept": "application/json"}
    staff_records = []

    for s_id in season_ids:
        url = f"{SPORTMONKS_BASE}/teams/seasons/{s_id}?include=coaches.coach.nationality"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=20) as res:
                payload = json.loads(res.read().decode("utf-8"))
                teams = payload.get("data", [])
                for team in teams:
                    t_name = team.get("name")
                    for c in team.get("coaches", []):
                        # Include caretaker managers or assistant staff
                        pos = c.get("position_id")
                        if pos in (560, 226, 227, 228) or (not c.get("active") and pos == 221):
                            coach_obj = c.get("coach")
                            if not coach_obj:
                                continue
                            name = coach_obj.get("display_name") or coach_obj.get("common_name")
                            if not name:
                                continue
                            nat = (coach_obj.get("nationality") or {}).get("name", "English")
                            dob = coach_obj.get("date_of_birth") or "1980-01-01"
                            role = "Assistant Manager" if pos in (560, 226) else ("Goalkeeping Coach" if pos == 227 else "First Team Coach")
                            exp = 25
                            attrs = synthesize_attributes(role, exp)
                            staff_records.append({
                                "staff_name": name,
                                "role": role,
                                "team_name": t_name,
                                "nationality": nat,
                                "secondary_nationality": "",
                                "date_of_birth": dob,
                                "experience": exp,
                                "coaching": round(attrs["coaching"], 2),
                                "judging_ability": round(attrs["judging_ability"], 2),
                                "physiotherapy": round(attrs["physiotherapy"], 2),
                                "tactical_knowledge": round(attrs["tactical_knowledge"], 2),
                                "salary_weekly": 6500,
                                "contract_years": 2,
                                "spoken_languages": build_spoken_languages(nat)
                            })
            time.sleep(0.3)
        except Exception:
            pass

    return staff_records


# =============================================================================
# SQLITE SYNC & EXPORT
# =============================================================================

def save_staff_json(staff: List[Dict[str, Any]], output_path: Path):
    """Saves staff collection to a JSON file."""
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"staff": staff}, f, indent=2, ensure_ascii=False)
    print(f"\n[JSON] Exported {len(staff)} staff members to {output_path.resolve()}")


def update_master_sqlite_staff(staff: List[Dict[str, Any]], db_path: Path):
    """Synchronizes staff records into powerfootball_master.db staff table."""
    if not db_path.exists():
        return

    conn = sqlite3.connect(db_path)
    cur = conn.cursor()

    cur.execute("""
        CREATE TABLE IF NOT EXISTS staff (
            staff_id INTEGER PRIMARY KEY AUTOINCREMENT,
            team_id INTEGER,
            team_name TEXT,
            staff_name TEXT NOT NULL,
            role TEXT NOT NULL,
            nationality TEXT,
            date_of_birth TEXT,
            experience INTEGER DEFAULT 20,
            coaching REAL DEFAULT 0.70,
            judging_ability REAL DEFAULT 0.70,
            physiotherapy REAL DEFAULT 0.70,
            tactical_knowledge REAL DEFAULT 0.70,
            salary_weekly INTEGER DEFAULT 6000,
            contract_years INTEGER DEFAULT 2
        );
    """)

    # Look up team_id mapping from teams table
    cur.execute("SELECT team_id, name FROM teams;")
    team_name_to_id = {row[1].lower(): row[0] for row in cur.fetchall()}

    inserted = 0
    for s in staff:
        t_name = s.get("team_name", "")
        team_id = team_name_to_id.get(t_name.lower())

        # Clean existing identical record
        cur.execute("DELETE FROM staff WHERE staff_name = ? AND team_name = ?;", (s["staff_name"], t_name))

        cur.execute("""
            INSERT INTO staff (
                team_id, team_name, staff_name, role, nationality, date_of_birth,
                experience, coaching, judging_ability, physiotherapy, tactical_knowledge,
                salary_weekly, contract_years
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, (
            team_id, t_name, s["staff_name"], s["role"], s["nationality"], s["date_of_birth"],
            s["experience"], s["coaching"], s["judging_ability"], s["physiotherapy"],
            s["tactical_knowledge"], s["salary_weekly"], s["contract_years"]
        ))
        inserted += 1

    conn.commit()
    conn.close()
    print(f"[SQLite] Synchronized {inserted} staff members into {db_path.resolve()}")


# =============================================================================
# CLI ENTRY POINT
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="Harvest football club backroom staff members across Wikipedia and SportMonks")
    parser.add_argument("--token", type=str, default=os.environ.get("SPORTMONKS_API_TOKEN", DEFAULT_API_TOKEN), help="SportMonks API token")
    parser.add_argument("--top-clubs", action="store_true", default=True, help="Harvest elite European and worldwide clubs")
    parser.add_argument("--include-sportmonks", action="store_true", help="Also query SportMonks active seasons for assistant coaching staff")
    parser.add_argument("--output-json", type=Path, default=Path("data_pipeline/data_lake_2026/staff_2026.json"), help="Output JSON path")
    parser.add_argument("--sync-godot", action="store_true", help="Also write to data/staff_2026.json")
    parser.add_argument("--sync-sqlite", action="store_true", help="Synchronize staff table in powerfootball_master.db")
    args = parser.parse_args()

    print("==========================================================")
    print("POWERFOOTBALL-2D: BACKROOM STAFF HARVESTER")
    print("==========================================================")

    all_staff: List[Dict[str, Any]] = []
    seen_keys: Set[Tuple[str, str]] = set()

    # 1. Curated elite staff
    print(f"\n[Fas 1] Importing {len(CURATED_STAFF)} curated marquee technical directors, scouts & set piece coaches...")
    for s in CURATED_STAFF:
        all_staff.append(s)
        seen_keys.add((s["staff_name"], s["team_name"]))

    # 2. Wikipedia Harvester across Elite Clubs
    print(f"\n[Fas 2] Harvesting backroom staff tables across {len(ELITE_CLUBS)} elite clubs...")
    for idx, (club_name, wiki_title) in enumerate(ELITE_CLUBS, 1):
        print(f"  [{idx:2d}/{len(ELITE_CLUBS)}] {club_name:26} -> {wiki_title}")
        club_staff = harvest_wikipedia_club_staff(club_name, wiki_title)
        added_count = 0
        for s in club_staff:
            key = (s["staff_name"], s["team_name"])
            if key not in seen_keys:
                all_staff.append(s)
                seen_keys.add(key)
                added_count += 1
        print(f"      + Extracted {added_count} staff members (e.g. {club_staff[0]['role'] if club_staff else 'None'})")
        time.sleep(0.4)

    # 3. Optional SportMonks Harvester
    if args.include_sportmonks:
        print("\n[Fas 3] Querying SportMonks seasons for assistant and caretaker coaches...")
        top_season_ids = [28083, 27965, 27895, 28005, 27913]  # EPL, La Liga, Serie A, Bundesliga, Ligue 1
        sm_staff = harvest_sportmonks_staff(args.token, top_season_ids)
        sm_added = 0
        for s in sm_staff:
            key = (s["staff_name"], s["team_name"])
            if key not in seen_keys:
                all_staff.append(s)
                seen_keys.add(key)
                sm_added += 1
        print(f"      + Added {sm_added} assistant coaches from SportMonks.")

    # 4. Export
    save_staff_json(all_staff, args.output_json)

    if args.sync_godot:
        save_staff_json(all_staff, Path("data/staff_2026.json"))

    if args.sync_sqlite:
        for db_loc in [Path("data_pipeline/powerfootball_master.db"), Path("data/powerfootball_master.db")]:
            if db_loc.exists():
                update_master_sqlite_staff(all_staff, db_loc)

    # Summary by role
    role_counts: Dict[str, int] = {}
    for s in all_staff:
        r = s.get("role", "Unknown")
        role_counts[r] = role_counts.get(r, 0) + 1

    print("\n==========================================================")
    print("STAFF HARVESTING SUMMARY BY ROLE:")
    for role, count in sorted(role_counts.items(), key=lambda x: -x[1]):
        print(f"  {role:26}: {count:4d}")
    print(f"TOTAL BACKROOM STAFF HARVESTED: {len(all_staff)}")
    print("==========================================================")


if __name__ == "__main__":
    main()
