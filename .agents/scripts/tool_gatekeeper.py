#!/usr/bin/env python3
import sys
import json
import re

def main():
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            print(json.dumps({"decision": "allow"}))
            return 0
        payload = json.loads(raw)
    except Exception:
        print(json.dumps({"decision": "allow"}))
        return 0

    tool_name = payload.get("toolCall", {}).get("name", "")
    args = payload.get("toolCall", {}).get("args", {})
    cmd = args.get("CommandLine", "")

    if tool_name == "run_command":
        if re.search(r"(grep|rg)\s+.*(-r|-R|--recursive)", cmd) or re.search(r"find\s+(\.|\/)\s+-name", cmd):
            print(json.dumps({
                "decision": "deny",
                "reason": "POLICY VIOLATION: Unconstrained directory scans prohibited. Query the knowledge graph via 'graphify query <concept>' or inspect interfaces with the 'gdscript-slicer' MCP server."
            }, indent=2))
            return 0

        if re.search(r"(cat|head|tail)\s+.*(MatchWorldModel|GameEvents)\.gd", cmd):
            print(json.dumps({
                "decision": "deny",
                "reason": "POLICY VIOLATION: Direct reads of core simulation choke points are prohibited. Use 'gdscript-slicer' to inspect interface signatures."
            }, indent=2))
            return 0

    print(json.dumps({"decision": "allow"}, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main())