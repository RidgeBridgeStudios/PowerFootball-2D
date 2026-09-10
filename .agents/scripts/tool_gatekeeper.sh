#!/usr/bin/env bash
# Deterministic pre-execution validation gate (<15ms latency).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v jq >/dev/null 2>&1; then
    PAYLOAD=$(cat)
    TOOL_NAME=$(echo "$PAYLOAD" | jq -r '.toolCall.name // empty')
    CMD=$(echo "$PAYLOAD" | jq -r '.toolCall.args.CommandLine // empty')

    if [[ "$TOOL_NAME" == "run_command" ]]; then
        if [[ "$CMD" =~ (grep|rg)[[:space:]]+.*(-r|-R|--recursive) ]] || \
           [[ "$CMD" =~ find[[:space:]]+(\.|\/)[[:space:]]+-name ]]; then
            cat <<EOF
{
  "decision": "deny",
  "reason": "POLICY VIOLATION: Unconstrained directory scans prohibited. Query the knowledge graph via 'graphify query <concept>' or inspect interfaces with the 'gdscript-slicer' MCP server."
}
EOF
            exit 0
        fi
        
        if [[ "$CMD" =~ (cat|head|tail)[[:space:]]+.*(MatchWorldModel|GameEvents)\.gd ]]; then
            cat <<EOF
{
  "decision": "deny",
  "reason": "POLICY VIOLATION: Direct reads of core simulation choke points are prohibited. Use 'gdscript-slicer' to inspect interface signatures."
}
EOF
            exit 0
        fi
    fi

    cat <<EOF
{
  "decision": "allow"
}
EOF
    exit 0
else
    if command -v py >/dev/null 2>&1; then
        exec py -3 "$SCRIPT_DIR/tool_gatekeeper.py"
    elif command -v python3 >/dev/null 2>&1; then
        exec python3 "$SCRIPT_DIR/tool_gatekeeper.py"
    else
        exec python "$SCRIPT_DIR/tool_gatekeeper.py"
    fi
fi