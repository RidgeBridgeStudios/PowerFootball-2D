---
description: Context window management and tool output discipline for all sessions
paths: ["**/*"]
---

## Context Hygiene

Maintain signal-to-noise ratio as context window fills. Clean output discipline preserves reasoning depth at 70%+ context.

### PROHIBITED

Pasting raw shell output (>3 lines) into context without summary:
```bash
# WRONG — pastes 200 lines of find output
find . -name "*.gd" -not -path "./.git/*"

# CORRECT — pasted summary
find: 47 files [autoloads/CareerManager.gd, shared/QuickSimEngine.gd, ...]
```

Reading entire directories at session start as "orientation":
- Do not `cat autoloads/*.gd` or `ls -la shared/`
- Use grep and targeted reads instead
- Reference files by path, not by pasting content

Re-reading files already loaded in this session's context:
- Once a file is in context, grep it instead of re-reading
- Use `/clear` between major subsystems if prior content is stale
- Trust context compression; do not refresh manually

Summarising CLAUDE.md or POWERFOOTBALL_MASTER_VISION.md back into conversation:
- Those files are canonical; do not paraphrase
- Reference by section instead: "@Part II — Simulation Stack"
- Never restate vision; focus on implementation

### Tool Output Rule

Always reduce shell output to structured summary before injecting:

| Tool | Output Format | Example |
|------|---------------|---------|
| gdcheck | `gdcheck: N errors \| PASS/FAIL [— lines X, Y, Z]` | `gdcheck: 3 errors \| FAIL — lines 42, 103, 156` |
| grep | `grep: N matches in M files [filenames]` | `grep: 12 matches in 3 files [CareerManager.gd, QuickSimEngine.gd, MatchStatsTracker.gd]` |
| find | `find: N files [paths]` | `find: 47 files [autoloads/CareerManager.gd, shared/QuickSimEngine.gd, ...]` |
| git status | `git status: N unstaged, M untracked` | `git status: 3 unstaged, 2 untracked [AGENTS.md, .claude/rules/context-hygiene.md]` |

### Pre-Load Rule

Read only files the current task directly requires.
When implementation intent is unclear, read research-index.md and consult the relevant file before writing any code.

Use `grep -r "ClassName" . --include="*.gd"` to locate dependencies instead of reading directories. This is faster and cheaper than scanning subdirectories.

### Scope Rule

One session = one file + one method/feature. Hand off via AGENTS_ERRATA.md.

When a feature spans multiple files or requires > one architectural decision, add a Session State block to AGENTS_ERRATA.md before ending the session:

```
## Session State: [date] [model]
TASK: [what was attempted]
FILES MODIFIED: [list]
GDCHECK: [pass/fail + count]
INVARIANTS CONSULTED: [list of .claude/rules/*.md]
NEXT: [exactly what next session does first]
NEW RULES: [prohibitions discovered, not yet in .claude/rules/]
```

### Context Budget Tracking

Monitor context usage across three phases:

| Phase | Budget | Action |
|-------|--------|--------|
| 0–50% | OPTIMAL | Full architecture work. Multi-layer features. Reference files inline. |
| 50–70% | MONITOR | Verify outputs against .claude/rules files. Use grep for spot checks. |
| 70–85% | DANGER | Run `/compact` to compress prior messages. Do not start new features. |
| 85%+ | CRITICAL | Run `/compact` or `/clear` before next task. Switch subsystems only. |

Switch major subsystems with `/clear` (career world ↔ quick-sim match ↔ narrative/presentation). CLAUDE.md and .claude/rules/ survive both compaction and clear.
