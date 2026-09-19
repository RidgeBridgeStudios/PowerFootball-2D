#!/usr/bin/env python3
"""
rehydrate_ratings_v2.py

Återställer och garanterar autentiska spelarbetyg i powerfootball_master.db
från de verkliga EA Sports FC 26 (EAFC26-Men.csv) och Football Manager 2023 (FM23.csv)
dataseten som finns i projektet.

Prioriteringsordning:
  1. EA Sports FC 26 (EAFC26-Men.csv) -> rating_source = 'EAFC'
  2. Football Manager 2023 (FM23.csv)   -> rating_source = 'FM23'
  3. Kalibrerad pyramid-procedural     -> rating_source = 'PROCEDURAL'
"""

import argparse
import math
import os
import re
import sqlite3
import time
import unicodedata
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import pandas as pd


# =============================================================================
# SÖKVÄGSHANTERING & INITIALISERING
# =============================================================================
def resolve_paths(custom_db_path: Optional[str] = None) -> Tuple[Path, Optional[Path], Path, Path]:
    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent if (script_dir.parent / "data").exists() else script_dir

    # 1. Master-databas (Godot runtime använder res://data/powerfootball_master.db)
    if custom_db_path:
        primary_db = Path(custom_db_path).resolve()
        secondary_db = None
    else:
        runtime_db = repo_dir / "data" / "powerfootball_master.db"
        pipeline_db = script_dir / "powerfootball_master.db"
        
        if runtime_db.exists():
            primary_db = runtime_db
            secondary_db = pipeline_db if pipeline_db.exists() and pipeline_db != runtime_db else None
        elif pipeline_db.exists():
            primary_db = pipeline_db
            secondary_db = runtime_db if runtime_db.parent.exists() else None
        else:
            primary_db = runtime_db
            secondary_db = None

    # 2. Dataset-källor
    eafc_csv = script_dir / "EAFC26-Men.csv"
    if not eafc_csv.exists() and (repo_dir / "data_pipeline" / "EAFC26-Men.csv").exists():
        eafc_csv = repo_dir / "data_pipeline" / "EAFC26-Men.csv"

    fm23_csv = script_dir / "FM23.csv"
    if not fm23_csv.exists() and (repo_dir / "data_pipeline" / "FM23.csv").exists():
        fm23_csv = repo_dir / "data_pipeline" / "FM23.csv"

    return primary_db, secondary_db, eafc_csv, fm23_csv


# =============================================================================
# STRÄNG- OCH DATA-NORMALISERING
# =============================================================================
TEAM_SYNONYMS: Dict[str, str] = {
    "man city": "manchester city",
    "man utd": "manchester united",
    "spurs": "tottenham hotspur",
    "wolves": "wolverhampton wanderers",
    "newcastle": "newcastle united",
    "west ham": "west ham united",
    "nott m forest": "nottingham forest",
    "notts forest": "nottingham forest",
    "paris sg": "paris saint germain",
    "psg": "paris saint germain",
    "inter": "internazionale",
    "milan": "ac milan",
    "bayern": "bayern munchen",
    "fc bayern": "bayern munchen",
    "dortmund": "borussia dortmund",
    "leverkusen": "bayer 04 leverkusen",
    "bayer leverkusen": "bayer 04 leverkusen",
    "atletico madrid": "atletico de madrid",
    "atletico": "atletico de madrid",
    "real madrid": "real madrid",
    "barcelona": "fc barcelona",
    "barca": "fc barcelona",
    "sporting cp": "sporting",
    "benfica": "sl benfica",
}


def normalize_name(name: Any) -> str:
    if not name or not isinstance(name, str):
        return ""
    n = "".join(c for c in unicodedata.normalize("NFD", name) if unicodedata.category(c) != "Mn")
    n = re.sub(r"[^\w\s]", " ", n.lower())
    return re.sub(r"\s+", " ", n).strip()


def normalize_team(team: Any) -> str:
    if not team or not isinstance(team, str):
        return ""
    t = normalize_name(team)
    t = re.sub(r"\b(fc|afc|cf|sc|ac|as|ss|rc|cd|ud|sv|vfb|bsc|fk|sk|ogc|rb|us)\b", "", t)
    t = re.sub(r"\s+", " ", t).strip()
    return TEAM_SYNONYMS.get(t, t)


def teams_match(team_a: str, team_b: str) -> bool:
    if not team_a or not team_b:
        return False
    ta = normalize_team(team_a)
    tb = normalize_team(team_b)
    if not ta or not tb:
        return False
    if ta == tb:
        return True
    if ta in tb or tb in ta:
        return True
    # Kolla delade signifikanta ord
    words_a = {w for w in ta.split() if len(w) >= 4}
    words_b = {w for w in tb.split() if len(w) >= 4}
    return bool(words_a and words_b and (words_a & words_b))


