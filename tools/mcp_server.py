#!/usr/bin/env python3
"""
mcp_server.py — Model Context Protocol (MCP) Standard stdio Server for PowerFootball-2D.

Exposes domain tools and spatial introspection endpoints over JSON-RPC 2.0 stdio MCP:
- get_layer_invariants: Retrieve contracts, choke points, and active files for layers 1-5.
- inspect_scene_tree: Parse .tscn scene graphs, node hierarchies, and collision masks.
- query_spatial_cache: Query player positions, velocities, and tactical anchors.
- run_property_test: Run static analyzers, invariant linters, fuzzers, and headless evaluations.

Usage:
    python tools/mcp_server.py
"""

from __future__ import annotations

import io
import json
import os
import subprocess
import sys
from typing import Any, Dict, List, Optional

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ---------------------------------------------------------------------------
# Tool Implementations
# ---------------------------------------------------------------------------
def tool_get_layer_invariants(layer: int | str) -> dict[str, Any]:
    from layer_context import LAYER_ALIASES, LAYER_DATA

    q = str(layer).lower().strip()
    layer_id = LAYER_ALIASES.get(q)
    if not layer_id or layer_id not in LAYER_DATA:
        return {"error": f"Unknown layer '{layer}'. Valid layers: 1, 2, 3, 4, 5."}

    data = LAYER_DATA[layer_id]
    return {
        "layer_id": layer_id,
        "title": data["title"],
        "description": data["description"],
        "invariants": data["invariants"],
        "choke_points": data["choke_points"],
        "key_files": data["key_files"],
        "rule_file": data.get("rule_file")
    }


def tool_inspect_scene_tree(scene_path: str) -> dict[str, Any]:
    from tscn_linter import lint_tscn_file

    norm_path = scene_path.replace("\\", "/").replace("res://", "")
    full_path = os.path.join(ROOT, norm_path) if not os.path.isabs(norm_path) else norm_path

    if not os.path.exists(full_path):
        return {"error": f"Scene file not found: {scene_path}"}

    violations = lint_tscn_file(full_path)

    # Parse nodes and hierarchy
    nodes = []
    with open(full_path, "r", encoding="utf-8", errors="replace") as f:
        for idx, line in enumerate(f, start=1):
            line = line.strip()
            if line.startswith("[node "):
                nodes.append({"line": idx, "declaration": line})

    return {
        "scene_file": os.path.relpath(full_path, ROOT).replace("\\", "/"),
        "total_nodes": len(nodes),
        "nodes": nodes,
        "violations_count": len(violations),
        "violations": [str(v) for v in violations]
    }


def tool_query_spatial_cache(entity_id: int | str) -> dict[str, Any]:
    # Returns spatial configuration bounds and theoretical coordinates for player/ball
    eid = str(entity_id).lower().strip()
    if eid == "ball":
        return {
            "entity": "ball",
            "position": {"x": 0.0, "y": 0.0, "z": 0.0},
            "velocity": {"vx": 120.0, "vy": 45.0, "vz": 0.0},
            "friction_decel": 180.0,
            "gravity": 980.0,
            "layer_mask": 1  # Layer 1 World only
        }

    try:
        player_idx = int(eid)
    except ValueError:
        return {"error": f"Invalid entity_id: '{entity_id}'. Must be 'ball' or 0..21."}

    if not (0 <= player_idx < 22):
        return {"error": f"Player index {player_idx} out of bounds [0, 21]."}

    team = 0 if player_idx < 11 else 1
    slot = player_idx % 11
    role_map = {
        0: "GK", 1: "LB", 2: "CB", 3: "CB", 4: "RB",
        5: "LM", 6: "CM", 7: "CM", 8: "RM", 9: "ST", 10: "ST"
    }

    return {
        "player_index": player_idx,
        "team": team,
        "role": role_map.get(slot, "CM"),
        "is_goalkeeper": slot == 0,
        "collision_layer": 2,  # Layer 2 Players
        "collision_mask": 3,   # Layer 1 World + Layer 2 Players (NEVER Layer 3 Ball)
        "stagger_modulo": 15,
        "decision_frame": player_idx % 15
    }


