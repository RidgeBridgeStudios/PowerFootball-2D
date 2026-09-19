#!/usr/bin/env python3
"""
enrich_datalake_wiki.py

Enrichment module for PowerFootball-2D club encyclopedic data.
Fetches verified Wikipedia summaries, extracts, and Wikidata QIDs for football clubs
in the PowerFootball database (data/powerfootball_master.db) and data lake.

Ensures strict association football entity resolution:
- Rejects non-football sports (e.g. basketball, rugby, cricket).
- Resolves name collisions using country, city, and league context.
- Maintains gender isolation (men's vs women's clubs).
- Supports direct SQLite database updates and multi-threaded queries.
"""

import argparse
import json
import os
import pathlib
import re
import sqlite3
import sys
import time
import unicodedata
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="backslashreplace")
        sys.stderr.reconfigure(encoding="utf-8", errors="backslashreplace")
    except Exception:
        pass

# =============================================================================
# CONFIGURATION & CONSTANTS
# =============================================================================
DEFAULT_DB_PATH = Path("data/powerfootball_master.db")
DATA_LAKE_DIR = Path("data_pipeline/data_lake_2026")
WIKIDATA_OUTPUT_FILE = DATA_LAKE_DIR / "raw_wikidata_clubs.jsonl"
WIKIPEDIA_OUTPUT_FILE = DATA_LAKE_DIR / "raw_wikipedia_extracts.jsonl"

WIKIPEDIA_USER_AGENT = (
    "PowerFootballDataBot/2.0 "
    "(https://github.com/businessgaberino-commits/PowerFootball-2D; "
    "dev@powerfootball.local)"
)
REQUEST_TIMEOUT = 12

SPORTMONKS_COUNTRY_MAP: Dict[str, Tuple[str, ...]] = {
    "462": ("England", "United Kingdom", "English", "Britain", "British", "UK"),
    "11": ("Germany", "German", "Deutschland"),
    "32": ("Spain", "Spanish", "España"),
    "251": ("Italy", "Italian", "Italia"),
    "17": ("France", "French"),
    "38": ("Netherlands", "Dutch", "Holland"),
    "47": ("Sweden", "Swedish", "Sverige"),
    "1578": ("Norway", "Norwegian", "Norge"),
    "20": ("Portugal", "Portuguese"),
    "5": ("Brazil", "Brazilian", "Brasil"),
    "44": ("Argentina", "Argentine", "Argentinian"),
    "3483": ("United States", "USA", "American", "US"),
    "1161": ("Scotland", "Scottish"),
    "455": ("Ireland", "Irish", "Republic of Ireland"),
    "458": ("Mexico", "Mexican"),
    "143": ("Austria", "Austrian", "Österreich"),
    "62": ("Switzerland", "Swiss", "Schweiz", "Suisse"),
    "556": ("Belgium", "Belgian", "Belgique"),
    "2": ("Poland", "Polish", "Polska"),
    "245": ("Czech Republic", "Czech", "Czechia"),
    "266": ("Croatia", "Croatian", "Hrvatska"),
    "116": ("Denmark", "Danish", "Danmark"),
    "1233": ("Finland", "Finnish", "Suomi"),
    "1796": ("Iceland", "Icelandic", "Ísland"),
    "404": ("Turkey", "Turkish", "Türkiye"),
    "802": ("Israel", "Israeli"),
    "748": ("Latvia", "Latvian"),
    "2079": ("Lithuania", "Lithuanian"),
    "2405": ("Estonia", "Estonian"),
    "479": ("Japan", "Japanese"),
    "712": ("South Korea", "Korean", "Korea"),
    "98": ("Australia", "Australian"),
    "146": ("South Africa", "South African"),
    "886": ("Egypt", "Egyptian"),
    "1424": ("Morocco", "Moroccan"),
    "353": ("Colombia", "Colombian"),
    "674": ("Hungary", "Hungarian", "Magyar"),
    "401": ("Slovakia", "Slovak"),
    "1638": ("Slovenia", "Slovenian"),
    "224": ("Bulgaria", "Bulgarian"),
    "227": ("Russia", "Russian"),
    "212": ("Belarus", "Belarusian"),
    "119": ("Georgia", "Georgian"),
    "125": ("Greece", "Greek"),
    "296": ("Serbia", "Serbian"),
    "320": ("Romania", "Romanian"),
    "338": ("Uruguay", "Uruguayan"),
    "488": ("Iran", "Iranian"),
    "2802": ("United Arab Emirates", "UAE", "Emirati"),
    "74505": ("Qatar", "Qatari"),
    "35376": ("Saudi Arabia", "Saudi"),
    "153732": ("India", "Indian"),
    "49477": ("Thailand", "Thai"),
    "69697": ("Vietnam", "Vietnamese"),
    "88407": ("Indonesia", "Indonesian"),
    "5618": ("China", "Chinese"),
    "21462": ("Kuwait", "Kuwaiti"),
    "80": ("Chile", "Chilean"),
    "158": ("Paraguay", "Paraguayan"),
    "459": ("Ecuador", "Ecuadorian"),
    "515": ("Peru", "Peruvian"),
    "7598": ("Bolivia", "Bolivian"),
    "107": ("Iraq", "Iraqi"),
    "97374": ("Bahrain", "Bahraini"),
    "16175": ("Northern Ireland", "Northern Irish"),
    "2756": ("Wales", "Welsh"),
    "2427": ("Kazakhstan", "Kazakh"),
    "2453": ("Azerbaijan", "Azerbaijani"),
    "3995": ("Armenia", "Armenian"),
    "190321": ("Singapore", "Singaporean"),
    "1439": ("Algeria", "Algerian"),
    "1004": ("Jordan", "Jordanian"),
}

