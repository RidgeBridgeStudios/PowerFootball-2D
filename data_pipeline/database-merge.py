#!/usr/bin/env python3
"""
data_pipeline/database-merge.py

Spine-first merge: EAFC26-Men.csv is the base (current players + ratings).
FM23 enriches each FC26 player with deep attributes + DOB + ISO3 nationality.

Key changes vs. previous version
--------------------------------
* FC26 is the SPINE. Output = one row per FC26 player.
* DOB matching uses a BIRTH-YEAR BAND (±1) instead of fake exact day-level
  DOB (FC26 only has Age, so day-level DOB is unknowable).
* Stricter matching: default min_score 92, plus a secondary-signal
  requirement (same birth-year OR same last-name token) for scores < 95.
* One-to-one enforcement: an FM23 row can match at most one FC26 row.
* FC26 / FM23 rows tracked by DataFrame index, not by name.
* FM23-only rows are optionally dumped to a separate CSV (--fm-only-out).
"""

import argparse
import ast
import re
import unicodedata
from pathlib import Path

import pandas as pd
from rapidfuzz import fuzz, process


# ---------------------------------------------------------------------------
# Column aliases — unchanged
# ---------------------------------------------------------------------------
FM23_ALIASES = {
    "uid":             ["UID"],
    "name":            ["Name"],
    "dob_raw":         ["DOB"],
    "nationality":     ["Nat"],
    "age":             ["Age"],
    "height_raw":      ["Height"],
    "weight_raw":      ["Weight"],
    "club":            ["Club"],
    "position":        ["Position"],
    "based":           ["Based"],
    "transfer_value":  ["Transfer Value"],
    "preferred_foot":  ["Preferred Foot"],
    "media_handling":  ["Media Handling"],
    "acceleration":    ["Acc"],
    "work_rate":       ["Wor"],
    "vision":          ["Vis"],
    "technique":       ["Tec"],
    "teamwork":        ["Tea"],
    "tackling":        ["Tck"],
    "strength":        ["Str"],
    "stamina":         ["Sta"],
    "reflexes":        ["Ref"],
    "positioning":     ["Pos"],
    "penalty_taking":  ["Pen"],
    "passing":         ["Pas"],
    "pace":            ["Pac"],
    "off_the_ball":    ["OtB"],
    "natural_fitness": ["Nat.1"],
    "marking":         ["Mar"],
    "long_throws":     ["L Th"],
    "long_shots":      ["Lon"],
    "leadership":      ["Ldr"],
    "jumping":         ["Jum"],
    "heading":         ["Hea"],
    "handling":        ["Han"],
    "free_kicks":      ["Fre"],
    "flair":           ["Fla"],
    "first_touch":     ["Fir"],
    "finishing":       ["Fin"],
    "eccentricity":    ["Ecc"],
    "dribbling":       ["Dri"],
    "determination":   ["Det"],
    "decisions":       ["Dec"],
    "crossing":        ["Cro"],
    "corners":         ["Cor"],
    "concentration":   ["Cnt"],
    "composure":       ["Cmp"],
    "communication":   ["Com"],
    "command_of_area": ["Cmd"],
    "bravery":         ["Bra"],
    "balance":         ["Bal"],
    "anticipation":    ["Ant"],
    "agility":         ["Agi"],
    "aggression":      ["Agg"],
    "aerial_reach":    ["Aer"],
    "versatility":     ["Vers"],
    "temperament":     ["Temp"],
    "sportsmanship":   ["Spor"],
    "professionalism": ["Prof"],
    "pressure":        ["Pres"],
    "loyalty":         ["Loy"],
    "injury_proneness":["Inj Pr"],
    "important_matches":["Imp M"],
    "dirtiness":       ["Dirt"],
    "ambition":        ["Amb"],
    "adaptability":    ["Ada"],
    "consistency":     ["Cons"],
    "controversy":     ["Cont"],
}