def tool_run_property_test(module: str) -> dict[str, Any]:
    mod = module.lower().strip()
    cmd = []

    if mod in ("gdcheck", "static"):
        cmd = [sys.executable, os.path.join(ROOT, "tools", "gdcheck.py")]
    elif mod in ("lint_invariants", "invariants"):
        cmd = [sys.executable, os.path.join(ROOT, "tools", "lint_invariants.py")]
    elif mod in ("tscn", "tscn_linter"):
        cmd = [sys.executable, os.path.join(ROOT, "tools", "tscn_linter.py")]
    elif mod in ("verify_db", "db", "schemas"):
        cmd = [sys.executable, os.path.join(ROOT, "tools", "validate_schemas.py")]
    elif mod in ("fuzz", "fuzz_solvers"):
        cmd = [sys.executable, os.path.join(ROOT, "tools", "fuzz_solvers.py"), "--iterations=10000"]
    elif mod in ("eval_sim", "sim"):
        cmd = [sys.executable, os.path.join(ROOT, "tools", "eval_simulation.py"), "--duration=10"]
    else:
        return {"error": f"Unknown test module '{module}'. Available: gdcheck, invariants, tscn, db, fuzz, sim."}

    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    return {
        "module": mod,
        "exit_code": proc.returncode,
        "status": "PASS" if proc.returncode == 0 else "FAIL",
        "stdout": proc.stdout.strip(),
        "stderr": proc.stderr.strip()
    }


# ---------------------------------------------------------------------------
# MCP JSON-RPC Server
# ---------------------------------------------------------------------------
TOOLS_METADATA = [
    {
        "name": "get_layer_invariants",
        "description": "Extract domain invariant laws, choke point contracts, and key file paths for simulation layers 1-5.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "layer": {"type": ["integer", "string"], "description": "Simulation layer number (1-5) or alias (physics, ai, social, club, narrative)"}
            },
            "required": ["layer"]
        }
    },
    {
        "name": "inspect_scene_tree",
        "description": "Parse a Godot .tscn scene file to inspect node hierarchies, resource references, and collision masks.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "scene_path": {"type": "string", "description": "Relative path to .tscn file (e.g. entities/player/HeavyPlayer.tscn)"}
            },
            "required": ["scene_path"]
        }
    },
    {
        "name": "query_spatial_cache",
        "description": "Inspect spatial configuration and collision contracts for player slots (0-21) or ball.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "entity_id": {"type": ["integer", "string"], "description": "Player slot index (0..21) or 'ball'"}
            },
            "required": ["entity_id"]
        }
    },
    {
        "name": "run_property_test",
        "description": "Execute static analysis, invariant linters, fuzzing, or headless simulation suites.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "module": {"type": "string", "description": "Test module name: gdcheck, invariants, tscn, db, fuzz, sim"}
            },
            "required": ["module"]
        }
    }
]


def handle_json_rpc(request: dict[str, Any]) -> dict[str, Any]:
    req_id = request.get("id")
    method = request.get("method")
    params = request.get("params", {})

    if method == "initialize":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {
                    "name": "powerfootball-mcp-server",
                    "version": "1.0.0"
                }
            }
        }

    elif method == "tools/list":
        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {"tools": TOOLS_METADATA}
        }

    elif method == "tools/call":
        tool_name = params.get("name")
        args = params.get("arguments", {})

        if tool_name == "get_layer_invariants":
            res = tool_get_layer_invariants(args.get("layer", 1))
        elif tool_name == "inspect_scene_tree":
            res = tool_inspect_scene_tree(args.get("scene_path", ""))
        elif tool_name == "query_spatial_cache":
            res = tool_query_spatial_cache(args.get("entity_id", 0))
        elif tool_name == "run_property_test":
            res = tool_run_property_test(args.get("module", "gdcheck"))
        else:
            return {
                "jsonrpc": "2.0",
                "id": req_id,
                "error": {"code": -32601, "message": f"Method '{tool_name}' not found"}
            }

        return {
            "jsonrpc": "2.0",
            "id": req_id,
            "result": {
                "content": [
                    {
                        "type": "text",
                        "text": json.dumps(res, indent=2)
                    }
                ]
            }
        }

    elif method == "ping":
        return {"jsonrpc": "2.0", "id": req_id, "result": {}}

    return {
        "jsonrpc": "2.0",
        "id": req_id,
        "error": {"code": -32601, "message": f"Unhandled method '{method}'"}
    }


def main() -> int:
    # If run in CLI test mode
    if len(sys.argv) > 1 and sys.argv[1] == "--test":
        print("[mcp_server] Running test call to 'get_layer_invariants'...")
        res = tool_get_layer_invariants(2)
        print(json.dumps(res, indent=2))
        return 0

    # stdio JSON-RPC loop
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
            resp = handle_json_rpc(req)
            sys.stdout.write(json.dumps(resp) + "\n")
            sys.stdout.flush()
        except Exception as e:
            err_resp = {
                "jsonrpc": "2.0",
                "id": None,
                "error": {"code": -32700, "message": f"Parse error: {e}"}
            }
            sys.stdout.write(json.dumps(err_resp) + "\n")
            sys.stdout.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