KNOWN_ALIASES: Dict[str, str] = {
    "arsenal": "Arsenal F.C.",
    "crystal palace": "Crystal Palace F.C.",
    "chelsea": "Chelsea F.C.",
    "liverpool": "Liverpool F.C.",
    "manchester united": "Manchester United F.C.",
    "manchester city": "Manchester City F.C.",
    "everton": "Everton F.C.",
    "newcastle united": "Newcastle United F.C.",
    "tottenham hotspur": "Tottenham Hotspur F.C.",
    "aston villa": "Aston Villa F.C.",
    "afc bournemouth": "AFC Bournemouth",
    "schalke 04": "FC Schalke 04",
    "genoa": "Genoa CFC",
    "chorley": "Chorley F.C.",
    "hapoel jerusalem": "Hapoel Jerusalem F.C.",
    "hapoel tel aviv": "Hapoel Tel Aviv F.C.",
    "grazer ak": "Grazer AK",
    "hércules": "Hércules CF",
    "hercules": "Hércules CF",
    "łks łódź": "ŁKS Łódź",
    "lks lodz": "ŁKS Łódź",
    "mineros de zacatecas": "Mineros de Zacatecas",
    "us monastir": "US Monastir (football)",
    "al-najma": "Al-Najma SC (Bahrain)",
    "wolverhampton wanderers": "Wolverhampton Wanderers F.C.",
    "west ham united": "West Ham United F.C.",
    "brighton & hove albion": "Brighton & Hove Albion F.C.",
    "nottingham forest": "Nottingham Forest F.C.",
    "leicester city": "Leicester City F.C.",
    "southampton": "Southampton F.C.",
    "ipswich town": "Ipswich Town F.C.",
    "brentford": "Brentford F.C.",
    "fulham": "Fulham F.C.",
    "leeds united": "Leeds United F.C.",
    "sunderland": "Sunderland A.F.C.",
    "burnley": "Burnley F.C.",
    "sheffield united": "Sheffield United F.C.",
    "norwich city": "Norwich City F.C.",
    "west bromwich albion": "West Bromwich Albion F.C.",
    "middlesbrough": "Middlesbrough F.C.",
    "coventry city": "Coventry City F.C.",
    "hull city": "Hull City A.F.C.",
    "stoke city": "Stoke City F.C.",
    "blackburn rovers": "Blackburn Rovers F.C.",
    "preston north end": "Preston North End F.C.",
    "millwall": "Millwall F.C.",
    "queens park rangers": "Queens Park Rangers F.C.",
    "qpr": "Queens Park Rangers F.C.",
    "swansea city": "Swansea City A.F.C.",
    "cardiff city": "Cardiff City F.C.",
    "watford": "Watford F.C.",
    "bristol city": "Bristol City F.C.",
    "plymouth argyle": "Plymouth Argyle F.C.",
    "portsmouth": "Portsmouth F.C.",
    "derby county": "Derby County F.C.",
    "oxford united": "Oxford United F.C.",
    "luton town": "Luton Town F.C.",
    "inter": "Inter Milan",
    "internazionale": "Inter Milan",
    "milan": "A.C. Milan",
    "ac milan": "A.C. Milan",
    "juventus": "Juventus FC",
    "roma": "AS Roma",
    "as roma": "AS Roma",
    "lazio": "SS Lazio",
    "napoli": "SSC Napoli",
    "fiorentina": "ACF Fiorentina",
    "atalanta": "Atalanta B.C.",
    "bologna": "Bologna F.C. 1909",
    "torino": "Torino F.C.",
    "monza": "AC Monza",
    "udinese": "Udinese Calcio",
    "genoa": "Genoa CFC",
    "cagliari": "Cagliari Calcio",
    "hellas verona": "Hellas Verona FC",
    "verona": "Hellas Verona FC",
    "empoli": "Empoli F.C.",
    "lecce": "U.S. Lecce",
    "parma": "Parma Calcio 1913",
    "como": "Como 1907",
    "venezia": "Venezia FC",
    "salernitana": "US Salernitana 1919",
    "sassuolo": "U.S. Sassuolo Calcio",
    "frosinone": "Frosinone Calcio",
    "sampdoria": "U.C. Sampdoria",
    "real madrid": "Real Madrid CF",
    "barcelona": "FC Barcelona",
    "fc barcelona": "FC Barcelona",
    "atletico madrid": "Atlético Madrid",
    "atlético madrid": "Atlético Madrid",
    "athletic club": "Athletic Bilbao",
    "athletic bilbao": "Athletic Bilbao",
    "real sociedad": "Real Sociedad",
    "real betis": "Real Betis",
    "villarreal": "Villarreal CF",
    "sevilla": "Sevilla FC",
    "valencia": "Valencia CF",
    "girona": "Girona FC",
    "celta vigo": "RC Celta de Vigo",
    "osasuna": "CA Osasuna",
    "getafe": "Getafe CF",
    "rayo vallecano": "Rayo Vallecano",
    "mallorca": "RCD Mallorca",
    "rcd mallorca": "RCD Mallorca",
    "deportivo alavés": "Deportivo Alavés",
    "alaves": "Deportivo Alavés",
    "espanyol": "RCD Espanyol",
    "rcd espanyol": "RCD Espanyol",
    "las palmas": "UD Las Palmas",
    "cd leganés": "CD Leganés",
    "leganes": "CD Leganés",
    "real valladolid": "Real Valladolid",
    "bayern münchen": "FC Bayern Munich",
    "bayern munich": "FC Bayern Munich",
    "fc bayern münchen": "FC Bayern Munich",
    "fc bayern munich": "FC Bayern Munich",
    "borussia dortmund": "Borussia Dortmund",
    "bayer leverkusen": "Bayer 04 Leverkusen",
    "rb leipzig": "RB Leipzig",
    "eintracht frankfurt": "Eintracht Frankfurt",
    "vfb stuttgart": "VfB Stuttgart",
    "vfl wolfsburg": "VfL Wolfsburg",
    "borussia mönchengladbach": "Borussia Mönchengladbach",
    "sc freiburg": "SC Freiburg",
    "tsg hoffenheim": "TSG 1899 Hoffenheim",
    "1. fc heidenheim": "1. FC Heidenheim",
    "fc augsburg": "FC Augsburg",
    "werder bremen": "SV Werder Bremen",
    "1. fc union berlin": "1. FC Union Berlin",
    "union berlin": "1. FC Union Berlin",
    "1. fsv mainz 05": "1. FSV Mainz 05",
    "mainz 05": "1. FSV Mainz 05",
    "fc st. pauli": "FC St. Pauli",
    "st. pauli": "FC St. Pauli",
    "holstein kiel": "Holstein Kiel",
    "vfl bochum": "VfL Bochum",
    "paris saint-germain": "Paris Saint-Germain F.C.",
    "paris saint germain": "Paris Saint-Germain F.C.",
    "psg": "Paris Saint-Germain F.C.",
    "marseille": "Olympique de Marseille",
    "olympique de marseille": "Olympique de Marseille",
    "lyon": "Olympique Lyonnais",
    "olympique lyonnais": "Olympique Lyonnais",
    "monaco": "AS Monaco FC",
    "as monaco": "AS Monaco FC",
    "lille": "Lille OSC",
    "lille osc": "Lille OSC",
    "rennes": "Stade Rennais F.C.",
    "stade rennais": "Stade Rennais F.C.",
    "nice": "OGC Nice",
    "ogc nice": "OGC Nice",
    "lens": "RC Lens",
    "rc lens": "RC Lens",
    "ajax": "AFC Ajax",
    "afc ajax": "AFC Ajax",
    "psv": "PSV Eindhoven",
    "psv eindhoven": "PSV Eindhoven",
    "feyenoord": "Feyenoord",
    "sporting cp": "Sporting CP",
    "sporting": "Sporting CP",
    "benfica": "S.L. Benfica",
    "sl benfica": "S.L. Benfica",
    "porto": "FC Porto",
    "fc porto": "FC Porto",
    "celtic": "Celtic F.C.",
    "rangers": "Rangers F.C.",
    "galatasaray": "Galatasaray S.K. (football)",
    "fenerbahce": "Fenerbahçe S.K. (football)",
    "fenerbahçe": "Fenerbahçe S.K. (football)",
    "besiktas": "Beşiktaş J.K.",
    "beşiktaş": "Beşiktaş J.K.",
    "boca juniors": "Boca Juniors",
    "river plate": "Club Atlético River Plate",
    "flamengo": "CR Flamengo",
    "palmeiras": "SE Palmeiras",
    "são paulo": "São Paulo FC",
    "corinthians": "Sport Club Corinthians Paulista",
    "santos": "Santos FC",
    "gremio": "Grêmio Foot-Ball Porto Alegrense",
    "grêmio": "Grêmio Foot-Ball Porto Alegrense",
    "internacional": "Sport Club Internacional",
    "fluminense": "Fluminense FC",
    "botafogo": "Botafogo de Futebol e Regatas",
    "cruzeiro": "Cruzeiro Esporte Clube",
    "vasco da gama": "CR Vasco da Gama",
    "club brugge": "Club Brugge KV",
    "anderlecht": "R.S.C. Anderlecht",
    "kaa gent": "K.A.A. Gent",
    "genk": "K.R.C. Genk",
    "standard liege": "Standard Liège",
    "red bull salzburg": "FC Red Bull Salzburg",
    "salzburg": "FC Red Bull Salzburg",
    "sturm graz": "SK Sturm Graz",
    "rapid wien": "SK Rapid Wien",
    "young boys": "BSC Young Boys",
    "basel": "FC Basel",
    "fc basel": "FC Basel",
    "fc zurich": "FC Zürich",
    "sparta praha": "AC Sparta Prague",
    "sparta prague": "AC Sparta Prague",
    "slavia praha": "SK Slavia Prague",
    "slavia prague": "SK Slavia Prague",
    "viktoria plzen": "FC Viktoria Plzeň",
    "dinamo zagreb": "GNK Dinamo Zagreb",
    "hajduk split": "HNK Hajduk Split",
    "paok": "PAOK FC",
    "olympiacos": "Olympiacos F.C.",
    "panathinaikos": "Panathinaikos F.C.",
    "aek athens": "AEK Athens F.C.",
    "red star belgrade": "Red Star Belgrade",
    "crvena zvezda": "Red Star Belgrade",
    "partizan": "FK Partizan",
    "shakhtar donetsk": "FC Shakhtar Donetsk",
    "dynamo kyiv": "FC Dynamo Kyiv",
    "malmö ff": "Malmö FF",
    "aik": "AIK Fotboll",
    "djurgårdens if": "Djurgårdens IF Fotboll",
    "djurgarden": "Djurgårdens IF Fotboll",
    "ifk göteborg": "IFK Göteborg",
    "hammarby": "Hammarby Fotboll",
    "bodø/glimt": "FK Bodø/Glimt",
    "rosenborg": "Rosenborg BK",
    "molde": "Molde FK",
    "sk brann": "SK Brann",
    "brann": "SK Brann",
    "viking": "Viking FK",
    "fc copenhagen": "F.C. Copenhagen",
    "københavn": "F.C. Copenhagen",
    "brøndby": "Brøndby IF",
    "fc midtjylland": "FC Midtjylland",
    "midtjylland": "FC Midtjylland",
    "al hilal": "Al Hilal SFC",
    "al nassr": "Al Nassr FC",
    "al ittihad": "Al-Ittihad Club (Jeddah)",
    "al ahli": "Al-Ahli Saudi FC",
    "inter miami": "Inter Miami CF",
    "la galaxy": "LA Galaxy",
    "los angeles fc": "Los Angeles FC",
    "new york red bulls": "New York Red Bulls",
    "atlanta united": "Atlanta United FC",
    "seattle sounders": "Seattle Sounders FC",
    "portland timbers": "Portland Timbers",
    "toronto fc": "Toronto FC",
}


