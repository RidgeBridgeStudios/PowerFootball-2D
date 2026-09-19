#!/usr/bin/env python3
"""
data_pipeline/database-merge-optimized.py

Optimerad pipeline för att bygga en initial spelardatabas för en fotbollssimulator.
Skapar en "spine" från FC26 och berikar med djupa attribut från FM23.
Redo att utökas med externa API-källor i framtiden.
"""

import argparse
import ast
import re
import unicodedata
from pathlib import Path

import pandas as pd
from rapidfuzz import fuzz, process

# =============================================================================
# KONFIGURATION & ALIAS (Bevarade från originalskriptet)
# =============================================================================

FM23_ALIASES = {
    "uid": ["UID"], "name": ["Name"], "dob_raw": ["DOB"], "nationality": ["Nat"],
    "age": ["Age"], "height_raw": ["Height"], "weight_raw": ["Weight"],
    "club": ["Club"], "position": ["Position"], "based": ["Based"],
    "transfer_value": ["Transfer Value"], "preferred_foot": ["Preferred Foot"],
    "acceleration": ["Acc"], "work_rate": ["Wor"], "vision": ["Vis"],
    "technique": ["Tec"], "teamwork": ["Tea"], "tackling": ["Tck"],
    "strength": ["Str"], "stamina": ["Sta"], "reflexes": ["Ref"],
    "positioning": ["Pos"], "passing": ["Pas"], "pace": ["Pac"],
    "off_the_ball": ["OtB"], "finishing": ["Fin"], "dribbling": ["Dri"],
    "composure": ["Cmp"], "decisions": ["Dec"], "anticipation": ["Ant"]
    # ... (Lägg till resterande attribut från din ursprungliga lista vid behov)
}

FC26_ALIASES = {
    "name": ["Name"], "age": ["Age"], "nation": ["Nation"], "league": ["League"],
    "team": ["Team"], "position": ["Position"], "height_raw": ["Height"],
    "weight_raw": ["Weight"], "ovr": ["OVR"]
}

NAT_ALIASES = {
    "eng": "england", "sco": "scotland", "wal": "wales", "ger": "germany",
    "ned": "holland", "sui": "switzerland", "den": "denmark", "por": "portugal",
    "arg": "argentina", "bra": "brazil", "uru": "uruguay", "usa": "united states",
    "netherlands": "holland", "south korea": "korea republic", 
    "united states of america": "united states", "ireland": "republic of ireland"
}

# =============================================================================
# KLASS: DataNormalizer
# Ansvarar för all tvätt och konvertering av rådata.
# =============================================================================
class DataNormalizer:
    
    @staticmethod
    def strip_accents(s: str) -> str:
        if not isinstance(s, str): return ""
        return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")

    @classmethod
    def normalize_name(cls, name: str) -> str:
        n = cls.strip_accents(name).lower()
        n = re.sub(r"[^\w\s]", " ", n)
        return re.sub(r"\s+", " ", n).strip()

    @classmethod
    def normalize_nationality(cls, nat: str) -> str:
        nat_norm = cls.normalize_name(nat)
        return NAT_ALIASES.get(nat_norm, nat_norm)

    @staticmethod
    def parse_fm23_dob(s: str) -> pd.Timestamp:
        if not isinstance(s, str): return pd.NaT
        m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})", s)
        if not m: return pd.NaT
        d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if mo > 12 and d <= 12: d, mo = mo, d # Hantera felvända format
        try:
            return pd.Timestamp(year=y, month=mo, day=d)
        except ValueError:
            return pd.NaT

    @staticmethod
    def resolve_columns(df: pd.DataFrame, aliases: dict, source: str) -> dict:
        """Hittar rätt kolumnnamn i en DataFrame baserat på alias-ordboken."""
        resolved = {}
        for canonical, options in aliases.items():
            for opt in options:
                if opt in df.columns:
                    resolved[canonical] = opt
                    break
        return resolved

# =============================================================================
# KLASS: PlayerMatcher
# Kapslar in fuzzy-logiken för att hitta rätt spelare mellan dataset.
# =============================================================================
class PlayerMatcher:
    def __init__(self, min_score: int = 92):
        self.min_score = min_score

    def match(self, base_row: pd.Series, enrichment_pool: pd.DataFrame) -> tuple:
        """
        Utvärderar den bästa matchningen för en spelare med hjälp av namn, ålder och position.
        """
        if enrichment_pool.empty:
            return None, 0, "empty_pool"

        birth_year = base_row.get("birth_year")
        
        # Steg 1: Filtrera på födelseårs-band (±1 år)
        if pd.notna(birth_year):
            dob_band = enrichment_pool[
                enrichment_pool["dob"].notna() &
                ((enrichment_pool["dob"].dt.year - birth_year).abs() <= 1)
            ]
            pool = dob_band if not dob_band.empty else enrichment_pool
        else:
            pool = enrichment_pool

        # Steg 2: Hitta det närmaste namnet via Fuzzy Matching
        choice = process.extractOne(
            base_row["name_norm"],
            pool["name_norm"].tolist(),
            scorer=fuzz.token_sort_ratio,
        )
        
        if not choice:
            return None, 0, "no_choice"

        score = choice[1]
        candidate = pool.iloc[choice[2]]

        # Steg 3: Kvalitetssäkring och Tie-breakers
        if score < self.min_score:
            return None, score, "below_min"

        if score < 95:
            # Tie-breaker 1: Samma efternamn
            fc_last = base_row["name_norm"].split()[-1] if base_row["name_norm"] else ""
            fm_last = candidate["name_norm"].split()[-1] if candidate["name_norm"] else ""
            same_last = bool(fc_last) and fc_last == fm_last
            
            # Tie-breaker 2: Samma grundposition (ex. "ST", "CB")
            fc_pos = str(base_row.get("position", "")).lower()
            fm_pos = str(candidate.get("position", "")).lower()
            same_position = (fc_pos in fm_pos) or (fm_pos in fc_pos) if fc_pos and fm_pos else False
            
            if not (same_last or same_position):
                return None, score, "no_secondary_signal"

        return candidate, score, "ok"

