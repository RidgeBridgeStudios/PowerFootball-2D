#!/usr/bin/env python3
"""
MCP Server for GDScript 2.0 AST Slicing.
Uses tree-sitter-gdscript to return token-compact structural interfaces.
"""
import sys
import json
from pathlib import Path

try:
    import tree_sitter
    import tree_sitter_gdscript
    HAS_TREE_SITTER = True
except ImportError:
    HAS_TREE_SITTER = False

parser = None
GDSCRIPT_LANGUAGE = None

if HAS_TREE_SITTER:
    try:
        GDSCRIPT_LANGUAGE = tree_sitter.Language(tree_sitter_gdscript.language())
        try:
            parser = tree_sitter.Parser(GDSCRIPT_LANGUAGE)
        except Exception:
            parser = tree_sitter.Parser()
            parser.set_language(GDSCRIPT_LANGUAGE)
    except Exception:
        HAS_TREE_SITTER = False

def extract_signatures(source_code: bytes) -> str:
    output_lines = []
    seen = set()

    if HAS_TREE_SITTER and parser:
        try:
            tree = parser.parse(source_code)
            def walk(node):
                if node.type in ("function_definition", "class_name_statement", "signal_statement"):
                    text = source_code[node.start_byte:node.end_byte].decode("utf-8", errors="ignore").strip()
                    first_line = text.split("\n")[0].strip()
                    if node.type == "function_definition":
                        sig = first_line.split(":")[0].strip() + ":"
                        if sig not in seen:
                            seen.add(sig)
                            output_lines.append(f"{sig} ...")
                    else:
                        if first_line not in seen:
                            seen.add(first_line)
                            output_lines.append(first_line)
                for child in node.children:
                    walk(child)

            walk(tree.root_node)
            if output_lines:
                return "\n".join(output_lines)
        except Exception:
            pass

    # Fallback parser if tree-sitter is missing or fails
    text = source_code.decode("utf-8", errors="ignore")
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("class_name ") or stripped.startswith("signal ") or stripped.startswith("@export "):
            if stripped not in seen:
                seen.add(stripped)
                output_lines.append(stripped)
        elif stripped.startswith("func "):
            sig = stripped.split(":")[0].strip() + ":"
            if sig not in seen:
                seen.add(sig)
                output_lines.append(f"{sig} ...")

    return "\n".join(output_lines)

def handle_request(req: dict) -> dict:
    method = req.get("method")

    if method == "tools/list":
        return {
            "tools": [{
                "name": "get_gdscript_interface",
                "description": "Extracts typed signatures, signals, and classes from a GDScript file without implementation bodies.",
                "inputSchema": {
                    "type": "object",
                    "properties": {
                        "path": {"type": "string", "description": "Workspace relative path to .gd file"}
                    },
                    "required": ["path"]
                }
            }]
        }

    elif method == "tools/call":
        args = req.get("params", {}).get("arguments", {})
        target_path = Path(args.get("path", ""))

        if not target_path.exists():
            return {"error": f"File {target_path} not found"}

        raw_code = target_path.read_bytes()
        signatures = extract_signatures(raw_code)

        return {
            "content": [{"type": "text", "text": signatures}]
        }

    return {"error": "Unsupported method"}

def main():
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        try:
            req = json.loads(line)
            res = handle_request(req)
            res["jsonrpc"] = "2.0"
            res["id"] = req.get("id")
            sys.stdout.write(json.dumps(res) + "\n")
            sys.stdout.flush()
        except json.JSONDecodeError:
            continue

if __name__ == "__main__":
    main()
