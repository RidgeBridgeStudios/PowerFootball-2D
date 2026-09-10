#!/usr/bin/env bash
# Dynamic task router modulating reasoning mode and model flags based on task scope.
set -euo pipefail

TASK_SCOPE="${1:-simple}"
if [ $# -gt 0 ]; then
    shift
fi
PROMPT="$*"

case "$TASK_SCOPE" in
    "linter"|"syntax")
        echo "Routing to Gemini 3.8 Flash (Low Reasoning / Sub-4s Target)..."
        agy --mode=accept-edits --model="gemini-3.8-flash" -e "Fix diagnostics: $PROMPT"
        ;;
    "kinematics"|"boost"|"architecture")
        echo "Escalating to Antigravity /boost Multi-Agent Pipeline..."
        agy --mode=plan -e "/boost Resolve simulation invariant: $PROMPT"
        ;;
    *)
        agy -e "$PROMPT"
        ;;
esac