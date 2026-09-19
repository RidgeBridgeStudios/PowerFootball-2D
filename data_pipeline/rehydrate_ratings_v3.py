#!/usr/bin/env python3
"""
data_pipeline/rehydrate_ratings_v3.py

Robust, realistic player rating rehydration engine for PowerFootball-2D:
  1. EA Sports FC 26 (EAFC26-Men.csv) with strict disambiguation (no loose surname collisions)
  2. Football Manager 2023 (FM23.csv) with multi-token cross-validation and tier ceiling guards
  3. Live scraping / API hooks (Sportmonks v3, TheSportsDB, web cache)
  4. Conservative, tier-anchored mathematical model for obscure players based on
     team reputation, stature, position archetypes, and age curves.
"""

import argparse
import json
import math
import os
import re
import shutil
import sqlite3
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import pandas as pd

# =============================================================================
# SÖKVÄGAR & INITIALISERING
# =============================================================================
def resolve_paths(custom_db_path: Optional[str] = None) -> Tuple[Path, Optional[Path], Path, Path]:
    script_dir = Path(__file__).resolve().parent
    repo_dir = script_dir.parent if (script_dir.parent / "data").exists() else script_dir

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
    "bvb": "borussia dortmund",
    "leverkusen": "bayer 04 leverkusen",
    "bayer leverkusen": "bayer 04 leverkusen",
    "atletico madrid": "atletico de madrid",
    "atletico": "atletico de madrid",
    "real madrid": "real madrid",
    "barcelona": "fc barcelona",
    "barca": "fc barcelona",
    "sporting cp": "sporting",
    "benfica": "sl benfica",
    "porto": "fc porto",
    "juve": "juventus",
    "ajax": "afc ajax",
    "psv": "psv eindhoven",
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
    t = re.sub(r"\b(fc|afc|cf|sc|ac|as|ss|rc|cd|ud|sv|vfb|bsc|fk|sk|ogc|rb|us|club|de|la)\b", "", t)
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
    words_a = {w for w in ta.split() if len(w) >= 4}
    words_b = {w for w in tb.split() if len(w) >= 4}
    return bool(words_a and words_b and (words_a & words_b))


def parse_weight(val: Any, default: float = 75.0) -> float:
    if val is None or pd.isna(val):
        return default
    if isinstance(val, (int, float)):
        return float(val) if 45.0 <= float(val) <= 125.0 else default
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
        if 45.0 <= v <= 125.0:
            return v
    return default


def parse_height(val: Any, default: int = 180) -> int:
    if val is None or pd.isna(val):
        return default
    if isinstance(val, (int, float)):
        v = int(val)
        return v if 150 <= v <= 215 else default
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
        if 150 <= v <= 215:
            return v
    return default


def parse_birth_year(dob: Any, age: Any = None, ref_year: int = 2026) -> Optional[int]:
    if dob and isinstance(dob, str) and not pd.isna(dob):
        m = re.search(r"(\d{4})", dob)
        if m:
            y = int(m.group(1))
            if 1965 <= y <= 2015:
                return y
    if age and not pd.isna(age):
        try:
            a = int(float(age))
            if 15 <= a <= 55:
                return ref_year - a
        except (ValueError, TypeError):
            pass
    return None


def clamp_stat(val: float, low: float = 0.08, high: float = 0.99) -> float:
    return max(low, min(high, round(val, 3)))