class WikipediaClient:
    """Handles HTTP requests to Wikipedia REST and Search APIs with session reuse and error handling."""

    def __init__(self, user_agent: str = WIKIPEDIA_USER_AGENT):
        self.headers = {"User-Agent": user_agent, "Accept": "application/json"}
        self._cache: Dict[str, Optional[dict]] = {}

    def fetch_summary(self, title: str, retries: int = 2) -> Optional[dict]:
        clean_title = title.strip().replace(" ", "_")
        cache_key = clean_title.lower()
        if cache_key in self._cache:
            return self._cache[cache_key]

        url = f"https://en.wikipedia.org/api/rest_v1/page/summary/{urllib.parse.quote(clean_title)}"
        for attempt in range(retries + 1):
            req = urllib.request.Request(url, headers=self.headers)
            try:
                with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode("utf-8"))
                        self._cache[cache_key] = data
                        return data
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    self._cache[cache_key] = None
                    return None
                elif e.code == 429:
                    time.sleep(2.0 * (attempt + 1))
                elif e.code >= 500:
                    time.sleep(1.0 * (attempt + 1))
            except Exception:
                if attempt < retries:
                    time.sleep(1.0 * (attempt + 1))

        return None

    def search(self, query: str, limit: int = 5, retries: int = 2) -> List[str]:
        url = (
            "https://en.wikipedia.org/w/api.php?"
            f"action=query&list=search&srsearch={urllib.parse.quote(query)}"
            f"&format=json&srlimit={limit}"
        )
        for attempt in range(retries + 1):
            req = urllib.request.Request(url, headers=self.headers)
            try:
                with urllib.request.urlopen(req, timeout=REQUEST_TIMEOUT) as resp:
                    if resp.status == 200:
                        data = json.loads(resp.read().decode("utf-8"))
                        return [item["title"] for item in data.get("query", {}).get("search", [])]
            except urllib.error.HTTPError as e:
                if e.code == 429:
                    time.sleep(2.0 * (attempt + 1))
                elif e.code >= 500:
                    time.sleep(1.0 * (attempt + 1))
            except Exception:
                if attempt < retries:
                    time.sleep(1.0 * (attempt + 1))
        return []