FC26_ALIASES = {
    "name":          ["Name"],
    "age":           ["Age"],
    "nation":        ["Nation"],
    "league":        ["League"],
    "team":          ["Team"],
    "position":      ["Position"],
    "height_raw":    ["Height"],
    "weight_raw":    ["Weight"],
    "acceleration":  ["Acceleration"],
    "sprint_speed":  ["Sprint Speed"],
    "vision":        ["Vision"],
    "composure":     ["Composure"],
    "aggression":    ["Aggression"],
    "ball_control":  ["Ball Control"],
    "dribbling":     ["Dribbling"],
    "stamina":       ["Stamina"],
    "strength":      ["Strength"],
    "jumping":       ["Jumping"],
    "gk_reflexes":   ["GK Reflexes"],
    "gk_diving":     ["GK Diving"],
    "gk_handling":   ["GK Handling"],
    "pac":           ["PAC"],
    "sho":           ["SHO"],
    "pas":           ["PAS"],
    "dri":           ["DRI"],
    "def":           ["DEF"],
    "phy":           ["PHY"],
    "alt_positions": ["Alternative positions"],
    "play_style":    ["play style"],
    "ovr":           ["OVR"],
}

FM23_ATTR_COLS = [
    "Acc", "Wor", "Vis", "Tec", "Tea", "Tck", "Str", "Sta", "Ref", "Pos",
    "Pen", "Pas", "Pac", "OtB", "Nat.1", "Mar", "L Th", "Lon", "Ldr", "Jum",
    "Hea", "Han", "Fre", "Fla", "Fir", "Fin", "Ecc", "Dri", "Det", "Dec",
    "Cro", "Cor", "Cnt", "Cmp", "Com", "Cmd", "Bra", "Bal", "Ant", "Agi",
    "Agg", "Aer", "Vers", "Temp", "Spor", "Prof", "Pres", "Loy", "Inj Pr",
    "Imp M", "Dirt", "Amb", "Ada", "Cons", "Cont", "Thr", "TRO", "Pun",
    "1v1", "Kic",
]