def parse_weight(val: Any, default: float = 75.0) -> float:
    if val is None or pd.isna(val):
        return default
    if isinstance(val, (int, float)):
        return float(val) if val > 0 else default
    s = str(val).lower()
    m_kg = re.search(r"(\d+(?:\.\d+)?)\s*kg", s)
    if m_kg:
        return float(m_kg.group(1))
    m_lb = re.search(r"(\d+(?:\.\d+)?)\s*lb", s)
    if m_lb:
        return round(float(m_lb.group(1)) * 0.45359237, 1)
    m_num = re.search(r"(\d+(?:\.\d+)?)", s)
    if m_num:
        v = float(m_num.group(1))
        if 40.0 <= v <= 130.0:
            return v
    return default


def parse_height(val: Any, default: int = 180) -> int:
    if val is None or pd.isna(val):
        return default
    if isinstance(val, (int, float)):
        v = int(val)
        return v if 140 <= v <= 220 else default
    s = str(val)
    m_cm = re.search(r"(\d+)\s*cm", s)
    if m_cm:
        return int(m_cm.group(1))
    m_ft = re.search(r"(\d+)'(\d+)\"?", s)
    if m_ft:
        feet = int(m_ft.group(1))
        inches = int(m_ft.group(2))
        return int(round((feet * 12 + inches) * 2.54))
    m_num = re.search(r"(\d+)", s)
    if m_num:
        v = int(m_num.group(1))
        if 140 <= v <= 220:
            return v
    return default


def parse_birth_year(dob: Any, age: Any = None, ref_year: int = 2025) -> Optional[int]:
    if dob and isinstance(dob, str) and not pd.isna(dob):
        m = re.search(r"(\d{4})", dob)
        if m:
            y = int(m.group(1))
            if 1960 <= y <= 2015:
                return y
    if age and not pd.isna(age):
        try:
            a = int(float(age))
            if 15 <= a <= 55:
                return ref_year - a
        except (ValueError, TypeError):
            pass
    return None


def clamp_stat(val: float, low: float = 0.05, high: float = 0.99) -> float:
    return max(low, min(high, round(val, 3)))


# =============================================================================
# PYRAMID-REGLER OCH BASLINJER FÖR FALLBACK
# =============================================================================
PYRAMID_RULES: List[Tuple[str, int, float]] = [
    # England
    (r"premier league$", 1, 0.76),
    (r"championship$", 2, 0.58),
    (r"league one", 3, 0.45),
    (r"league two", 4, 0.36),
    (r"national league$", 5, 0.28),
    (r"national league north|national league south", 6, 0.22),

    # Spanien
    (r"la liga$", 1, 0.75),
    (r"la liga 2|segunda divisi[oó]n", 2, 0.55),
    (r"primera federaci[oó]n", 3, 0.42),
    (r"segunda federaci[oó]n", 4, 0.32),

    # Tyskland
    (r"^bundesliga$", 1, 0.74),
    (r"2\. bundesliga", 2, 0.56),
    (r"3\. liga", 3, 0.44),
    (r"regionalliga", 4, 0.34),

    # Italien
    (r"^serie a$", 1, 0.74),
    (r"^serie b$", 2, 0.54),
    (r"^serie c", 3, 0.41),

    # Frankrike
    (r"^ligue 1$", 1, 0.73),
    (r"^ligue 2$", 2, 0.52),
    (r"^national 1$", 3, 0.40),

    # Portugal & Nederländerna
    (r"primeira liga", 1, 0.66),
    (r"liga portugal 2", 2, 0.45),
    (r"eredivisie", 1, 0.65),
    (r"eerste divisie", 2, 0.44),

    # Skandinavien & Skottland
    (r"allsvenskan", 1, 0.56),
    (r"superettan", 2, 0.44),
    (r"ettan", 3, 0.36),
    (r"premiership$", 1, 0.58),
    (r"championship.*scotland", 2, 0.40),

    # Övriga förstadivisioner
    (r"superliga|pro league|bundesliga.*austria|ekstraklasa|super lig", 1, 0.58),
    (r"major league soccer|saudi pro league|serie a.*brazil|primera divisi[oó]n.*argentina", 1, 0.62),
]