# =============================================================================
# SPORTMONKS & ONLINE SCRAPER CLIENT
# =============================================================================
class OnlineFootballDataFetcher:
    """Online data enricher using Sportmonks API v3 and TheSportsDB."""

    SPORTMONKS_TOKEN = os.environ.get(
        "SPORTMONKS_API_TOKEN", "WF5neL4jRErhZvad8hJpq3a9MNS2hk9jgkU6b8wCFqbOh8EnXHFdCqzMYEdT"
    )
    SPORTMONKS_BASE = "https://api.sportmonks.com/v3/football"
    THESPORTSDB_BASE = "https://www.thesportsdb.com/api/v1/json/3"

    def __init__(self, cache_db: Optional[Path] = None):
        self.cache_db = cache_db
        if self.cache_db:
            self._init_cache()

    def _init_cache(self) -> None:
        try:
            with sqlite3.connect(self.cache_db) as conn:
                conn.execute("""
                    CREATE TABLE IF NOT EXISTS api_cache (
                        endpoint TEXT PRIMARY KEY,
                        payload TEXT,
                        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
                    )
                """)
        except Exception:
            pass

    def fetch_sportmonks_player_stats(self, player_id: int) -> Optional[Dict[str, Any]]:
        url = f"{self.SPORTMONKS_BASE}/players/{player_id}?include=statistics.details"
        req = urllib.request.Request(
            url,
            headers={
                "Authorization": self.SPORTMONKS_TOKEN,
                "Accept": "application/json",
                "User-Agent": "PowerFootball-2D/1.0"
            }
        )
        try:
            with urllib.request.urlopen(req, timeout=4.0) as res:
                if res.status == 200:
                    data = json.loads(res.read().decode("utf-8"))
                    return data.get("data")
        except Exception:
            return None
        return None

    @staticmethod
    def apply_stat_adjustments(stats: Dict[str, Any], player_stats_payload: Dict[str, Any]) -> Dict[str, Any]:
        """Translates real-world season statistics into attribute calibrations."""
        if not player_stats_payload:
            return stats
        raw_stats = player_stats_payload.get("statistics", [])
        if not raw_stats:
            return stats

        goals = 0
        assists = 0
        appearances = 0
        for s in raw_stats:
            for d in s.get("details", []):
                t_id = d.get("type_id")
                val = d.get("value", {}).get("total", 0) if isinstance(d.get("value"), dict) else d.get("value", 0)
                try:
                    ival = int(val)
                except (ValueError, TypeError):
                    ival = 0
                if t_id == 52:  # Goals
                    goals += ival
                elif t_id == 79:  # Assists
                    assists += ival
                elif t_id == 321:  # Appearances
                    appearances += ival

        if appearances >= 10:
            gpg = goals / appearances
            apg = assists / appearances
            if gpg > 0.40:
                stats["composure"] = clamp_stat(stats["composure"] + 0.05)
                stats["close_control"] = clamp_stat(stats["close_control"] + 0.04)
            if apg > 0.25:
                stats["vision"] = clamp_stat(stats["vision"] + 0.06)

        return stats


