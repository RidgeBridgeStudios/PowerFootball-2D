#!/usr/bin/env python3
"""
Sync Rules Tool
Parses structured logs in AGENTS_ERRATA.md and generates git commits to promote them into .claude/rules/ and docs/CORE_INVARIANTS.md.
"""

import os
import re
import sys
import subprocess

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ERRATA_FILE = os.path.join(REPO_ROOT, "AGENTS_ERRATA.md")
RULES_DIR = os.path.join(REPO_ROOT, ".claude", "rules")


def parse_discovered_rules(content: str) -> list[dict]:
    rules = []
    # Match YAML blocks within discovered_rules
    dr_match = re.search(r"discovered_rules:\s*(.*?)(?=\n[a-z_]+:|\Z)", content, re.DOTALL)
    if not dr_match:
        return rules

    dr_text = dr_match.group(1).strip()
    if not dr_text or dr_text == "[]":
        return rules

    # Strip comment lines
    non_comment_lines = [
        line for line in dr_text.splitlines()
        if not line.strip().startswith("#") and line.strip()
    ]
    cleaned_text = "\n".join(non_comment_lines)
    if not cleaned_text.strip() or cleaned_text.strip() == "[]":
        return rules

    # Parse items starting with - id:
    item_blocks = re.split(r"\n\s*-\s*id:\s*", "\n" + cleaned_text)
    for block in item_blocks:
        if not block.strip():
            continue
        lines = block.strip().split("\n")
        rule_id = lines[0].strip().strip("\"'")
        rule = {"id": rule_id, "status": "pending"}
        for line in lines[1:]:
            kv = line.strip().split(":", 1)
            if len(kv) == 2:
                k = kv[0].strip()
                v = kv[1].strip().strip("\"'")
                rule[k] = v
        rules.append(rule)
    return rules


def main() -> int:
    if not os.path.exists(ERRATA_FILE):
        print(f"[sync-rules] Error: {ERRATA_FILE} not found.", file=sys.stderr)
        return 1

    with open(ERRATA_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    print("[sync-rules] Scanning AGENTS_ERRATA.md for pending rules...")
    rules = parse_discovered_rules(content)
    pending_rules = [r for r in rules if r.get("status") == "pending"]

    if not pending_rules:
        print("[sync-rules] No pending rules found in AGENTS_ERRATA.md (all promoted or empty).")
        return 0

    print(f"[sync-rules] Found {len(pending_rules)} pending rule(s) to promote.")
    promoted_count = 0

    for r in pending_rules:
        rule_id = r.get("id", "unnamed")
        category = r.get("category", "general")
        invariant = r.get("invariant", "")
        rationale = r.get("rationale", "")
        target_path = r.get("promotion_target", os.path.join(RULES_DIR, f"{category}.md"))
        if not os.path.isabs(target_path):
            target_path = os.path.join(REPO_ROOT, target_path)

        os.makedirs(os.path.dirname(target_path), exist_ok=True)
        append_text = f"\n\n### {rule_id}\n- **Invariant:** {invariant}\n- **Rationale:** {rationale}\n"
        
        with open(target_path, "a", encoding="utf-8") as tf:
            tf.write(append_text)
        print(f"[sync-rules] Promoted {rule_id} -> {os.path.relpath(target_path, REPO_ROOT)}")
        promoted_count += 1

    # Update status in AGENTS_ERRATA.md
    updated_content = re.sub(r"(status:\s*)pending", r"\1promoted", content)
    with open(ERRATA_FILE, "w", encoding="utf-8") as f:
        f.write(updated_content)

    # Git commit if git is available
    try:
        subprocess.run(["git", "add", ERRATA_FILE, ".claude/rules/", "docs/"], cwd=REPO_ROOT, check=True)
        commit_msg = f"chore(rules): promote {promoted_count} rule(s) from AGENTS_ERRATA.md"
        subprocess.run(["git", "commit", "-m", commit_msg], cwd=REPO_ROOT, check=True)
        print(f"[sync-rules] Created git commit: '{commit_msg}'")
    except Exception as e:
        print(f"[sync-rules] Notice: Git commit skipped or failed ({e})")

    print(f"[sync-rules] Completed. Successfully promoted {promoted_count} rule(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