# ---------------------------------------------------------------------------
# Nationality normalization (unchanged)
# ---------------------------------------------------------------------------
NAT_ALIASES = {
    "eng": "england", "sco": "scotland", "wal": "wales", "nir": "northern ireland",
    "irl": "republic of ireland",
    "ger": "germany", "ned": "holland", "sui": "switzerland", "den": "denmark",
    "por": "portugal", "gre": "greece", "cro": "croatia", "rom": "romania",
    "bul": "bulgaria", "cze": "czech republic", "svk": "slovakia",
    "svn": "slovenia", "srb": "serbia", "bih": "bosnia and herzegovina",
    "mne": "montenegro", "mkd": "north macedonia", "alb": "albania",
    "rus": "russia", "ukr": "ukraine", "blr": "belarus", "pol": "poland",
    "aut": "austria", "hun": "hungary", "tur": "turkey", "isr": "israel",
    "geo": "georgia", "arm": "armenia", "aze": "azerbaijan",
    "kaz": "kazakhstan", "uzb": "uzbekistan", "kos": "kosovo",
    "cyp": "cyprus", "mlt": "malta", "isl": "iceland", "fin": "finland",
    "est": "estonia", "lva": "latvia", "lat": "latvia", "ltu": "lithuania",
    "mda": "moldova", "lux": "luxembourg", "and": "andorra",
    "smr": "san marino", "gib": "gibraltar", "lie": "liechtenstein",
    "fro": "faroe islands",
    "arg": "argentina", "bra": "brazil", "uru": "uruguay",
    "par": "paraguay", "chi": "chile", "col": "colombia",
    "ven": "venezuela", "ecu": "ecuador", "per": "peru", "bol": "bolivia",
    "mex": "mexico", "usa": "united states", "can": "canada",
    "crc": "costa rica", "jam": "jamaica", "hon": "honduras",
    "pan": "panama", "gua": "guatemala", "slv": "el salvador",
    "tri": "trinidad and tobago", "cub": "cuba", "hai": "haiti",
    "dom": "dominican republic", "pur": "puerto rico",
    "cuw": "curacao", "sur": "suriname", "guy": "guyana",
    "kor": "korea republic", "prk": "north korea",
    "jpn": "japan", "chn": "china pr", "tpe": "chinese taipei",
    "hkg": "hong kong", "tha": "thailand", "vie": "vietnam",
    "idn": "indonesia", "mas": "malaysia", "sin": "singapore",
    "phi": "philippines", "mya": "myanmar", "ind": "india",
    "aus": "australia", "nzl": "new zealand",
    "nga": "nigeria", "gha": "ghana", "sen": "senegal",
    "civ": "cote d ivoire", "cmr": "cameroon", "alg": "algeria",
    "mar": "morocco", "tun": "tunisia", "egy": "egypt",
    "rsa": "south africa", "zaf": "south africa",
    "mli": "mali", "bfa": "burkina faso", "gui": "guinea",
    "cod": "congo dr", "cog": "congo", "gab": "gabon",
    "ang": "angola", "zam": "zambia", "zim": "zimbabwe",
    "moz": "mozambique", "tan": "tanzania", "uga": "uganda",
    "ken": "kenya", "eth": "ethiopia",
    "cpv": "cape verde islands", "gnb": "guinea-bissau",
    "sle": "sierra leone", "lbr": "liberia", "tog": "togo",
    "ben": "benin", "nig": "niger", "mrt": "mauritania",
    "gam": "gambia",
    "sau": "saudi arabia", "ksa": "saudi arabia",
    "uae": "united arab emirates", "qat": "qatar",
    "kuw": "kuwait", "bhr": "bahrain", "oma": "oman",
    "jor": "jordan", "lbn": "lebanon", "syr": "syria",
    "irq": "iraq", "irn": "iran", "afg": "afghanistan",
    # FC26 variants
    "netherlands": "holland",
    "south korea": "korea republic",
    "united states of america": "united states",
    "u s a": "united states",
    "ireland": "republic of ireland",
    "czechia": "czech republic",
    "ivory coast": "cote d ivoire",
    "cote d ivoire": "cote d ivoire",
    "bosnia": "bosnia and herzegovina",
    "macedonia": "north macedonia",
    "congo": "congo dr",
    "dr congo": "congo dr",
    "democratic republic of congo": "congo dr",
    "guinea bissau": "guinea-bissau",
    "cape verde": "cape verde islands",
    "cabo verde": "cape verde islands",
    "korea dpr": "north korea",
    "republic of korea": "korea republic",
}


# ---------------------------------------------------------------------------
# Normalization helpers
# ---------------------------------------------------------------------------
def strip_accents(s):
    return "".join(
        c for c in unicodedata.normalize("NFD", s)
        if unicodedata.category(c) != "Mn"
    )


def normalize_name(name):
    if not isinstance(name, str):
        return ""
    n = strip_accents(name).lower()
    n = re.sub(r"[^\w\s]", " ", n)
    n = re.sub(r"\s+", " ", n).strip()
    return n


def last_name_token(name_norm):
    """Crude 'last name' = final whitespace-separated token."""
    parts = name_norm.split()
    return parts[-1] if parts else ""


def normalize_nationality(nat):
    if not isinstance(nat, str):
        return ""
    nat = strip_accents(nat).lower()
    nat = re.sub(r"[^\w\s]", " ", nat)
    nat = re.sub(r"\s+", " ", nat).strip()
    return NAT_ALIASES.get(nat, nat)


def parse_fm23_dob(s):
    """'10/9/2004 (17 years old)' → pd.Timestamp (DD/MM/YYYY)."""
    if not isinstance(s, str):
        return pd.NaT
    m = re.match(r"(\d{1,2})/(\d{1,2})/(\d{4})", s)
    if not m:
        return pd.NaT
    d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
    if mo > 12 and d <= 12:
        d, mo = mo, d
    try:
        return pd.Timestamp(year=y, month=mo, day=d)
    except ValueError:
        return pd.NaT