def is_valid_football_club(
    summary: dict,
    target_gender: str = "men",
    country_keywords: Optional[List[str]] = None,
    venue_city: Optional[str] = None,
) -> bool:
    """Validates that a Wikipedia summary represents a genuine association football club."""
    if not summary:
        return False

    page_type = summary.get("type", "")
    if page_type in ("disambiguation", "no-extract"):
        return False

    title = summary.get("title", "")
    title_lower = title.lower()
    desc = (summary.get("description") or "").lower()
    extract = (summary.get("extract") or "")
    extract_lower = extract.lower()
    full_text = f"{title_lower} {desc} {extract_lower}"

    # 1. Hard Blacklist: Reject persons / players / coaches / referees
    person_terms = [
        "footballer", "soccer player", "football player", "goalkeeper",
        "midfielder", "defender", "forward", "striker", "coach", "referee",
        "biography", "athlete", "politician"
    ]
    for term in person_terms:
        if re.search(r"\b" + re.escape(term) + r"\b", desc):
            return False
    if re.search(r"\b(footballer|manager|coach|referee)\b", title_lower):
        return False
    if re.search(r"\b(is|was)\s+(an?|[a-z\s]+)\s+(professional\s+)?(footballer|player|manager|coach|referee)\b", extract_lower[:150]):
        return False
    if re.search(r"\(born\s+(\d{1,2}\s+[a-zA-Z]+\s+)?\d{4}\)", extract[:150]):
        return False
    if re.search(r"\b(plays|played)\s+as\s+a\s+(midfielder|defender|forward|striker|goalkeeper|winger|back)\b", extract_lower[:150]):
        return False

    # 2. Hard Blacklist: Reject non-football sports
    blacklisted_sports = [
        "basketball", "rugby union", "rugby league", "cricket club",
        "ice hockey", "field hockey", "baseball", "american football",
        "handball", "water polo", "volleyball team", "motor racing",
        "formula one", "athletics club", "gaelic football", "australian rules"
    ]
    for sport in blacklisted_sports:
        if sport in desc and not ("football" in desc or "soccer" in desc):
            return False
        # Reject if the sport appears as a primary definition without a football section/club
        if re.search(r"\b" + re.escape(sport) + r"\b", extract_lower[:250]):
            has_football = any(f in extract_lower[:250] for f in [
                "football club", "soccer club", "football section", "football department", "football team"
            ])
            if not has_football:
                return False

    # 3. Reject non-club pages (seasons, leagues, tournaments, lists, stadiums, derbies)
    if re.search(r"\bseason\b", title_lower) or re.search(r"^\d{4}([-–/]\d{2,4})?\s+", title_lower):
        return False
    if re.search(r"^(the\s+)?\d{4}([-–/]\d{2,4})?\s+.*\bseason\b", extract_lower[:100]):
        return False
    if title_lower.startswith("list of ") or "list of " in title_lower:
        return False
    bad_page_terms = ["disambiguation", "season", "stadium", "derby", "rivalry", "academy"]
    for term in bad_page_terms:
        if f"({term})" in title_lower or title_lower.endswith(f" {term}"):
            return False

    # 4. Positive Football Signals: Must describe a football/soccer entity
    football_signals = [
        "football club", "soccer club", "association football", "football team",
        "soccer team", "football section", "football department", "professional football club",
        "premier league", "la liga", "serie a", "bundesliga", "ligue 1", "eredivisie",
        "allsvenskan", "eliteserien", "championship", "top flight of", "first tier of", "football league"
    ]
    if not any(sig in full_text for sig in football_signals):
        return False

    # 5. Gender Isolation
    women_indicators = ["women", "w.f.c.", "femenino", "frauen", "damer", "féminines", "vrouwen"]
    is_women_article = any(w in title_lower or w in desc for w in women_indicators)

    if target_gender == "men" and is_women_article:
        return False
    if target_gender == "women" and not is_women_article:
        pass

    # 5. Geographic Disambiguation (prevent wrong country matching)
    if country_keywords:
        country_matched = any(k.lower() in full_text for k in country_keywords)
        city_matched = venue_city and venue_city.lower() in full_text

        # If neither country nor city is mentioned, check if another distinct nation is claimed
        if not country_matched and not city_matched:
            # Check for strong collision signals (e.g. "club based in Maseru, Lesotho" for English club)
            first_sentence = extract_lower[:200]
            for c_id, names in SPORTMONKS_COUNTRY_MAP.items():
                primary_name = names[0].lower()
                if primary_name not in [k.lower() for k in country_keywords]:
                    if f"in {primary_name}" in first_sentence or f"based in {primary_name}" in first_sentence:
                        return False

    return True