# =============================================================================
# KLASS: DatabasePipeline
# Orkestrerar flödet, läser, berikar och sparar slutprodukten.
# =============================================================================
class DatabasePipeline:
    def __init__(self, fc_path: str, fm_path: str, out_path: str, ref_year: int = 2025):
        self.fc_path = fc_path
        self.fm_path = fm_path
        self.out_path = out_path
        self.ref_year = ref_year
        self.matcher = PlayerMatcher(min_score=92)
        
    def load_data(self):
        print("Laddar och standardiserar FC26 (Spine)...")
        self.fc = pd.read_csv(self.fc_path, low_memory=False)
        cols = DataNormalizer.resolve_columns(self.fc, FC26_ALIASES, "FC26")
        self.fc.rename(columns={v: k for k, v in cols.items()}, inplace=True)
        
        self.fc["name_norm"] = self.fc["name"].apply(DataNormalizer.normalize_name)
        self.fc["birth_year"] = self.ref_year - pd.to_numeric(self.fc["age"], errors="coerce")
        self.fc["nationality_norm"] = self.fc["nation"].apply(DataNormalizer.normalize_nationality)

        print("Laddar och standardiserar FM23 (Enrichment)...")
        self.fm = pd.read_csv(self.fm_path, low_memory=False)
        cols = DataNormalizer.resolve_columns(self.fm, FM23_ALIASES, "FM23")
        self.fm.rename(columns={v: k for k, v in cols.items()}, inplace=True)
        
        self.fm["name_norm"] = self.fm["name"].apply(DataNormalizer.normalize_name)
        self.fm["dob"] = self.fm["dob_raw"].apply(DataNormalizer.parse_fm23_dob)
        if "nationality" in self.fm.columns:
            self.fm["nationality_norm"] = self.fm["nationality"].apply(DataNormalizer.normalize_nationality)

    def execute_merge(self):
        print("Startar matchningsprocessen...")
        fm_by_nat = {n: g for n, g in self.fm.groupby("nationality_norm")}
        fm_used_indices = set()
        
        # Skapa tomma kolumner i FC26 för den data vi vill lyfta över
        payload_cols = [c for c in FM23_ALIASES.keys() if c in self.fm.columns]
        for c in payload_cols:
            self.fc[f"fm_{c}"] = None
            
        self.fc["match_status"] = "Unmatched"
        matches_found = 0

        for idx, fc_row in self.fc.iterrows():
            nat = fc_row.get("nationality_norm", "")
            pool = fm_by_nat.get(nat)
            
            if pool is None or pool.empty:
                continue

            available = pool[~pool.index.isin(fm_used_indices)]
            match_row, score, reason = self.matcher.match(fc_row, available)

            if match_row is not None:
                fm_used_indices.add(match_row.name)
                matches_found += 1
                self.fc.at[idx, "match_status"] = f"Matched ({score})"
                
                # Överför attributen
                for c in payload_cols:
                    self.fc.at[idx, f"fm_{c}"] = match_row.get(c)

        print(f"Matchning klar! Hittade {matches_found} matchningar totalt.")
        
    def export(self):
        Path(self.out_path).parent.mkdir(parents=True, exist_ok=True)
        
        # Städa upp temporära kolumner innan export
        export_df = self.fc.drop(columns=["name_norm", "nationality_norm", "birth_year"], errors="ignore")
        export_df.to_csv(self.out_path, index=False)
        print(f"Master-databas skapad och sparad till: {self.out_path}")

# =============================================================================
# STARTPUNKT
# =============================================================================
def main():
    ap = argparse.ArgumentParser(description="Fotbollssimulator Database Builder")
    ap.add_argument("--fm", required=True, help="Sökväg till FM23 CSV")
    ap.add_argument("--fc", required=True, help="Sökväg till FC26 CSV")
    ap.add_argument("--out", default="game_database_init.csv", help="Slutgiltig output för spelet")
    args = ap.parse_args()

    pipeline = DatabasePipeline(fc_path=args.fc, fm_path=args.fm, out_path=args.out)
    pipeline.load_data()
    pipeline.execute_merge()
    pipeline.export()

if __name__ == "__main__":
    main()