# =============================================================================
# REHYDRATION ENGINE V3
# =============================================================================
class RatingRehydratorV3:
    def __init__(
        self,
        primary_db: Path,
        secondary_db: Optional[Path],
        eafc_path: Path,
        fm23_path: Path,
        enable_online: bool = False
    ):
        self.primary_db = primary_db
        self.secondary_db = secondary_db
        self.eafc_path = eafc_path
        self.fm23_path = fm23_path
        self.enable_online = enable_online

        print("==========================================================")
        print("POWERFOOTBALL-2D RATINGS REHYDRATION ENGINE V3")
        print("==========================================================")
        print(f"  * Primary Target DB : {self.primary_db.resolve()}")
        if self.secondary_db:
            print(f"  * Secondary Mirror  : {self.secondary_db.resolve()}")
        print(f"  * EA FC 26 Dataset  : {self.eafc_path.resolve()}")
        print(f"  * FM23 Dataset      : {self.fm23_path.resolve()}")
        print(f"  * Online Enricher   : {'ENABLED' if self.enable_online else 'DISABLED (Offline)'}\n")

        self.conn = sqlite3.connect(self.primary_db)
        self.cur = self.conn.cursor()
        self._ensure_schema()

        self.online_fetcher = OnlineFootballDataFetcher() if self.enable_online else None

        # Läs in och indexera dataseten
        self.eafc_by_name, self.eafc_by_fl, self.eafc_by_team_last, self.eafc_by_init_last_yr = self._load_eafc()
        self.fm_by_name, self.fm_by_fl, self.fm_by_team_last, self.fm_by_init_last_yr = self._load_fm23()

    def _ensure_schema(self) -> None:
        try:
            self.cur.execute("ALTER TABLE players ADD COLUMN rating_source TEXT DEFAULT 'UNSET'")
        except sqlite3.OperationalError:
            pass
        self.conn.commit()

    @staticmethod
    def _disambiguate_candidate(
        candidates: List[Dict[str, Any]],
        target_team: Optional[str],
        target_byear: Optional[int],
        target_pos: Optional[str],
        team_rep: float
    ) -> Optional[Dict[str, Any]]:
        """
        Väljer rätt spelarkandidat med strikta kvalitets- och sammanhangskontroller.
        Förhindrar att division 6-spelare tilldelas 85+ OVR stjärnor på grund av samma efternamn.
        """
        if not candidates:
            return None

        # Filtrera bort felaktig position (GK vs utespelare är absolut skild)
        is_target_gk = "GK" in (target_pos or "").upper()
        pos_filtered = [c for c in candidates if c["stats"]["is_gk"] == is_target_gk]
        if pos_filtered:
            candidates = pos_filtered

        # 1. Klubbmatchning (starkaste signalen)
        if target_team:
            team_matches = [c for c in candidates if teams_match(target_team, c["team"])]
            if len(team_matches) == 1:
                return team_matches[0]["stats"]
            if len(team_matches) > 1:
                candidates = team_matches

        # 2. Födelseårsmatchning (+- 1 år)
        if target_byear:
            year_matches = [c for c in candidates if c["byear"] and abs(c["byear"] - target_byear) <= 1]
            if len(year_matches) == 1:
                cand = year_matches[0]
                cand_ovr = cand.get("ovr", 60.0)
                is_tm = teams_match(target_team or "", cand["team"])
                # Cross-tier sanity guards om klubben inte matchade:
                if not is_tm:
                    if team_rep < 0.20 and cand_ovr > 62.0:
                        return None
                    elif team_rep < 0.35 and cand_ovr > 68.0:
                        return None
                    elif team_rep < 0.50 and cand_ovr > 74.0:
                        return None
                    elif team_rep < 0.68 and cand_ovr > 80.0:
                        return None
                return cand["stats"]
            if len(year_matches) > 1:
                candidates = year_matches

        # 3. Om flera återstår och ingen klubb matchade:
        # Välj kandidat vars OVR är närmast klubbens förväntade nivå, INTE den högsta OVR!
        expected_ovr = 46.0 + team_rep * 40.0
        candidates.sort(key=lambda c: abs(c.get("ovr", 60.0) - expected_ovr))
        best = candidates[0]
        best_ovr = best.get("ovr", 60.0)
        is_tm = teams_match(target_team or "", best["team"])

        if not is_tm:
            if team_rep < 0.20 and best_ovr > 62.0:
                return None
            elif team_rep < 0.35 and best_ovr > 68.0:
                return None
            elif team_rep < 0.50 and best_ovr > 74.0:
                return None
            elif team_rep < 0.68 and best_ovr > 80.0:
                return None

        return best["stats"]

    def _load_eafc(self):
        print("1. Indexerar EA Sports FC 26 (EAFC26-Men.csv)...")
        by_name: Dict[str, List[Dict[str, Any]]] = {}
        by_fl: Dict[str, List[Dict[str, Any]]] = {}
        by_team_last: Dict[Tuple[str, str], List[Dict[str, Any]]] = {}
        by_init_last_yr: Dict[Tuple[str, str, int], List[Dict[str, Any]]] = {}

        if not self.eafc_path.exists():
            print(f"  [VARNING] {self.eafc_path} hittades inte!")
            return by_name, by_fl, by_team_last, by_init_last_yr

        df = pd.read_csv(self.eafc_path, low_memory=False)
        total = len(df)

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

            weight_kg = parse_weight(r.get("Weight"), default=85.0 if is_gk else 75.0)
            height_cm = parse_height(r.get("Height"), default=188 if is_gk else 180)
            sprint = float(r.get("Sprint Speed", r.get("PAC", 65.0))) if not pd.isna(r.get("Sprint Speed", r.get("PAC"))) else 65.0
            stamina = float(r.get("Stamina", 65.0)) if not pd.isna(r.get("Stamina")) else 65.0

            if is_gk:
                top_speed = min(198.0, max(172.0, 172.0 + (sprint / 100.0) * 26.0))
                gk_kick = r.get("GK Kicking")
                vis_val = float(gk_kick) if not pd.isna(gk_kick) else (ovr * 0.85)
                vision = clamp_stat(vis_val / 100.0, 0.35, 0.95)

                gk_pos = r.get("GK Positioning")
                pos_val = float(gk_pos) if not pd.isna(gk_pos) else 60.0
                cmp_val = float(r.get("Composure", 60.0)) if not pd.isna(r.get("Composure")) else 60.0
                composure = clamp_stat(max(cmp_val, pos_val) / 100.0, 0.35, 0.98)

                gk_ref = r.get("GK Reflexes")
                if pd.isna(gk_ref):
                    gk_ref = r.get("GK Diving", max(float(r.get("Reactions", 60.0)), ovr))
                reflexes = clamp_stat(float(gk_ref) / 100.0, 0.40, 0.98)

                bc = float(r.get("Ball Control", 50.0)) if not pd.isna(r.get("Ball Control")) else 50.0
                close_ctrl = clamp_stat(max(bc, 30.0) / 100.0, 0.25, 0.70)
                agg = float(r.get("Aggression", 50.0)) if not pd.isna(r.get("Aggression")) else 50.0
                aggression = clamp_stat(agg / 100.0, 0.20, 0.95)
                determination = clamp_stat((composure * 0.5 + (stamina / 100.0) * 0.5), 0.30, 0.98)
                work_rate = clamp_stat((composure * 0.5 + aggression * 0.5), 0.30, 0.98)
            else:
                top_speed = min(255.0, max(175.0, 175.0 + (sprint / 100.0) * 75.0))
                vis = float(r.get("Vision", 55.0)) if not pd.isna(r.get("Vision")) else 55.0
                cmp = float(r.get("Composure", 55.0)) if not pd.isna(r.get("Composure")) else 55.0
                agg = float(r.get("Aggression", 55.0)) if not pd.isna(r.get("Aggression")) else 55.0
                react = float(r.get("Reactions", 55.0)) if not pd.isna(r.get("Reactions")) else 55.0
                bc = float(r.get("Ball Control", 55.0)) if not pd.isna(r.get("Ball Control")) else 55.0
                dri = float(r.get("Dribbling", 55.0)) if not pd.isna(r.get("Dribbling")) else 55.0

                close_ctrl = clamp_stat((bc * 0.6 + dri * 0.4) / 100.0, 0.20, 0.99)
                vision = clamp_stat(vis / 100.0, 0.20, 0.99)
                composure = clamp_stat(cmp / 100.0, 0.20, 0.99)
                aggression = clamp_stat(agg / 100.0, 0.20, 0.99)
                reflexes = clamp_stat(0.30 + (react / 100.0) * 0.30, 0.25, 0.65)
                determination = clamp_stat((react * 0.35 + cmp * 0.35 + stamina * 0.30) / 100.0, 0.25, 0.99)
                work_rate = clamp_stat((stamina * 0.60 + agg * 0.40) / 100.0, 0.25, 0.99)

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

            byear = parse_birth_year(r.get("DOB"), r.get("Age"), ref_year=2026)
            cand = {"stats": stats, "team": team_norm, "byear": byear, "ovr": ovr, "name": name}

            by_name.setdefault(norm, []).append(cand)

            tokens = norm.split()
            if len(tokens) >= 2:
                fl = f"{tokens[0]} {tokens[-1]}"
                by_fl.setdefault(fl, []).append(cand)
                first_init = tokens[0][0]
                last_tok = tokens[-1]
                if team_norm and last_tok:
                    by_team_last.setdefault((team_norm, last_tok), []).append(cand)
                if byear and last_tok and len(last_tok) >= 4:
                    by_init_last_yr.setdefault((first_init, last_tok, byear), []).append(cand)

        print(f"  -> Indexerade {len(by_name)} unika EAFC-namn från {total} rader.\n")
        return by_name, by_fl, by_team_last, by_init_last_yr

    def _load_fm23(self):
        print("2. Indexerar Football Manager 2023 (FM23.csv)...")
        by_name: Dict[str, List[Dict[str, Any]]] = {}
        by_fl: Dict[str, List[Dict[str, Any]]] = {}
        by_team_last: Dict[Tuple[str, str], List[Dict[str, Any]]] = {}
        by_init_last_yr: Dict[Tuple[str, str, int], List[Dict[str, Any]]] = {}

        if not self.fm23_path.exists():
            print(f"  [VARNING] {self.fm23_path} hittades inte!")
            return by_name, by_fl, by_team_last, by_init_last_yr

        use_cols = [
            "Name", "DOB", "Age", "Club", "Position", "Height", "Weight",
            "Pac", "Acc", "Sta", "Str", "Vis", "Cmp", "Agg", "Tec", "Fir",
            "Dri", "Ref", "Det", "Wor", "Ant", "Kic", "Cmd", "Pos", "Dec"
        ]
        df = pd.read_csv(self.fm23_path, usecols=lambda c: c in use_cols, low_memory=False)
        total = len(df)

        for _, r in df.iterrows():
            name = str(r.get("Name", "")).strip()
            if not name or name.lower() == "nan":
                continue

            norm = normalize_name(name)
            raw_team = str(r.get("Club", ""))
            team_norm = normalize_team(raw_team)
            pos = str(r.get("Position", "")).upper().strip()
            is_gk = "GK" in pos

            def fm_val(col: str, def_val: float = 9.0) -> float:
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

            pace_val = (pac * 0.7 + acc * 0.3) / 20.0
            if is_gk:
                top_speed = min(198.0, max(172.0, 172.0 + (pac / 20.0) * 26.0))
                reflexes = clamp_stat(ref / 20.0, 0.35, 0.98)
                vision = clamp_stat(max(vis, kic) / 20.0, 0.30, 0.95)
                composure = clamp_stat(max(cmp, cmd, pos_stat) / 20.0, 0.35, 0.98)
                close_ctrl = clamp_stat(tec / 20.0, 0.20, 0.70)
            else:
                top_speed = min(252.0, max(175.0, 175.0 + pace_val * 72.0))
                reflexes = clamp_stat(0.30 + (ant / 20.0) * 0.25, 0.25, 0.65)
                vision = clamp_stat(vis / 20.0, 0.15, 0.98)
                composure = clamp_stat(cmp / 20.0, 0.15, 0.98)
                close_ctrl = clamp_stat((tec * 0.4 + dri * 0.4 + fir * 0.2) / 20.0, 0.15, 0.98)

            stamina_max = min(100.0, max(70.0, 70.0 + (sta / 20.0) * 30.0))
            aggression = clamp_stat(agg / 20.0, 0.15, 0.98)
            determination = clamp_stat(det / 20.0, 0.15, 0.98)
            work_rate = clamp_stat(wor / 20.0, 0.15, 0.98)

            # FM overall estimate (30-90 scale)
            ovr_est = 35.0 + ((pac + sta + vis + cmp + tec + ref if is_gk else pac + sta + vis + cmp + tec + wor) / 120.0) * 55.0

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

            byear = parse_birth_year(r.get("DOB"), r.get("Age"), ref_year=2023)
            cand = {"stats": stats, "team": team_norm, "byear": byear, "ovr": ovr_est, "name": name}

            by_name.setdefault(norm, []).append(cand)

            tokens = norm.split()
            if len(tokens) >= 2:
                fl = f"{tokens[0]} {tokens[-1]}"
                by_fl.setdefault(fl, []).append(cand)
                first_init = tokens[0][0]
                last_tok = tokens[-1]
                if team_norm and last_tok:
                    by_team_last.setdefault((team_norm, last_tok), []).append(cand)
                if byear and last_tok and len(last_tok) >= 4:
                    by_init_last_yr.setdefault((first_init, last_tok, byear), []).append(cand)

        print(f"  -> Indexerade {len(by_name)} unika FM23-namn från {total} rader.\n")
        return by_name, by_fl, by_team_last, by_init_last_yr

    def generate_conservative_procedural_stats(
        self,
        p_id: int,
        pos: str,
        team_rep: float,
        dob: Optional[str]
    ) -> Dict[str, Any]:
        """
        Konservativ matematisk formel för obskyra/lokala spelare.
        Baserad direkt på klubbens rykte (0.05 till 0.98), ålderskurva och positionsroll.
        Producerar realistiska betyg:
          - Division 6 / regional: 48-52 OVR
          - Division 4 / League Two: 54-58 OVR
          - Division 3 / League One: 60-65 OVR
          - Division 2 / Championship: 67-73 OVR
          - Division 1 toppklubb: 76-84 OVR
        """
        p = (pos or "CM").upper()
        is_gk = "GK" in p

        # 1. Klubb-baslinje B in [0.10, 0.74]
        base = 0.10 + (clamp_stat(team_rep, 0.05, 0.98) * 0.65)

        # 2. Deterministisk pseudo-slumpvariation per spelare (-0.035 till +0.035)
        jitter = (((p_id * 37 + 19) % 21) - 10) * 0.0035
        base = max(0.08, min(0.85, base + jitter))

        # 3. Ålderskurva
        byear = parse_birth_year(dob)
        age = (2026 - byear) if byear else 25
        age_pace_mod = 0.0
        age_mental_mod = 0.0
        if age <= 19:
            base -= 0.04
            age_mental_mod = -0.05
            age_pace_mod = +0.02
        elif 20 <= age <= 22:
            base -= 0.02
            age_mental_mod = -0.02
        elif 30 <= age <= 33:
            age_mental_mod = +0.04
            age_pace_mod = -0.03
        elif age >= 34:
            age_mental_mod = +0.07
            age_pace_mod = -0.07
            base -= 0.02

        # 4. Positions-arketyper
        if is_gk:
            top_spd = 172.0 + (base + age_pace_mod) * 16.0
            stamina = 70.0 + base * 16.0
            return {
                "mass": 86.0,
                "top_speed": round(min(195.0, max(170.0, top_spd)), 1),
                "stamina_max": round(min(92.0, max(70.0, stamina)), 1),
                "vision": clamp_stat(base * 0.70),
                "composure": clamp_stat((base + age_mental_mod) * 0.95),
                "aggression": clamp_stat(base * 0.70),
                "close_control": clamp_stat(base * 0.40),
                "reflexes": clamp_stat(base * 1.25 + 0.10, 0.25, 0.95),
                "determination": clamp_stat((base + age_mental_mod) * 1.00),
                "work_rate": clamp_stat(base * 0.85),
                "is_gk": True
            }
        elif any(cb in p for cb in ["CB", "DEF", "CENTRE BACK"]):
            top_spd = 180.0 + (base + age_pace_mod) * 44.0
            stamina = 74.0 + base * 20.0
            return {
                "mass": 82.0,
                "top_speed": round(min(240.0, max(172.0, top_spd)), 1),
                "stamina_max": round(min(96.0, max(72.0, stamina)), 1),
                "vision": clamp_stat(base * 0.75),
                "composure": clamp_stat((base + age_mental_mod) * 0.90),
                "aggression": clamp_stat(base * 1.20, 0.15, 0.95),
                "close_control": clamp_stat(base * 0.70),
                "reflexes": clamp_stat(0.28 + base * 0.18, 0.20, 0.55),
                "determination": clamp_stat((base + age_mental_mod) * 1.05),
                "work_rate": clamp_stat(base * 1.05),
                "is_gk": False
            }
        elif any(fb in p for fb in ["LB", "RB", "WING BACK", "LWB", "RWB"]):
            top_spd = 188.0 + (base + age_pace_mod) * 52.0
            stamina = 75.0 + base * 22.0
            return {
                "mass": 74.0,
                "top_speed": round(min(248.0, max(175.0, top_spd)), 1),
                "stamina_max": round(min(98.0, max(74.0, stamina)), 1),
                "vision": clamp_stat(base * 0.85),
                "composure": clamp_stat((base + age_mental_mod) * 0.90),
                "aggression": clamp_stat(base * 0.95),
                "close_control": clamp_stat(base * 0.88),
                "reflexes": clamp_stat(0.28 + base * 0.18, 0.20, 0.55),
                "determination": clamp_stat((base + age_mental_mod) * 1.00),
                "work_rate": clamp_stat(base * 1.15),
                "is_gk": False
            }
        elif any(st in p for st in ["ST", "CF", "ATT", "FORWARD"]):
            top_spd = 186.0 + (base + age_pace_mod) * 50.0
            stamina = 74.0 + base * 20.0
            return {
                "mass": 78.0,
                "top_speed": round(min(246.0, max(175.0, top_spd)), 1),
                "stamina_max": round(min(96.0, max(72.0, stamina)), 1),
                "vision": clamp_stat(base * 0.80),
                "composure": clamp_stat((base + age_mental_mod) * 1.10),
                "aggression": clamp_stat(base * 0.90),
                "close_control": clamp_stat(base * 1.10),
                "reflexes": clamp_stat(0.28 + base * 0.18, 0.20, 0.55),
                "determination": clamp_stat((base + age_mental_mod) * 1.05),
                "work_rate": clamp_stat(base * 0.95),
                "is_gk": False
            }
        elif any(w in p for w in ["LW", "RW", "LM", "RM", "WINGER"]):
            top_spd = 190.0 + (base + age_pace_mod) * 56.0
            stamina = 75.0 + base * 20.0
            return {
                "mass": 71.0,
                "top_speed": round(min(252.0, max(178.0, top_spd)), 1),
                "stamina_max": round(min(96.0, max(72.0, stamina)), 1),
                "vision": clamp_stat(base * 0.90),
                "composure": clamp_stat((base + age_mental_mod) * 0.95),
                "aggression": clamp_stat(base * 0.85),
                "close_control": clamp_stat(base * 1.15),
                "reflexes": clamp_stat(0.28 + base * 0.18, 0.20, 0.55),
                "determination": clamp_stat((base + age_mental_mod) * 0.95),
                "work_rate": clamp_stat(base * 1.00),
                "is_gk": False
            }
        else:  # CM / DM / AM
            top_spd = 184.0 + (base + age_pace_mod) * 46.0
            stamina = 75.0 + base * 22.0
            return {
                "mass": 74.0,
                "top_speed": round(min(242.0, max(174.0, top_spd)), 1),
                "stamina_max": round(min(98.0, max(74.0, stamina)), 1),
                "vision": clamp_stat(base * 1.10),
                "composure": clamp_stat((base + age_mental_mod) * 1.05),
                "aggression": clamp_stat(base * 0.95),
                "close_control": clamp_stat(base * 1.05),
                "reflexes": clamp_stat(0.28 + base * 0.18, 0.20, 0.55),
                "determination": clamp_stat((base + age_mental_mod) * 1.00),
                "work_rate": clamp_stat(base * 1.10),
                "is_gk": False
            }

    def run(self, batch_size: int = 5000, limit: Optional[int] = None) -> None:
        t0 = time.time()
        print("==========================================================")
        print("STARTAR KALIBRERING OCH HYDRERING AV SPELARBETYG V3")
        print("==========================================================")

        query = """
            SELECT p.player_id, p.player_name, p.first_name, p.last_name,
                   p.position_role, p.nationality, p.date_of_birth, p.height_cm, p.weight_kg,
                   t.name AS team_name, t.reputation AS team_rep, l.name AS league_name, l.league_id
            FROM players p
            LEFT JOIN contracts c ON p.player_id = c.player_id
            LEFT JOIN teams t ON c.team_id = t.team_id
            LEFT JOIN leagues l ON t.league_id = l.league_id
            GROUP BY p.player_id
        """
        if limit:
            query += f" LIMIT {int(limit)}"

        self.cur.execute(query)
        all_players = self.cur.fetchall()
        total_players = len(all_players)
        print(f"Laddade {total_players:,} spelare från master-databasen på {time.time() - t0:.2f}s.\n")

        batch_updates: List[Tuple] = []
        counts = {"EAFC": 0, "FM23": 0, "SPORTMONKS": 0, "PROCEDURAL": 0}

        for idx, row in enumerate(all_players, 1):
            (
                p_id, p_name, f_name, l_name, pos, nat, dob,
                curr_h, curr_w, t_name, t_rep, l_name_str, l_id
            ) = row

            team_reputation = float(t_rep) if (t_rep is not None) else 0.20
            p_norm = normalize_name(p_name)
            fn = normalize_name(f_name)
            ln = normalize_name(l_name)
            fl_norm = f"{fn} {ln}".strip() if (fn and ln) else ""
            t_norm = normalize_team(t_name)
            byear = parse_birth_year(dob)

            tokens = ln.split() if ln else p_norm.split()
            last_tok = tokens[-1] if tokens else ""
            first_init = fn[0] if fn else (p_norm[0] if p_norm else "")

            stats: Optional[Dict[str, Any]] = None
            source = "PROCEDURAL"

            # -------------------------------------------------------------
            # STAGE 1: EA SPORTS FC 26 (Strikt matchning med takkontroll)
            # -------------------------------------------------------------
            if p_norm in self.eafc_by_name:
                stats = self._disambiguate_candidate(self.eafc_by_name[p_norm], t_name, byear, pos, team_reputation)
                if stats: source = "EAFC"
            elif fl_norm and fl_norm in self.eafc_by_fl:
                stats = self._disambiguate_candidate(self.eafc_by_fl[fl_norm], t_name, byear, pos, team_reputation)
                if stats: source = "EAFC"
            elif t_norm and last_tok and (t_norm, last_tok) in self.eafc_by_team_last:
                stats = self._disambiguate_candidate(self.eafc_by_team_last[(t_norm, last_tok)], t_name, byear, pos, team_reputation)
                if stats: source = "EAFC"
            elif first_init and last_tok and byear and (first_init, last_tok, byear) in self.eafc_by_init_last_yr:
                stats = self._disambiguate_candidate(self.eafc_by_init_last_yr[(first_init, last_tok, byear)], t_name, byear, pos, team_reputation)
                if stats: source = "EAFC"

            # -------------------------------------------------------------
            # STAGE 2: FOOTBALL MANAGER 2023 (Strikt matchning)
            # -------------------------------------------------------------
            if not stats:
                if p_norm in self.fm_by_name:
                    stats = self._disambiguate_candidate(self.fm_by_name[p_norm], t_name, byear, pos, team_reputation)
                    if stats: source = "FM23"
                elif fl_norm and fl_norm in self.fm_by_fl:
                    stats = self._disambiguate_candidate(self.fm_by_fl[fl_norm], t_name, byear, pos, team_reputation)
                    if stats: source = "FM23"
                elif t_norm and last_tok and (t_norm, last_tok) in self.fm_by_team_last:
                    stats = self._disambiguate_candidate(self.fm_by_team_last[(t_norm, last_tok)], t_name, byear, pos, team_reputation)
                    if stats: source = "FM23"
                elif first_init and last_tok and byear and (first_init, last_tok, byear) in self.fm_by_init_last_yr:
                    stats = self._disambiguate_candidate(self.fm_by_init_last_yr[(first_init, last_tok, byear)], t_name, byear, pos, team_reputation)
                    if stats: source = "FM23"

            # Om EAFC hittades men FM har djupare mental data:
            if stats and source == "EAFC":
                fm_supp = None
                if p_norm in self.fm_by_name:
                    fm_supp = self._disambiguate_candidate(self.fm_by_name[p_norm], t_name, byear, pos, team_reputation)
                elif fl_norm and fl_norm in self.fm_by_fl:
                    fm_supp = self._disambiguate_candidate(self.fm_by_fl[fl_norm], t_name, byear, pos, team_reputation)
                if fm_supp:
                    stats["determination"] = fm_supp["determination"]
                    stats["work_rate"] = fm_supp["work_rate"]

            # -------------------------------------------------------------
            # STAGE 3: ONLINE STATS ENRICHMENT (OM AKTIVERAD)
            # -------------------------------------------------------------
            if self.online_fetcher and (not stats or source == "PROCEDURAL"):
                p_stats_payload = self.online_fetcher.fetch_sportmonks_player_stats(p_id)
                if p_stats_payload:
                    if not stats:
                        stats = self.generate_conservative_procedural_stats(p_id, pos, team_reputation, dob)
                    stats = self.online_fetcher.apply_stat_adjustments(stats, p_stats_payload)
                    source = "SPORTMONKS"

            # -------------------------------------------------------------
            # STAGE 4: KONSERVATIV PYRAMID/KLUBB-ANKRAD FORMEL FÖR OBSKYRA
            # -------------------------------------------------------------
            if not stats:
                stats = self.generate_conservative_procedural_stats(p_id, pos, team_reputation, dob)
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
                self.cur.executemany("""
                    UPDATE players
                    SET mass = ?, top_speed = ?, stamina_max = ?,
                        vision = ?, composure = ?, aggression = ?,
                        close_control = ?, reflexes = ?, determination = ?,
                        work_rate = ?, rating_source = ?
                    WHERE player_id = ?;
                """, batch_updates)
                self.conn.commit()
                batch_updates.clear()
                print(f"  -> Bearbetat {idx:,} / {total_players:,} spelare...")

        if batch_updates:
            self.cur.executemany("""
                UPDATE players
                SET mass = ?, top_speed = ?, stamina_max = ?,
                    vision = ?, composure = ?, aggression = ?,
                    close_control = ?, reflexes = ?, determination = ?,
                    work_rate = ?, rating_source = ?
                WHERE player_id = ?;
            """, batch_updates)
            self.conn.commit()

        print("\nUtför SQLite PRAGMA integrity_check...")
        self.cur.execute("PRAGMA integrity_check;")
        res = self.cur.fetchone()
        assert res and res[0] == "ok", f"Integrity check failed: {res}"
        self.conn.commit()
        self.conn.close()

        # Spegla till sekundär kopia
        if self.secondary_db:
            print(f"Speglar uppdaterad databas till: {self.secondary_db.resolve()}...")
            self.secondary_db.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(self.primary_db, self.secondary_db)
            print("  [OK] Spegling slutförd.")

        # Spegla till Godot aktiva user:// katalog om den finns
        user_db_candidates = []
        appdata = os.environ.get("APPDATA")
        if appdata:
            user_db_candidates.append(Path(appdata) / "Godot" / "app_userdata" / "PowerFootball 2D" / "powerfootball_master.db")
            user_db_candidates.append(Path(appdata) / "Godot" / "app_userdata" / "PowerFootball-2D" / "powerfootball_master.db")
        home = Path.home()
        user_db_candidates.append(home / ".local" / "share" / "godot" / "app_userdata" / "PowerFootball 2D" / "powerfootball_master.db")
        user_db_candidates.append(home / "Library" / "Application Support" / "Godot" / "app_userdata" / "PowerFootball 2D" / "powerfootball_master.db")

        for u_path in user_db_candidates:
            if u_path.parent.exists():
                print(f"Speglar till Godot user:// databas: {u_path.resolve()}...")
                for ext in ["-wal", "-shm"]:
                    f_stale = Path(str(u_path) + ext)
                    if f_stale.exists():
                        f_stale.unlink()
                shutil.copy2(self.primary_db, u_path)
                print("  [OK] Godot user:// spegling slutförd.")

        elapsed = time.time() - t0
        print("\n==========================================================")
        print("KALIBRERING V3 SLUTFÖRD!")
        print(f"  * Totalt behandlade     : {total_players:,} spelare")
        print(f"  * EA Sports FC 26-betyg : {counts['EAFC']:,} spelare ({counts['EAFC']/total_players*100:.1f}%)")
        print(f"  * FM23-betyg            : {counts['FM23']:,} spelare ({counts['FM23']/total_players*100:.1f}%)")
        if counts["SPORTMONKS"] > 0:
            print(f"  * Sportmonks-berikade   : {counts['SPORTMONKS']:,} spelare ({counts['SPORTMONKS']/total_players*100:.1f}%)")
        print(f"  * Konservativ formel    : {counts['PROCEDURAL']:,} spelare ({counts['PROCEDURAL']/total_players*100:.1f}%)")
        print(f"  * Tidsåtgång            : {elapsed:.2f} sekunder")
        print("==========================================================")


def main():
    parser = argparse.ArgumentParser(description="Rehydrate PowerFootball-2D player ratings (v3).")
    parser.add_argument("--db-path", default=None, help="Explicit path to target SQLite database")
    parser.add_argument("--no-sync", action="store_true", help="Do not mirror primary DB to secondary copy")
    parser.add_argument("--online", action="store_true", help="Enable online scraping/API enricher")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of players for quick testing")
    parser.add_argument("--batch-size", type=int, default=5000, help="Batch size for database updates")
    args = parser.parse_args()

    primary_db, secondary_db, eafc_csv, fm23_csv = resolve_paths(args.db_path)
    if args.no_sync:
        secondary_db = None

    rehydrator = RatingRehydratorV3(
        primary_db,
        secondary_db,
        eafc_csv,
        fm23_csv,
        enable_online=args.online
    )
    rehydrator.run(batch_size=args.batch_size, limit=args.limit)


if __name__ == "__main__":
    main()