def parse_fm23_height(s):
    if not isinstance(s, str):
        return None
    m = re.match(r"(\d+)'(\d+)", s)
    if not m:
        return None
    ft, inch = int(m.group(1)), int(m.group(2))
    return round((ft * 12 + inch) * 2.54, 1)


def parse_fm23_weight(s):
    if not isinstance(s, str):
        return None
    m = re.search(r"(\d+)", s)
    return float(m.group(1)) if m else None


def parse_fc26_height(s):
    if not isinstance(s, str):
        return None
    m = re.match(r"(\d+)cm", s)
    return float(m.group(1)) if m else None


def parse_fc26_weight(s):
    if not isinstance(s, str):
        return None
    m = re.match(r"(\d+)kg", s)
    return float(m.group(1)) if m else None


def safe_literal_eval(s):
    if not isinstance(s, str) or not s.strip():
        return []
    try:
        v = ast.literal_eval(s)
        return v if isinstance(v, list) else [v]
    except (ValueError, SyntaxError):
        return []


def resolve_columns(df, aliases, source):
    resolved = {}
    for canonical, options in aliases.items():
        for opt in options:
            if opt in df.columns:
                resolved[canonical] = opt
                break
        else:
            print(f"  [warn] {source}: no column for '{canonical}'")
    return resolved


