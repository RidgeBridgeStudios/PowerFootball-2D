#!/usr/bin/env python3
"""lint_xref.py — cross-reference qualified member access against real definitions.

Fills a specific hole in the existing gates. tools/gdcheck.py resolves autoload
names and class_names as known TYPES but never checks that a member actually
exists on them, and it does not type-check expressions at all. So a call like

    RefereeLoader.get_or_assign_referee(home, away)

passes every static check in the repo while being a guaranteed runtime crash if
that method was never written. This linter caught exactly that: three shipped
call sites (KickOffMenu, PreGameScreen, and the career layer) were calling a
RefereeLoader method that did not exist.

What it does:
  1. Indexes every .gd file's real surface — funcs, vars, consts, signals,
     enums and their values, and inner classes.
  2. Indexes each autoload from project.godot the same way.
  3. Scans all code (string literals and comments stripped) for `Owner.member`
     where Owner is a known class_name or autoload, and reports any member that
     the owner does not expose.
  4. Verifies every res:// scene/resource path referenced in code exists.

Members inherited from Object/RefCounted/Node/Resource are whitelisted, since
they are real but never declared in project source (the same allowance
gdcheck.py documents for `.new()`).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SKIP_DIRS = (".git", ".godot", "docs/archive", "addons", "legacy")

# Inherited engine surface: real, but declared nowhere in project source.
UNIVERSAL = {
    "new", "instantiate", "duplicate", "connect", "disconnect", "is_connected",
    "call", "call_deferred", "callv", "free", "queue_free", "get", "set",
    "has_method", "has_signal", "has_meta", "get_meta", "set_meta", "remove_meta",
    "emit", "emit_signal", "bind", "unbind", "is_valid", "resource_path",
    "resource_name", "get_class", "is_class", "notification", "get_instance_id",
    "reference", "unreference", "to_string", "get_script", "set_script",
    "get_node", "get_node_or_null", "add_child", "remove_child", "get_children",
    "get_parent", "get_tree", "is_inside_tree", "is_instance_valid", "set_deferred",
    "process_mode", "name", "owner", "get_child_count", "add_to_group",
    "is_in_group", "remove_from_group", "get_groups", "propagate_call",
    # Common builtin-container methods that can appear after a typed local.
    "keys", "values", "size", "append", "append_array", "clear", "has", "erase",
    "find", "is_empty", "resize", "fill", "sort", "sort_custom", "slice",
    "remove_at", "insert", "pop_back", "front", "back", "reverse", "count",
}


def collect(path):
    """(class_name, surface_set, source) for one .gd file."""
    with open(path, encoding="utf-8") as fh:
        src = fh.read()
    m = re.search(r"^class_name\s+(\w+)", src, re.M)
    cname = m.group(1) if m else None
    surface = set()
    for mm in re.finditer(r"^\s*(?:static\s+)?func\s+(\w+)", src, re.M):
        surface.add(mm.group(1))
    for mm in re.finditer(
        r"^\s*(?:@export[^\n]*\n\s*)?(?:@onready\s+)?(?:static\s+)?var\s+(\w+)", src, re.M
    ):
        surface.add(mm.group(1))
    for mm in re.finditer(r"^\s*const\s+(\w+)", src, re.M):
        surface.add(mm.group(1))
    for mm in re.finditer(r"^\s*signal\s+(\w+)", src, re.M):
        surface.add(mm.group(1))
    for mm in re.finditer(r"^\s*class\s+(\w+)", src, re.M):
        surface.add(mm.group(1))
    for mm in re.finditer(r"^\s*enum\s+(\w+)\s*\{([^}]*)\}", src, re.M | re.S):
        surface.add(mm.group(1))
        for v in re.findall(r"(\w+)", mm.group(2)):
            if not v.isdigit():
                surface.add(v)
    for mm in re.finditer(r"^\s*enum\s*\{([^}]*)\}", src, re.M | re.S):
        for v in re.findall(r"(\w+)", mm.group(1)):
            if not v.isdigit():
                surface.add(v)
    return cname, surface, src


def strip_noise(line):
    """Remove string literals and trailing comments so paths are not scanned."""
    line = re.sub(r'"[^"]*"', '""', line)
    line = re.sub(r"'[^']*'", "''", line)
    return line.split("#")[0]


def gd_files():
    out = []
    for dirpath, _dirnames, filenames in os.walk(ROOT):
        rel = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        if any(rel == d or rel.startswith(d + "/") or ("/" + d) in rel for d in SKIP_DIRS):
            continue
        for fn in filenames:
            if fn.endswith(".gd"):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)


def main():
    files = gd_files()
    classes = {}
    for path in files:
        cname, surface, _ = collect(path)
        if cname:
            classes[cname] = surface

    autoloads = {}
    proj_path = os.path.join(ROOT, "project.godot")
    with open(proj_path, encoding="utf-8") as fh:
        proj = fh.read()
    block = re.search(r"\[autoload\](.*?)(?:\n\[|\Z)", proj, re.S)
    if block:
        for mm in re.finditer(r'^(\w+)="\*?(res://[^"]+)"', block.group(1), re.M):
            p = os.path.join(ROOT, mm.group(2).replace("res://", ""))
            if os.path.exists(p):
                _, surface, _ = collect(p)
                autoloads[mm.group(1)] = surface

    targets = dict(classes)
    targets.update(autoloads)

    errors = []

    # 1. Qualified member access.
    for path in files:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        for i, raw in enumerate(src.split("\n"), 1):
            code = strip_noise(raw)
            if not code.strip():
                continue
            for mm in re.finditer(r"\b([A-Z]\w+)\.(\w+)", code):
                owner, member = mm.group(1), mm.group(2)
                if owner not in targets or member in UNIVERSAL:
                    continue
                if member in targets[owner]:
                    continue
                errors.append(
                    f"{rel}:{i}: `{owner}.{member}` does not exist on {owner}."
                )

    # 2. res:// paths referenced in code actually exist.
    for path in files:
        rel = os.path.relpath(path, ROOT)
        with open(path, encoding="utf-8") as fh:
            src = fh.read()
        for i, raw in enumerate(src.split("\n"), 1):
            for mm in re.finditer(r'"(res://[^"]+)"', raw):
                target = os.path.join(ROOT, mm.group(1).replace("res://", ""))
                if not os.path.exists(target):
                    errors.append(f"{rel}:{i}: missing resource `{mm.group(1)}`.")

    if errors:
        print(f"lint_xref: Found {len(errors)} unresolved reference(s):", file=sys.stderr)
        for e in errors:
            print(f"  [ERROR] {e}", file=sys.stderr)
        return 1

    print(
        f"lint_xref: {len(files)} scripts checked, 0 unresolved references "
        f"({len(classes)} classes, {len(autoloads)} autoloads)."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