def strip_accents(text: str) -> str:
    """Removes diacritics and accents for robust Wikipedia searching."""
    return "".join(
        c for c in unicodedata.normalize("NFKD", text)
        if unicodedata.category(c) != "Mn"
    )


def generate_candidate_titles(name: str, gender: str = "men") -> List[str]:
    """Generates ordered Wikipedia article title candidates based on club naming conventions."""
    candidates: List[str] = []
    clean_name = name.strip()
    name_lower = clean_name.lower()
    ascii_name = strip_accents(clean_name)

    # 1. Known alias check
    if name_lower in KNOWN_ALIASES:
        candidates.append(KNOWN_ALIASES[name_lower])
    if ascii_name.lower() in KNOWN_ALIASES:
        candidates.append(KNOWN_ALIASES[ascii_name.lower()])

    # 2. Gender-specific candidates for women's teams
    if gender == "women" or name_lower.endswith(" w") or name_lower.endswith(" women"):
        base = re.sub(r"(?i)\s+(w|women|w\.f\.c\.?|femenino)$", "", clean_name).strip()
        base_ascii = strip_accents(base)
        candidates.extend([
            f"{base} W.F.C.",
            f"{base} F.C. Women",
            f"{base} Women",
            f"{base} Femenino",
            f"{base} (women)",
            f"{base_ascii} W.F.C.",
            f"{base_ascii} Women",
            f"{clean_name} W.F.C.",
            f"{clean_name} Women",
        ])

    # 3. Standard football club patterns
    base_name = re.sub(
        r"(?i)\s+(f\.?c\.?|c\.?f\.?|s\.?v\.?|s\.?c\.?|b\.?s\.?c\.?|a\.?c\.?|a\.?s\.?|f\.?k\.?|i\.?f\.?|b\.?k\.?|s\.?k\.?|f\.?f\.?|i\.?k\.?|u21|u19|ii)$",
        "",
        clean_name,
    ).strip()
    base_ascii = strip_accents(base_name)

    # Direct and F.C. candidates
    candidates.extend([
        f"{clean_name} F.C.",
        f"{clean_name} A.F.C.",
        clean_name,
        f"FC {clean_name}",
        f"{clean_name} FC",
        f"{clean_name} CF",
    ])

    if ascii_name != clean_name:
        candidates.extend([
            f"{ascii_name} F.C.",
            f"{ascii_name} A.F.C.",
            ascii_name,
            f"FC {ascii_name}",
            f"{ascii_name} FC",
            f"{ascii_name} CF",
        ])

    if base_name and base_name != clean_name:
        candidates.extend([
            f"{base_name} F.C.",
            f"{base_name} A.F.C.",
            base_name,
            f"FC {base_name}",
            f"{base_name} FC",
            f"{base_name} CF",
        ])

    # Common continental prefixes and formats
    for n in [clean_name, ascii_name, base_name]:
        if not n:
            continue
        candidates.extend([
            f"AS {n}",
            f"RC {n}",
            f"OGC {n}",
            f"Real {n}",
            f"CD {n}",
            f"UD {n}",
            f"CA {n}",
            f"1. FC {n}",
            f"SV {n}",
            f"VfL {n}",
            f"VfB {n}",
            f"AC {n}",
            f"SS {n}",
            f"US {n}",
            f"SSC {n}",
            f"SBV {n}",
            f"{n} SC",
            f"{n} Club",
        ])
        if n.startswith("Al "):
            candidates.append(f"Al-{n[3:]}")
            candidates.append(f"Al-{n[3:]} SC")
            candidates.append(f"Al-{n[3:]} FC")
        elif n.startswith("Al-"):
            candidates.append(f"Al {n[3:]}")

    # Remove duplicates while preserving priority order
    seen: Set[str] = set()
    ordered: List[str] = []
    for c in candidates:
        norm = c.strip()
        if norm and norm.lower() not in seen:
            seen.add(norm.lower())
            ordered.append(norm)

    return ordered