def resolve_league_tier_baseline(league_id: Optional[int], league_name: Optional[str]) -> float:
    if league_id == 8:
        return 0.76
    if not league_name:
        return 0.38
    
    lname = league_name.lower().strip()
    for pattern, _, baseline in PYRAMID_RULES:
        if re.search(pattern, lname):
            return baseline
            
    # Heuristik baserad på ord
    if any(k in lname for k in ["premier", "super", "division 1", "first division", "serie a", "bundesliga", "ligue 1", "eredivisie"]):
        return 0.54
    if any(k in lname for k in ["championship", "division 2", "second division", "2.", "serie b", "ligue 2"]):
        return 0.44
    if any(k in lname for k in ["division 3", "3.", "serie c", "league one"]):
        return 0.36
    if any(k in lname for k in ["division 4", "4.", "league two", "regionalliga"]):
        return 0.30

    return 0.35


# =============================================================================
# RATING REHYDRATOR KLASS
# =============================================================================
class RatingRehydrator:
    def __init__(self, primary_db: Path, secondary_db: Optional[Path], eafc_path: Path, fm23_path: Path):
        self.primary_db = primary_db
        self.secondary_db = secondary_db
        self.eafc_path = eafc_path
        self.fm23_path = fm23_path

        print("==========================================================")
        print("POWERFOOTBALL-2D RATINGS REHYDRATION ENGINE V2")
        print("==========================================================")
        print(f"  * Mål-databas (Primary)   : {self.primary_db.resolve()}")
        if self.secondary_db:
            print(f"  * Spegel-databas (Secondary): {self.secondary_db.resolve()}")
        print(f"  * EA FC 26 Dataset        : {self.eafc_path.resolve()}")
        print(f"  * FM23 Dataset            : {self.fm23_path.resolve()}\n")

        self.conn_master = sqlite3.connect(self.primary_db)
        self.cur_master = self.conn_master.cursor()
        self._ensure_schema()

        # Läs in EAFC26
        self.eafc_candidates, self.eafc_by_team, self.eafc_by_year = self._load_eafc()

        # Läs in FM23
        self.fm_candidates, self.fm_by_team, self.fm_by_year = self._load_fm23()

    def _ensure_schema(self) -> None:
        """Säkerställer att kolumnen rating_source finns i players."""
        try:
            self.cur_master.execute("ALTER TABLE players ADD COLUMN rating_source TEXT DEFAULT 'UNSET'")
            print("Lade till 'rating_source' i players.")
        except sqlite3.OperationalError:
            pass
        self.conn_master.commit()

    @staticmethod
    def _pick_best_candidate(candidates: List[Dict[str, Any]], target_team: Optional[str], target_byear: Optional[int]) -> Dict[str, Any]:
        """Väljer rätt kandidat baserat på klubb, födelseår och övergripande kvalitet."""
        if not candidates:
            return {}
        if len(candidates) == 1:
            return candidates[0]["stats"]

        # 1. Försök matcha med klubb
        if target_team:
            team_matches = [c for c in candidates if teams_match(target_team, c["team"])]
            if len(team_matches) == 1:
                return team_matches[0]["stats"]
            if len(team_matches) > 1:
                candidates = team_matches

        # 2. Försök matcha med födelseår (±1 år)
        if target_byear:
            year_matches = [c for c in candidates if c["byear"] and abs(c["byear"] - target_byear) <= 1]
            if len(year_matches) == 1:
                return year_matches[0]["stats"]
            if len(year_matches) > 1:
                candidates = year_matches

        # 3. Om flera återstår, välj den med högst OVR/kvalitet
        candidates.sort(key=lambda x: x.get("ovr", 0.0), reverse=True)
        return candidates[0]["stats"]

    def _load_eafc(self) -> Tuple[Dict[str, List[Dict[str, Any]]], Dict[Tuple[str, str], List[Dict[str, Any]]], Dict[Tuple[str, int], List[Dict[str, Any]]]]:
        print("1. Läser in EA Sports FC 26 (EAFC26-Men.csv)...")
        candidates_map: Dict[str, List[Dict[str, Any]]] = {}
        by_team: Dict[Tuple[str, str], List[Dict[str, Any]]] = {}
        by_year: Dict[Tuple[str, int], List[Dict[str, Any]]] = {}

        if not self.eafc_path.exists():
            print(f"  [VARNING] {self.eafc_path} hittades inte!")
            return candidates_map, by_team, by_year

        df = pd.read_csv(self.eafc_path, low_memory=False)
        total_rows = len(df)

        for _, r in df.iterrows():
            name = str(r.get("Name", "")).strip()
            if not name or name.lower() == "nan":
                continue

            norm = normalize_name(name)
            raw_team = str(r.get("Team", ""))
            team_norm = normalize_team(raw_team)
            ovr = float(r.get("OVR", 65.0)) if not pd.isna(r.get("OVR")) else 65.0
            pos = str(r.get("Position", "")).upper().strip()
            is_gk = "GK" in pos

            # Fysiska attribut
            weight_kg = parse_weight(r.get("Weight"), default=85.0 if is_gk else 75.0)
            height_cm = parse_height(r.get("Height"), default=188 if is_gk else 180)
            sprint = float(r.get("Sprint Speed", r.get("PAC", 65.0))) if not pd.isna(r.get("Sprint Speed", r.get("PAC"))) else 65.0
            stamina = float(r.get("Stamina", 65.0)) if not pd.isna(r.get("Stamina")) else 65.0

            # Skalning till spelmotorns fysik och intervall
            if is_gk:
                top_speed = min(200.0, max(175.0, 175.0 + (sprint / 100.0) * 25.0))
                # GK distribution / vision
                gk_kick = r.get("GK Kicking")
                vis_val = float(gk_kick) if not pd.isna(gk_kick) else (ovr * 0.85)
                vision = clamp_stat(vis_val / 100.0, 0.45, 0.95)

                # GK composure & positioning
                gk_pos = r.get("GK Positioning")
                pos_val = float(gk_pos) if not pd.isna(gk_pos) else 65.0
                cmp_val = float(r.get("Composure", 65.0)) if not pd.isna(r.get("Composure")) else 65.0
                composure = clamp_stat(max(cmp_val, pos_val) / 100.0, 0.55, 0.98)

                # GK reflexes & diving
                gk_ref = r.get("GK Reflexes")
                if pd.isna(gk_ref):
                    gk_ref = r.get("GK Diving", max(float(r.get("Reactions", 60.0)), ovr))
                reflexes = clamp_stat(float(gk_ref) / 100.0, 0.55, 0.98)

                bc = float(r.get("Ball Control", 50.0)) if not pd.isna(r.get("Ball Control")) else 50.0
                close_ctrl = clamp_stat(max(bc, 40.0) / 100.0, 0.35, 0.70)
                agg = float(r.get("Aggression", 50.0)) if not pd.isna(r.get("Aggression")) else 50.0
                aggression = clamp_stat(agg / 100.0)
                determination = clamp_stat((composure * 0.5 + (stamina / 100.0) * 0.5), 0.40, 0.98)
                work_rate = clamp_stat((composure * 0.5 + aggression * 0.5), 0.40, 0.98)
            else:
                top_speed = min(255.0, max(180.0, 180.0 + (sprint / 100.0) * 72.0))
                vis = float(r.get("Vision", 60.0)) if not pd.isna(r.get("Vision")) else 60.0
                cmp = float(r.get("Composure", 60.0)) if not pd.isna(r.get("Composure")) else 60.0
                agg = float(r.get("Aggression", 60.0)) if not pd.isna(r.get("Aggression")) else 60.0
                react = float(r.get("Reactions", 60.0)) if not pd.isna(r.get("Reactions")) else 60.0

                bc = float(r.get("Ball Control", 60.0)) if not pd.isna(r.get("Ball Control")) else 60.0
                dri = float(r.get("Dribbling", 60.0)) if not pd.isna(r.get("Dribbling")) else 60.0
                close_ctrl = clamp_stat((bc * 0.6 + dri * 0.4) / 100.0)

                vision = clamp_stat(vis / 100.0)
                composure = clamp_stat(cmp / 100.0)
                aggression = clamp_stat(agg / 100.0)
                reflexes = clamp_stat(0.35 + (react / 100.0) * 0.25, 0.35, 0.65)
                determination = clamp_stat((react * 0.35 + cmp * 0.35 + stamina * 0.30) / 100.0, 0.35, 0.99)
                work_rate = clamp_stat((stamina * 0.60 + agg * 0.40) / 100.0, 0.35, 0.99)

            stamina_max = min(100.0, max(70.0, 70.0 + (stamina / 100.0) * 30.0))

            stats = {
                "mass": weight_kg,
                "height_cm": height_cm,
                "top_speed": round(top_speed, 1),
                "stamina_max": round(stamina_max, 1),
                "vision": vision,
                "composure": composure,
                "aggression": aggression,
                "close_control": close_ctrl,
                "reflexes": reflexes,
                "determination": determination,
                "work_rate": work_rate,
                "ovr": ovr,
                "is_gk": is_gk
            }

            byear = parse_birth_year(r.get("DOB"), r.get("Age"), ref_year=2025)
            cand_entry = {
                "stats": stats,
                "team": team_norm,
                "byear": byear,
                "ovr": ovr
            }

            if norm not in candidates_map:
                candidates_map[norm] = []
            candidates_map[norm].append(cand_entry)

            tokens = norm.split()
            last_tok = tokens[-1] if tokens else ""

            if team_norm and last_tok:
                key_team = (team_norm, last_tok)
                if key_team not in by_team:
                    by_team[key_team] = []
                by_team[key_team].append(cand_entry)

            if byear and last_tok:
                for dy in [0, -1, 1]:
                    key_yr = (last_tok, byear + dy)
                    if key_yr not in by_year:
                        by_year[key_yr] = []
                    by_year[key_yr].append(cand_entry)

        print(f"  -> Laddade {len(candidates_map)} unika EAFC-namn från {total_rows} rader.\n")
        return candidates_map, by_team, by_year

    def _load_fm23(self) -> Tuple[Dict[str, List[Dict[str, Any]]], Dict[Tuple[str, str], List[Dict[str, Any]]], Dict[Tuple[str, int], List[Dict[str, Any]]]]:
        print("2. Läser in Football Manager 2023 (FM23.csv)...")
        candidates_map: Dict[str, List[Dict[str, Any]]] = {}
        by_team: Dict[Tuple[str, str], List[Dict[str, Any]]] = {}
        by_year: Dict[Tuple[str, int], List[Dict[str, Any]]] = {}

        if not self.fm23_path.exists():
            print(f"  [VARNING] {self.fm23_path} hittades inte!")
            return candidates_map, by_team, by_year

        use_cols = [
            "Name", "DOB", "Age", "Club", "Position", "Height", "Weight",
            "Pac", "Acc", "Sta", "Str", "Vis", "Cmp", "Agg", "Tec", "Fir",
            "Dri", "Ref", "Det", "Wor", "Ant", "Kic", "Cmd", "Pos"
        ]
        df = pd.read_csv(self.fm23_path, usecols=lambda c: c in use_cols, low_memory=False)
        total_rows = len(df)

        for _, r in df.iterrows():
            name = str(r.get("Name", "")).strip()
            if not name or name.lower() == "nan":
                continue

            norm = normalize_name(name)
            raw_team = str(r.get("Club", ""))
            team_norm = normalize_team(raw_team)
            pos = str(r.get("Position", "")).upper().strip()
            is_gk = "GK" in pos

            def fm_val(col: str, def_val: float = 10.0) -> float:
                v = r.get(col)
                try:
                    val = float(v)
                    return val if not math.isnan(val) else def_val
                except (ValueError, TypeError):
                    return def_val

            pac = fm_val("Pac")
            acc = fm_val("Acc")
            sta = fm_val("Sta")
            vis = fm_val("Vis")
            cmp = fm_val("Cmp")
            agg = fm_val("Agg")
            tec = fm_val("Tec")
            fir = fm_val("Fir")
            dri = fm_val("Dri")
            ref = fm_val("Ref")
            det = fm_val("Det")
            wor = fm_val("Wor")
            ant = fm_val("Ant")
            kic = fm_val("Kic")
            cmd = fm_val("Cmd")
            pos_stat = fm_val("Pos")

            weight_kg = parse_weight(r.get("Weight"), default=85.0 if is_gk else 75.0)
            height_cm = parse_height(r.get("Height"), default=188 if is_gk else 180)

            # Skalning till spelmotorns fysik och intervall
            pace_val = (pac * 0.7 + acc * 0.3) / 20.0
            if is_gk:
                top_speed = min(200.0, max(175.0, 175.0 + (pac / 20.0) * 25.0))
                reflexes = clamp_stat(ref / 20.0, 0.55, 0.98)
                vision = clamp_stat(max(vis, kic) / 20.0, 0.45, 0.95)
                composure = clamp_stat(max(cmp, cmd, pos_stat) / 20.0, 0.55, 0.98)
                close_ctrl = clamp_stat(tec / 20.0, 0.35, 0.70)
            else:
                top_speed = min(252.0, max(180.0, 180.0 + pace_val * 70.0))
                reflexes = clamp_stat(0.35 + (ant / 20.0) * 0.25, 0.35, 0.65)
                vision = clamp_stat(vis / 20.0)
                composure = clamp_stat(cmp / 20.0)
                close_ctrl = clamp_stat((tec * 0.4 + dri * 0.4 + fir * 0.2) / 20.0)

            stamina_max = min(100.0, max(70.0, 70.0 + (sta / 20.0) * 30.0))
            aggression = clamp_stat(agg / 20.0)
            determination = clamp_stat(det / 20.0)
            work_rate = clamp_stat(wor / 20.0)

            # Uppskattad förmåga för sortering vid namndubbletter
            ovr_est = (pac + sta + vis + cmp + tec + ref if is_gk else pac + sta + vis + cmp + tec + wor) * 0.8

            stats = {
                "mass": weight_kg,
                "height_cm": height_cm,
                "top_speed": round(top_speed, 1),
                "stamina_max": round(stamina_max, 1),
                "vision": vision,
                "composure": composure,
                "aggression": aggression,
                "close_control": close_ctrl,
                "reflexes": reflexes,
                "determination": determination,
                "work_rate": work_rate,
                "ovr": ovr_est,
                "is_gk": is_gk
            }

            byear = parse_birth_year(r.get("DOB"), r.get("Age"), ref_year=2022)
            cand_entry = {
                "stats": stats,
                "team": team_norm,
                "byear": byear,
                "ovr": ovr_est
            }

            if norm not in candidates_map:
                candidates_map[norm] = []
            candidates_map[norm].append(cand_entry)

            tokens = norm.split()
            last_tok = tokens[-1] if tokens else ""

            if team_norm and last_tok:
                key_team = (team_norm, last_tok)
                if key_team not in by_team:
                    by_team[key_team] = []
                by_team[key_team].append(cand_entry)

            if byear and last_tok:
                for dy in [0, -1, 1]:
                    key_yr = (last_tok, byear + dy)
                    if key_yr not in by_year:
                        by_year[key_yr] = []
                    by_year[key_yr].append(cand_entry)

        print(f"  -> Laddade {len(candidates_map)} unika FM23-namn från {total_rows} rader.\n")
        return candidates_map, by_team, by_year

    def generate_procedural_stats(self, p_id: int, pos: str, baseline: float) -> Dict[str, Any]:
        """Skapar deterministiska, balanserade betyg baserat på roll och ligans divisionsnivå."""
        p = (pos or "CM").upper()
        delta = (((p_id * 37) % 9) - 4) * 0.01
        base = max(0.20, min(0.85, baseline + delta))

        if "GK" in p:
            return {
                "mass": 85.0,
                "top_speed": round(185.0 + base * 10.0, 1),
                "stamina_max": round(75.0 + base * 15.0, 1),
                "vision": clamp_stat(base * 0.75),
                "composure": clamp_stat(base * 0.95),
                "aggression": clamp_stat(base * 0.75),
                "close_control": clamp_stat(base * 0.50),
                "reflexes": clamp_stat(max(base * 1.30, 0.70)),
                "determination": clamp_stat(base * 1.00),
                "work_rate": clamp_stat(base * 0.90)
            }
        elif any(cb in p for cb in ["CB", "LB", "RB", "DEF"]):
            return {
                "mass": 80.0,
                "top_speed": round(210.0 + (base * 25.0), 1),
                "stamina_max": round(78.0 + (base * 18.0), 1),
                "vision": clamp_stat(base * 0.85),
                "composure": clamp_stat(base * 0.95),
                "aggression": clamp_stat(min(base * 1.20, 0.95)),
                "close_control": clamp_stat(base * 0.80),
                "reflexes": 0.45,
                "determination": clamp_stat(base * 1.05),
                "work_rate": clamp_stat(base * 1.05)
            }
        elif any(st in p for st in ["ST", "CF", "FWD", "ATT", "LW", "RW"]):
            return {
                "mass": 76.0,
                "top_speed": round(218.0 + (base * 28.0), 1),
                "stamina_max": round(78.0 + (base * 18.0), 1),
                "vision": clamp_stat(base * 0.90),
                "composure": clamp_stat(min(base * 1.15, 0.95)),
                "aggression": clamp_stat(base * 0.90),
                "close_control": clamp_stat(min(base * 1.15, 0.95)),
                "reflexes": 0.42,
                "determination": clamp_stat(base * 1.05),
                "work_rate": clamp_stat(base * 0.95)
            }
        else:  # Mittfältare
            return {
                "mass": 74.0,
                "top_speed": round(212.0 + (base * 22.0), 1),
                "stamina_max": round(80.0 + (base * 20.0), 1),
                "vision": clamp_stat(min(base * 1.15, 0.95)),
                "composure": clamp_stat(base * 1.05),
                "aggression": clamp_stat(base * 0.95),
                "close_control": clamp_stat(min(base * 1.10, 0.95)),
                "reflexes": 0.45,
                "determination": clamp_stat(base * 1.00),
                "work_rate": clamp_stat(min(base * 1.15, 0.95))
            }

    def run(self, batch_size: int = 5000) -> None:
        t0 = time.time()
        print("==========================================================")
        print("STARTAR MULTI-STAGE MATCHNING & HYDRERING AV BETYG")
        print("==========================================================")

        self.cur_master.execute("""
            SELECT p.player_id, p.player_name, p.first_name, p.last_name, 
                   p.position_role, p.nationality, p.date_of_birth, p.height_cm, p.weight_kg,
                   t.name AS team_name, l.name AS league_name, l.league_id
            FROM players p
            LEFT JOIN contracts c ON p.player_id = c.player_id
            LEFT JOIN teams t ON c.team_id = t.team_id
            LEFT JOIN leagues l ON t.league_id = l.league_id
            GROUP BY p.player_id;
        """)
        all_players = self.cur_master.fetchall()
        total_players = len(all_players)
        print(f"Hämtade {total_players:,} spelare från master-databasen på {time.time() - t0:.2f}s.\n")

        batch_updates: List[Tuple] = []
        counts = {"EAFC": 0, "FM23": 0, "PROCEDURAL": 0}

        for idx, row in enumerate(all_players, 1):
            (
                p_id, p_name, f_name, l_name, pos, nat, dob,
                curr_h, curr_w, t_name, l_name_str, l_id
            ) = row

            p_norm = normalize_name(p_name)
            fn = normalize_name(f_name)
            ln = normalize_name(l_name)
            fl_norm = f"{fn} {ln}".strip() if (fn and ln) else ""
            t_norm = normalize_team(t_name)
            byear = parse_birth_year(dob)
            tokens = ln.split() if ln else p_norm.split()
            last_tok = tokens[-1] if tokens else ""

            stats: Optional[Dict[str, Any]] = None
            source = "PROCEDURAL"

            # -------------------------------------------------------------
            # STAGE 1: EA SPORTS FC 26 (EAFC26-Men.csv)
            # -------------------------------------------------------------
            if p_norm in self.eafc_candidates:
                stats = self._pick_best_candidate(self.eafc_candidates[p_norm], t_name, byear)
                source = "EAFC"
            elif fl_norm and fl_norm in self.eafc_candidates:
                stats = self._pick_best_candidate(self.eafc_candidates[fl_norm], t_name, byear)
                source = "EAFC"
            elif t_norm and last_tok and (t_norm, last_tok) in self.eafc_by_team:
                stats = self._pick_best_candidate(self.eafc_by_team[(t_norm, last_tok)], t_name, byear)
                source = "EAFC"
            elif byear and last_tok and (last_tok, byear) in self.eafc_by_year:
                stats = self._pick_best_candidate(self.eafc_by_year[(last_tok, byear)], t_name, byear)
                source = "EAFC"

            # Om EAFC hittades, berika mental stats från FM23 om tillgängligt
            if stats and source == "EAFC":
                fm_supp = None
                if p_norm in self.fm_candidates:
                    fm_supp = self._pick_best_candidate(self.fm_candidates[p_norm], t_name, byear)
                elif fl_norm and fl_norm in self.fm_candidates:
                    fm_supp = self._pick_best_candidate(self.fm_candidates[fl_norm], t_name, byear)
                elif t_norm and last_tok and (t_norm, last_tok) in self.fm_by_team:
                    fm_supp = self._pick_best_candidate(self.fm_by_team[(t_norm, last_tok)], t_name, byear)

                if fm_supp:
                    stats["determination"] = fm_supp["determination"]
                    stats["work_rate"] = fm_supp["work_rate"]

            # -------------------------------------------------------------
            # STAGE 2: FOOTBALL MANAGER 2023 (FM23.csv)
            # -------------------------------------------------------------
            if not stats:
                if p_norm in self.fm_candidates:
                    stats = self._pick_best_candidate(self.fm_candidates[p_norm], t_name, byear)
                    source = "FM23"
                elif fl_norm and fl_norm in self.fm_candidates:
                    stats = self._pick_best_candidate(self.fm_candidates[fl_norm], t_name, byear)
                    source = "FM23"
                elif t_norm and last_tok and (t_norm, last_tok) in self.fm_by_team:
                    stats = self._pick_best_candidate(self.fm_by_team[(t_norm, last_tok)], t_name, byear)
                    source = "FM23"
                elif byear and last_tok and (last_tok, byear) in self.fm_by_year:
                    stats = self._pick_best_candidate(self.fm_by_year[(last_tok, byear)], t_name, byear)
                    source = "FM23"

            # -------------------------------------------------------------
            # STAGE 3: KALIBRERAD PROCEDURAL PYRAMID FALLBACK
            # -------------------------------------------------------------
            if not stats:
                baseline = resolve_league_tier_baseline(l_id, l_name_str)
                stats = self.generate_procedural_stats(p_id, pos, baseline)
                source = "PROCEDURAL"

            counts[source] += 1

            final_mass = float(stats.get("mass", 75.0))
            if final_mass <= 0:
                final_mass = float(curr_w) if (curr_w and curr_w > 0) else 75.0

            batch_updates.append((
                final_mass,
                stats["top_speed"],
                stats["stamina_max"],
                stats["vision"],
                stats["composure"],
                stats["aggression"],
                stats["close_control"],
                stats["reflexes"],
                stats["determination"],
                stats["work_rate"],
                source,
                p_id
            ))

            if len(batch_updates) >= batch_size:
                self.cur_master.executemany("""
                    UPDATE players
                    SET mass = ?, top_speed = ?, stamina_max = ?,
                        vision = ?, composure = ?, aggression = ?,
                        close_control = ?, reflexes = ?, determination = ?,
                        work_rate = ?, rating_source = ?
                    WHERE player_id = ?;
                """, batch_updates)
                self.conn_master.commit()
                batch_updates.clear()
                print(f"  -> Bearbetat {idx:,} / {total_players:,} spelare...")

        if batch_updates:
            self.cur_master.executemany("""
                UPDATE players
                SET mass = ?, top_speed = ?, stamina_max = ?,
                    vision = ?, composure = ?, aggression = ?,
                    close_control = ?, reflexes = ?, determination = ?,
                    work_rate = ?, rating_source = ?
                WHERE player_id = ?;
            """, batch_updates)
            self.conn_master.commit()

        print("\nUtför optimering och verifiering...")
        self.cur_master.execute("PRAGMA integrity_check;")
        res = self.cur_master.fetchone()
        assert res and res[0] == "ok", f"Integrity check failed: {res}"
        self.conn_master.commit()
        self.conn_master.close()

        # Spegla till sekundär databas om konfigurerad
        if self.secondary_db:
            print(f"Speglar uppdaterad databas till: {self.secondary_db.resolve()}...")
            import shutil
            self.secondary_db.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.primary_db, self.secondary_db)
            print("  [OK] Spegling slutförd.")

        elapsed = time.time() - t0
        print("\n==========================================================")
        print("KALIBRERING & HYDRERING SLUTFÖRD!")
        print(f"  * Totalt behandlade     : {total_players:,} spelare")
        print(f"  * EA Sports FC 26-betyg : {counts['EAFC']:,} spelare ({counts['EAFC']/total_players*100:.1f}%)")
        print(f"  * FM23-betyg            : {counts['FM23']:,} spelare ({counts['FM23']/total_players*100:.1f}%)")
        print(f"  * Procedurala betyg     : {counts['PROCEDURAL']:,} spelare ({counts['PROCEDURAL']/total_players*100:.1f}%)")
        print(f"  * Tidsåtgång            : {elapsed:.2f} sekunder")
        print("==========================================================")


