#!/usr/bin/env python3
"""
LRU-based Antigravity brain store pruner.
Purges sessions older than 12 hours and truncates oversized transcripts.
"""
import os
import sys
import time
import shutil
from pathlib import Path

BRAIN_DIR = Path.home() / ".gemini" / "antigravity" / "brain"
CLI_BRAIN_DIR = Path.home() / ".gemini" / "antigravity-cli" / "brain"
MAX_SESSION_AGE_HOURS = 12
MAX_TRANSCRIPT_SIZE_MB = 10.0

def prune_brain_store(base_dir: Path) -> None:
    if not base_dir.exists():
        return
    
    now = time.time()
    for session_folder in base_dir.iterdir():
        if not session_folder.is_dir():
            continue
        
        lock_file = session_folder / ".lock"
        if lock_file.exists():
            continue
        
        mtime = session_folder.stat().st_mtime
        age_hours = (now - mtime) / 3600.0
        
        if age_hours > MAX_SESSION_AGE_HOURS:
            shutil.rmtree(session_folder, ignore_errors=True)
            continue
        
        for sg_name in [".system_generated", "system_generated"]:
            log_file = session_folder / sg_name / "logs" / "transcript.jsonl"
            if log_file.exists():
                size_mb = log_file.stat().st_size / (1024 * 1024)
                if size_mb > MAX_TRANSCRIPT_SIZE_MB:
                    lines = log_file.read_text(encoding="utf-8", errors="ignore").splitlines()
                    truncated = lines[:2] + lines[-150:]
                    log_file.write_text("\n".join(truncated) + "\n", encoding="utf-8")

if __name__ == "__main__":
    prune_brain_store(BRAIN_DIR)
    prune_brain_store(CLI_BRAIN_DIR)
    sys.exit(0)