class TeamEnrichmentWorker:
    """Resolves a single club to its correct Wikipedia extract and Wikidata QID."""

    def __init__(self, client: WikipediaClient):
        self.client = client

    def resolve_team(self, team_row: dict) -> Optional[dict]:
        name = team_row["name"]
        gender = (team_row.get("gender") or "men").lower()
        country_code = str(team_row.get("country_code") or "")
        league_name = team_row.get("league_name") or ""
        venue_city = team_row.get("venue_city")

        country_keywords = list(SPORTMONKS_COUNTRY_MAP.get(country_code, ()))
        candidates = generate_candidate_titles(name, gender)

        # 1. Try direct candidates
        for cand in candidates:
            summary = self.client.fetch_summary(cand)
            if summary and is_valid_football_club(summary, gender, country_keywords, venue_city):
                return self._build_result(team_row, summary)

        # 2. Search fallback with country context
        country_primary = country_keywords[0] if country_keywords else ""
        ascii_name = strip_accents(name)
        search_queries = []

        if country_primary:
            search_queries.append(f"{name} football club {country_primary}")
            search_queries.append(f'"{name}" football club {country_primary}')
            search_queries.append(f"{name} {league_name}")
            if ascii_name != name:
                search_queries.append(f"{ascii_name} football club {country_primary}")
        else:
            search_queries.append(f"{name} football club")

        if venue_city:
            search_queries.append(f"{name} football club {venue_city}")

        for sq in search_queries:
            titles = self.client.search(sq, limit=4)
            for t in titles:
                summary = self.client.fetch_summary(t)
                if summary and is_valid_football_club(summary, gender, country_keywords, venue_city):
                    return self._build_result(team_row, summary)

        return None

    def _build_result(self, team_row: dict, summary: dict) -> dict:
        return {
            "team_id": team_row["team_id"],
            "name": team_row["name"],
            "wikipedia_title": summary.get("title"),
            "extract": summary.get("extract"),
            "description": summary.get("description"),
            "wikidata_qid": summary.get("wikibase_item"),
            "thumbnail_url": summary.get("thumbnail", {}).get("source"),
        }