# ---------------------------------------------------------------------------
# Matching — strict, one-to-one, birth-year band
# ---------------------------------------------------------------------------
def match_fm23_for_fc26(fc_row, fm_pool, min_score=92):
    """
    Return (candidate_row | None, score, reason).

    fm_pool must already be filtered to:
      * same normalized nationality
      * FM23 rows not yet consumed by an earlier FC26 match

    Rules:
      * score < min_score                              → reject
      * min_score <= score < 95 requires a secondary   → reject if none
        signal: same birth year OR same last-name token
      * score >= 95                                    → accept
    """
    if fm_pool.empty:
        return None, 0, "empty_pool"

    birth_year = fc_row.get("birth_year")

    # Narrow by birth-year band (±1) when FM23 DOB is known
    if pd.notna(birth_year):
        dob_band = fm_pool[
            fm_pool["dob"].notna() &
            ((fm_pool["dob"].dt.year - birth_year).abs() <= 1)
        ]
    else:
        dob_band = pd.DataFrame()

    pool = dob_band if not dob_band.empty else fm_pool

    choice = process.extractOne(
        fc_row["name_norm"],
        pool["name_norm"].tolist(),
        scorer=fuzz.token_sort_ratio,
    )
    if not choice:
        return None, 0, "no_choice"

    score = choice[1]
    candidate = pool.iloc[choice[2]]

    if score < min_score:
        return None, score, "below_min"

    if score < 95:
        candidate_dob = candidate.get("dob")
        same_year = (
            pd.notna(birth_year)
            and pd.notna(candidate_dob)
            and abs(candidate_dob.year - birth_year) <= 1
        )
        fc_last = last_name_token(fc_row["name_norm"])
        fm_last = last_name_token(candidate["name_norm"])
        same_last = bool(fc_last) and fc_last == fm_last
        if not (same_year or same_last):
            return None, score, "no_secondary"

    return candidate, score, "ok"


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fm23", required=True,
                    help="FM23 CSV (enrichment source)")
    ap.add_argument("--fc26", required=True,
                    help="FC26 CSV (spine)")
    ap.add_argument("--out", required=True,
                    help="Output master CSV (one row per FC26 player)")
    ap.add_argument("--reference-year", type=int, default=2025,
                    help="Year to subtract FC26 Age from to get birth year.")
    ap.add_argument("--review", default="manual_review.csv",
                    help="CSV of ambiguous / near-miss FM23 matches")
    ap.add_argument("--fm-only-out", default="fm23_only.csv",
                    help="CSV of FM23 rows that matched no FC26 player. "
                         "Pass '' to skip.")
    ap.add_argument("--min-score", type=int, default=92,
                    help="Minimum token_sort_ratio to accept (default 92).")
    args = ap.parse_args()

    # ---------------------------------------------------------------
    # Load FC26 (spine)
    # ---------------------------------------------------------------
    print("Loading FC26 (spine)...")
    fc = pd.read_csv(args.fc26, low_memory=False)
    fc_cols = resolve_columns(fc, FC26_ALIASES, "FC26")
    fc = fc.rename(columns={v: k for k, v in fc_cols.items()})

    # ---------------------------------------------------------------
    # Load FM23 (enrichment)
    # ---------------------------------------------------------------
    print("Loading FM23...")
    fm = pd.read_csv(args.fm23, low_memory=False)
    fm_cols = resolve_columns(fm, FM23_ALIASES, "FM23")
    fm = fm.rename(columns={v: k for k, v in fm_cols.items()})

    for c in FM23_ATTR_COLS:
        if c in fm.columns:
            fm[c] = pd.to_numeric(fm[c], errors="coerce")

    # ---------------------------------------------------------------
    # Enrich FC26 spine
    # ---------------------------------------------------------------
    fc["name_norm"] = fc["name"].apply(normalize_name)
    fc["birth_year"] = args.reference_year - pd.to_numeric(
        fc["age"], errors="coerce"
    )
    fc["nationality_norm"] = fc["nation"].apply(normalize_nationality)
    fc["height_cm"] = fc["height_raw"].apply(parse_fc26_height)
    fc["weight_kg"] = fc["weight_raw"].apply(parse_fc26_weight)
    if "alt_positions" in fc.columns:
        fc["alt_positions_list"] = fc["alt_positions"].apply(safe_literal_eval)

    # ---------------------------------------------------------------
    # Enrich FM23
    # ---------------------------------------------------------------
    fm["name_norm"] = fm["name"].apply(normalize_name)
    fm["dob"] = fm["dob_raw"].apply(parse_fm23_dob)
    fm["nationality_norm"] = (
        fm["nationality"].apply(normalize_nationality)
        if "nationality" in fm.columns else ""
    )
    fm["height_cm"] = (
        fm["height_raw"].apply(parse_fm23_height)
        if "height_raw" in fm.columns else None
    )
    fm["weight_kg"] = (
        fm["weight_raw"].apply(parse_fm23_weight)
        if "weight_raw" in fm.columns else None
    )

    print(f"  FC26: {len(fc)} players, "
          f"nationalities: {fc['nationality_norm'].nunique()}")
    print(f"  FM23: {len(fm)} players, "
          f"valid DOB: {fm['dob'].notna().sum()}, "
          f"nationalities: {fm['nationality_norm'].nunique()}")

    # ---------------------------------------------------------------
    # Prepare enrichment columns on the FC26 spine
    # ---------------------------------------------------------------
    fm_payload_cols = [
        "uid", "dob", "nationality", "club", "position", "based",
        "transfer_value", "preferred_foot", "media_handling",
        "acceleration", "work_rate", "vision", "technique", "teamwork",
        "tackling", "strength", "stamina", "reflexes", "positioning",
        "penalty_taking", "passing", "pace", "off_the_ball",
        "natural_fitness", "marking", "long_throws", "long_shots",
        "leadership", "jumping", "heading", "handling", "free_kicks",
        "flair", "first_touch", "finishing", "eccentricity", "dribbling",
        "determination", "decisions", "crossing", "corners",
        "concentration", "composure", "communication", "command_of_area",
        "bravery", "balance", "anticipation", "agility", "aggression",
        "aerial_reach", "versatility", "temperament", "sportsmanship",
        "professionalism", "pressure", "loyalty", "injury_proneness",
        "important_matches", "dirtiness", "ambition", "adaptability",
        "consistency", "controversy", "height_cm", "weight_kg",
    ]
    fm_payload_cols = [c for c in fm_payload_cols if c in fm.columns]

    fc["fm23_match_name"] = pd.Series([None] * len(fc), dtype="object")
    fc["fm23_match_score"] = 0.0
    fc["fm23_match_reason"] = pd.Series([None] * len(fc), dtype="object")
    for c in fm_payload_cols:
        fc[f"fm23_{c}"] = pd.Series([None] * len(fc), dtype="object")

    # ---------------------------------------------------------------
    # Match FC26 → FM23, one-to-one, with rolling pool shrink
    # ---------------------------------------------------------------
    print("Matching FC26 → FM23...")
    fm_by_nat = {n: g for n, g in fm.groupby("nationality_norm")}
    fm_used_indices = set()          # original FM23 index values already consumed
    manual_review = []
    score_buckets = {"100": 0, "95-99": 0, "92-94": 0}

    for idx, fc_row in fc.iterrows():
        nat = fc_row.get("nationality_norm", "")
        pool = fm_by_nat.get(nat)
        if pool is None or pool.empty:
            continue

        available = pool[~pool.index.isin(fm_used_indices)]
        if available.empty:
            continue

        match, score, reason = match_fm23_for_fc26(
            fc_row, available, args.min_score
        )

        if match is not None:
            fm_used_indices.add(match.name)
            fc.at[idx, "fm23_match_name"] = match.get("name")
            fc.at[idx, "fm23_match_score"] = float(score)
            fc.at[idx, "fm23_match_reason"] = reason
            for c in fm_payload_cols:
                fc.at[idx, f"fm23_{c}"] = match.get(c)

            if score >= 100:
                score_buckets["100"] += 1
            elif score >= 95:
                score_buckets["95-99"] += 1
            else:
                score_buckets["92-94"] += 1
        else:
            if score and score >= 70:
                manual_review.append({
                    "fc26_name": fc_row.get("name"),
                    "fc26_nationality": nat,
                    "fc26_birth_year": fc_row.get("birth_year"),
                    "best_score": score,
                    "reject_reason": reason,
                })

    n_match = len(fm_used_indices)
    print(f"  Matched: {n_match} / {len(fc)} "
          f"({100 * n_match / len(fc):.1f}%)")
    print(f"  Score buckets: "
          f"100={score_buckets['100']}, "
          f"95-99={score_buckets['95-99']}, "
          f"92-94={score_buckets['92-94']}")

    fc["source_primary"] = "FC26"
    fc.loc[fc["fm23_match_name"].notna(), "source_primary"] = "FC26+FM23"

    # ---------------------------------------------------------------
    # Write master
    # ---------------------------------------------------------------
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    fc.to_csv(args.out, index=False)
    print(f"Wrote master: {args.out} ({len(fc)} rows)")

    if manual_review:
        pd.DataFrame(manual_review).to_csv(args.review, index=False)
        print(f"Flagged {len(manual_review)} ambiguous matches → {args.review}")

    # ---------------------------------------------------------------
    # Optional: FM23-only dump
    # ---------------------------------------------------------------
    if args.fm_only_out:
        fm_only = fm[~fm.index.isin(fm_used_indices)].copy()
        fm_only["source_primary"] = "FM23_only"
        fm_only.to_csv(args.fm_only_out, index=False)
        print(f"Wrote FM23-only: {args.fm_only_out} ({len(fm_only)} rows)")

    # ---------------------------------------------------------------
    # Sample
    # ---------------------------------------------------------------
    if n_match:
        print("\nSample matches (first 5):")
        sample = fc[fc["fm23_match_name"].notna()].head(5)
        for _, r in sample.iterrows():
            print(f"  {str(r['name']):30s} ({str(r['nationality_norm']):20s}) "
                  f"→ {str(r['fm23_match_name']):30s} "
                  f"score={r['fm23_match_score']:.1f} "
                  f"[{r['fm23_match_reason']}]")


if __name__ == "__main__":
    main()