def main():
    try:
        from rehydrate_ratings_v3 import RatingRehydratorV3, resolve_paths as resolve_paths_v3
        parser = argparse.ArgumentParser(description="Rehydrate PowerFootball-2D player ratings (v2 compatibility alias to v3).")
        parser.add_argument("--db-path", default=None, help="Explicit path to target SQLite database")
        parser.add_argument("--no-sync", action="store_true", help="Do not mirror primary DB to secondary copy")
        parser.add_argument("--online", action="store_true", help="Enable online scraping/API enricher")
        parser.add_argument("--batch-size", type=int, default=5000, help="Batch size for database updates")
        args = parser.parse_args()

        primary_db, secondary_db, eafc_csv, fm23_csv = resolve_paths_v3(args.db_path)
        if args.no_sync:
            secondary_db = None

        rehydrator = RatingRehydratorV3(primary_db, secondary_db, eafc_csv, fm23_csv, enable_online=args.online)
        rehydrator.run(batch_size=args.batch_size)
    except ImportError:
        parser = argparse.ArgumentParser(description="Rehydrate PowerFootball-2D player ratings from EAFC26 & FM23.")
        parser.add_argument("--db-path", default=None, help="Explicit path to target SQLite database")
        parser.add_argument("--no-sync", action="store_true", help="Do not mirror primary DB to secondary copy")
        parser.add_argument("--batch-size", type=int, default=5000, help="Batch size for database updates")
        args = parser.parse_args()

        primary_db, secondary_db, eafc_csv, fm23_csv = resolve_paths(args.db_path)
        if args.no_sync:
            secondary_db = None

        rehydrator = RatingRehydrator(primary_db, secondary_db, eafc_csv, fm23_csv)
        rehydrator.run(batch_size=args.batch_size)


if __name__ == "__main__":
    main()