def get_godot_user_db_path() -> Optional[Path]:
    """Resolves the platform-specific user:// directory for PowerFootball 2D."""
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        if appdata:
            return Path(appdata) / "Godot" / "app_userdata" / "PowerFootball 2D" / "powerfootball_master.db"
    elif sys.platform == "darwin":
        home = os.environ.get("HOME")
        if home:
            return Path(home) / "Library" / "Application Support" / "Godot" / "app_userdata" / "PowerFootball 2D" / "powerfootball_master.db"
    else:
        home = os.environ.get("HOME")
        if home:
            return Path(home) / ".local" / "share" / "godot" / "app_userdata" / "PowerFootball 2D" / "powerfootball_master.db"
    return None


def sync_to_user_db(src_db: Path) -> bool:
    """Synchronizes the updated master database to user:// for immediate Godot runtime use."""
    user_db = get_godot_user_db_path()
    if not user_db:
        print("[Sync] Unable to resolve user DB path for this OS.")
        return False

    try:
        user_db.parent.mkdir(parents=True, exist_ok=True)
        # Remove WAL and SHM files to avoid SQLite journal conflicts
        wal_file = user_db.with_name(user_db.name + "-wal")
        shm_file = user_db.with_name(user_db.name + "-shm")
        if wal_file.exists():
            wal_file.unlink()
        if shm_file.exists():
            shm_file.unlink()

        # Copy database
        with open(src_db, "rb") as fsrc, open(user_db, "wb") as fdst:
            fdst.write(fsrc.read())

        print(f"[Sync] Successfully synchronized master database to:\n  -> {user_db}")
        return True
    except Exception as e:
        print(f"[Sync Error] Failed to synchronize to {user_db}: {e}")
        return False


def append_jsonl(file_path: Path, payload: dict) -> None:
    """Appends a single JSON record to a JSONL file."""
    try:
        file_path.parent.mkdir(parents=True, exist_ok=True)
        with open(file_path, "a", encoding="utf-8") as f:
            f.write(json.dumps(payload, ensure_ascii=False) + "\n")
    except Exception:
        pass


