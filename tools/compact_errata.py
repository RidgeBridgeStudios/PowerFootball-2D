#!/usr/bin/env python3
"""
compact_errata.py — Errata memory compaction and archiving tool.

1. Automatically runs sync_rules logic to promote pending discovered_rules
   to .claude/rules/ and docs/CORE_INVARIANTS.md.
2. Archives session_state entries older than the 3 most recent sessions into
   docs/archive/errata_history.md.
3. Preserves clean machine-readable YAML formatting in AGENTS_ERRATA.md.
"""

from __future__ import annotations

import os
import re
import sys
import subprocess

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ERRATA_FILE = os.path.join(ROOT, "AGENTS_ERRATA.md")
ARCHIVE_DIR = os.path.join(ROOT, "docs", "archive")
ARCHIVE_FILE = os.path.join(ARCHIVE_DIR, "errata_history.md")
SYNC_RULES_PATH = os.path.join(ROOT, "tools", "sync_rules.py")


def run_sync_rules() -> None:
    print("[compact-errata] Running sync-rules to promote pending discovered_rules...")
    try:
        proc = subprocess.run([sys.executable, SYNC_RULES_PATH], cwd=ROOT, capture_output=True, text=True)
        if proc.stdout.strip():
            print(proc.stdout.strip())
        if proc.returncode != 0:
            print(f"[compact-errata] Warning: sync-rules exited with code {proc.returncode}: {proc.stderr.strip()}", file=sys.stderr)
    except Exception as e:
        print(f"[compact-errata] Notice: Failed to run sync_rules: {e}", file=sys.stderr)


def extract_session_blocks(session_section_text: str) -> list[str]:
    """Splits session_state YAML into individual session item blocks."""
    # Find start of session_state:
    m = re.search(r"session_state:\s*\n", session_section_text)
    if not m:
        return []
    body = session_section_text[m.end():]
    # Split on lines starting with '  - date:' or '  -'
    raw_blocks = re.split(r"\n(?=\s*-\s+date:)", "\n" + body)
    blocks = [b.strip("\n") for b in raw_blocks if b.strip() and "- date:" in b]
    return blocks


def archive_sessions(old_blocks: list[str]) -> None:
    os.makedirs(ARCHIVE_DIR, exist_ok=True)
    header = ""
    if not os.path.exists(ARCHIVE_FILE) or os.path.getsize(ARCHIVE_FILE) == 0:
        header = "# Errata History Archive\n\nHistorical archived session_state entries from `AGENTS_ERRATA.md`.\n\n```yaml\nsession_state_archive:\n"

    with open(ARCHIVE_FILE, "a" if os.path.exists(ARCHIVE_FILE) and os.path.getsize(ARCHIVE_FILE) > 0 else "w", encoding="utf-8") as f:
        if header:
            f.write(header)
        for block in old_blocks:
            # Ensure proper indent
            lines = block.splitlines()
            formatted = "\n".join(lines)
            f.write(formatted + "\n\n")

    print(f"[compact-errata] Archived {len(old_blocks)} old session(s) -> {os.path.relpath(ARCHIVE_FILE, ROOT)}")


def compact_errata_file() -> int:
    if not os.path.exists(ERRATA_FILE):
        print(f"[compact-errata] Error: {ERRATA_FILE} not found.", file=sys.stderr)
        return 1

    with open(ERRATA_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # Locate Session State section
    session_section_match = re.search(r"(## Session State\s*\n\s*```yaml\s*\n)(.*?)(```)", content, re.DOTALL)
    if not session_section_match:
        print("[compact-errata] Warning: Could not locate '## Session State' block in AGENTS_ERRATA.md.")
        return 0

    prefix = session_section_match.group(1)
    body = session_section_match.group(2)
    suffix = session_section_match.group(3)

    # Extract schema comments
    schema_comments = []
    for line in body.splitlines():
        if line.strip().startswith("#"):
            schema_comments.append(line)
        elif line.strip().startswith("session_state:"):
            break

    schema_header = "\n".join(schema_comments) + "\n\nsession_state:\n"

    blocks = extract_session_blocks(body)
    print(f"[compact-errata] Found {len(blocks)} total session state entry(ies).")

    if len(blocks) <= 3:
        print(f"[compact-errata] Session count ({len(blocks)}) <= 3. No compaction needed.")
        return 0

    old_blocks = blocks[:-3]
    retained_blocks = blocks[-3:]

    # Archive old blocks
    archive_sessions(old_blocks)

    # Reconstruct new session_state body
    retained_text = "\n\n".join(retained_blocks)
    new_body = schema_header + retained_text + "\n"
    new_session_section = prefix + new_body + suffix

    new_content = (
        content[:session_section_match.start()]
        + new_session_section
        + content[session_section_match.end():]
    )

    with open(ERRATA_FILE, "w", encoding="utf-8") as f:
        f.write(new_content)

    print(f"[compact-errata] Successfully compacted AGENTS_ERRATA.md. Retained latest 3 session(s).")
    return 0


def main() -> int:
    run_sync_rules()
    return compact_errata_file()


if __name__ == "__main__":
    sys.exit(main())