def run_pipeline(args: argparse.Namespace) -> None:
    db_path = Path(args.db_path)
    if not db_path.exists():
        print(f"Error: Database file not found at {db_path}!")
        sys.exit(1)

    print("==================================================================")
    print("POWERFOOTBALL-2D WIKIPEDIA & WIKIDATA ENRICHMENT PIPELINE")
    print(f"Database: {db_path.resolve()}")
    print("==================================================================")

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Build selection query
    sql = (
        "SELECT t.team_id, t.name, t.gender, t.short_code, t.wikipedia_extract, "
        "t.wikidata_qid, l.league_id, l.name AS league_name, l.country_code, "
        "l.sub_type AS league_type, v.city AS venue_city "
        "FROM teams t "
        "LEFT JOIN leagues l ON t.league_id = l.league_id "
        "LEFT JOIN venues v ON t.venue_id = v.venue_id "
        "WHERE 1=1 "
    )
    params = []

    if args.team_names:
        names = [n.strip() for n in args.team_names.split(",") if n.strip()]
        placeholders = ",".join(["?"] * len(names))
        sql += f"AND t.name IN ({placeholders}) "
        params.extend(names)
    elif args.team_ids:
        ids = [int(i.strip()) for i in args.team_ids.split(",") if i.strip().isdigit()]
        placeholders = ",".join(["?"] * len(ids))
        sql += f"AND t.team_id IN ({placeholders}) "
        params.extend(ids)
    elif args.league_ids:
        l_ids = [int(i.strip()) for i in args.league_ids.split(",") if i.strip().isdigit()]
        placeholders = ",".join(["?"] * len(l_ids))
        sql += f"AND t.league_id IN ({placeholders}) "
        params.extend(l_ids)
    elif args.all_playable:
        sql += "AND l.sub_type = 'domestic' "
    elif not args.all_teams:
        # Default: Domestic leagues
        sql += "AND l.sub_type = 'domestic' "

    if not args.force:
        sql += "AND (t.wikipedia_extract IS NULL OR TRIM(t.wikipedia_extract) = '') "

    sql += "ORDER BY t.team_id ASC"

    cursor.execute(sql, params)
    rows = [dict(r) for r in cursor.fetchall()]

    if args.limit and args.limit > 0:
        rows = rows[:args.limit]

    total_teams = len(rows)
    print(f"Selected {total_teams} teams for enrichment (Force={args.force}).\n")

    if total_teams == 0:
        print("No teams matching criteria need enrichment.")
        conn.close()
        return

    client = WikipediaClient()
    worker = TeamEnrichmentWorker(client)

    success_count = 0
    fail_count = 0
    commit_batch = 25

    print(f"Processing with {args.workers} concurrent workers...")

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        future_to_team = {executor.submit(worker.resolve_team, row): row for row in rows}

        for idx, future in enumerate(as_completed(future_to_team), 1):
            row = future_to_team[future]
            try:
                res = future.result()
            except Exception as e:
                res = None

            if res and res.get("extract"):
                success_count += 1
                cursor.execute(
                    "UPDATE teams SET wikipedia_extract = ?, wikidata_qid = ? WHERE team_id = ?",
                    (res["extract"], res.get("wikidata_qid"), res["team_id"]),
                )
                if args.update_jsonl:
                    append_jsonl(WIKIPEDIA_OUTPUT_FILE, {
                        "wikipedia_title": res["wikipedia_title"],
                        "extract": res["extract"],
                        "description": res.get("description"),
                        "thumbnail_url": res.get("thumbnail_url"),
                    })
                    append_jsonl(WIKIDATA_OUTPUT_FILE, {
                        "wikidata_qid": res.get("wikidata_qid"),
                        "club_label": res["name"],
                        "wikipedia_title": res["wikipedia_title"],
                    })

                status = f"[OK] {row['name']} -> {res['wikipedia_title']} [{res.get('wikidata_qid')}]"
            else:
                fail_count += 1
                status = f"[--] {row['name']} (No valid football extract found)"

            if idx % 10 == 0 or idx == total_teams:
                try:
                    print(f"[{idx}/{total_teams}] ({success_count} resolved, {fail_count} missed) - {status}")
                except Exception:
                    clean_status = status.encode("ascii", "replace").decode("ascii")
                    print(f"[{idx}/{total_teams}] ({success_count} resolved, {fail_count} missed) - {clean_status}")

            if idx % commit_batch == 0 or idx == total_teams:
                conn.commit()

    conn.close()

    print("\n==================================================================")
    print(f"ENRICHMENT COMPLETED: {success_count}/{total_teams} clubs resolved successfully.")
    print("==================================================================")

    if args.sync_user_db:
        sync_to_user_db(db_path)


def main():
    parser = argparse.ArgumentParser(description="Enrich PowerFootball-2D SQLite database with Wikipedia club summaries.")
    parser.add_argument("--db-path", type=str, default=str(DEFAULT_DB_PATH), help="Path to SQLite master database.")
    parser.add_argument("--all-playable", action="store_true", help="Enrich all domestic league teams.")
    parser.add_argument("--all-teams", action="store_true", help="Enrich all teams across the entire database.")
    parser.add_argument("--league-ids", type=str, default="", help="Comma-separated list of league IDs.")
    parser.add_argument("--team-ids", type=str, default="", help="Comma-separated list of team IDs.")
    parser.add_argument("--team-names", type=str, default="", help="Comma-separated list of team names.")
    parser.add_argument("--force", action="store_true", help="Force overwrite existing Wikipedia extracts.")
    parser.add_argument("--limit", type=int, default=0, help="Maximum number of teams to process.")
    parser.add_argument("--workers", type=int, default=8, help="Number of concurrent worker threads.")
    parser.add_argument("--sync-user-db", action="store_true", default=True, help="Sync updated DB to user:// directory.")
    parser.add_argument("--update-jsonl", action="store_true", default=True, help="Update raw data lake JSONL files.")

    args = parser.parse_args()
    run_pipeline(args)


if __name__ == "__main__":
    main()