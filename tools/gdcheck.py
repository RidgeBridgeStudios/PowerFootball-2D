#!/usr/bin/env python3
"""
gdcheck — static consistency checker for the PowerFootball-2D GDScript sources.

This is NOT a compiler. It is the fallback verification used in containers that
ship no Godot binary (see .claude/skills/godot-verify/SKILL.md). It parses every
.gd file in the project and reports:

  * unbalanced (), [] or {} within a file
  * mixed tab/space indentation (Godot rejects a file that mixes them)
  * forbidden Godot 3 APIs (yield, KinematicBody2D, RigidBody, file.open, ...)
  * `class_name` collisions
  * static access `SomeProjectClass.MEMBER` where MEMBER is not declared on that
    class or any project ancestor of it
  * type annotations / casts naming a class that is neither a project
    `class_name` nor a known engine type
  * `[autoload]` entries in project.godot pointing at files that do not exist,
    or at a script whose `class_name` does not match the autoload name
  * untyped `var x = ...` declarations (GDScript 2.0 strict-typing rule)

Exit status is 1 if any ERROR is reported, 0 otherwise. WARNINGs never fail.
"""

from __future__ import annotations

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Engine types the project refers to but does not declare. Anything used as a
# type annotation or cast that is neither here nor a project class_name is
# reported, which is what catches a typo'd class reference.
ENGINE_TYPES = {
    "Variant", "Object", "RefCounted", "Resource", "Node", "Node2D", "Control",
    "CanvasLayer", "CanvasItem", "CharacterBody2D", "RigidBody2D", "StaticBody2D",
    "Area2D", "CollisionShape2D", "CollisionObject2D", "Sprite2D", "Camera2D",
    "AnimatedSprite2D", "Timer", "Label", "Button", "OptionButton", "ItemList",
    "ProgressBar", "HSlider", "CheckButton", "PanelContainer", "VBoxContainer",
    "HBoxContainer", "ScrollContainer", "AcceptDialog", "ConfirmationDialog",
    "StyleBoxFlat", "PackedScene", "Tween", "Shape2D", "RectangleShape2D",
    "CircleShape2D", "KinematicCollision2D", "InputEvent", "InputEventKey",
    "InputEventJoypadButton", "InputEventJoypadMotion", "InputEventMouseButton",
    "InputEventMouse", "Viewport", "Window",
    # Control/container types used by the Manager Mode UI. All real Godot 4
    # classes; this set is a whitelist of what the project happens to name in
    # annotations, so a missing entry is a checker gap, not a code error.
    "MarginContainer", "GridContainer", "CenterContainer", "TabContainer",
    "TabBar", "BoxContainer", "Container", "FlowContainer", "HFlowContainer",
    "VFlowContainer", "SplitContainer", "HSplitContainer", "VSplitContainer",
    "HSeparator", "VSeparator", "Separator", "RichTextLabel", "LineEdit",
    "TextEdit", "TextureRect", "ColorRect", "SpinBox", "CheckBox", "Range",
    "Slider", "VSlider", "TextureButton", "LinkButton", "BaseButton",
    "ButtonGroup", "Tree", "TreeItem", "PopupMenu", "Popup", "PopupPanel",
    "TextServer", "Theme", "StyleBox", "StyleBoxEmpty", "StyleBoxTexture",
    "ScrollBar", "HScrollBar", "VScrollBar", "VBoxContainer",
    "SceneTree", "Font", "Texture2D", "Image", "Callable", "Signal", "Semaphore",
    "bool", "int", "float", "String", "StringName", "NodePath", "Vector2",
    "Vector2i", "Vector3", "Rect2", "Rect2i", "Color", "Transform2D", "Basis",
    "Quaternion", "Plane", "AABB", "Array", "Dictionary", "PackedByteArray",
    "PackedInt32Array", "PackedInt64Array", "PackedFloat32Array",
    "PackedFloat64Array", "PackedStringArray", "PackedVector2Array",
    "PackedVector3Array", "PackedColorArray", "JSON", "FileAccess", "DirAccess",
    "Input", "Time", "OS", "Engine", "ProjectSettings", "ResourceLoader",
    "ResourceSaver", "AudioServer", "DisplayServer", "RandomNumberGenerator",
    "Mutex", "Thread", "Performance", "Marker2D", "Line2D", "Polygon2D",
    "Panel", "TextureRect", "ColorRect", "GridContainer", "MarginContainer",
    "SpinBox", "LineEdit", "TextEdit", "RichTextLabel", "CheckBox",
    "TabContainer", "SubViewport", "AudioStreamPlayer", "AudioStreamPlayer2D",
    "AudioStream", "AudioStreamWAV", "AudioStreamGenerator", "AudioStreamMP3", "AudioStreamOggVorbis",
    "Material", "ShaderMaterial", "Shader", "CanvasItemMaterial",
}

# Static-access targets that are engine singletons/utility classes rather than
# project classes; member checking does not apply to them.
# Members every Object/Resource/RefCounted inherits. Static access to these is
# always legal and must not be reported as an undeclared member.
UNIVERSAL_MEMBERS = {
    "new", "instantiate", "duplicate", "get_class", "is_class", "call",
    "callv", "call_deferred", "get", "set", "has_method", "get_method_list",
    "connect", "disconnect", "emit_signal", "free", "queue_free",
    "resource_path", "get_instance_id", "reference", "unreference",
    "get_script", "set_script", "to_string", "get_property_list",
}

ENGINE_STATIC = {
    "Input", "Time", "OS", "Engine", "JSON", "FileAccess", "DirAccess",
    "ProjectSettings", "ResourceLoader", "ResourceSaver", "AudioServer",
    "DisplayServer", "Vector2", "Vector2i", "Vector3", "Color", "Rect2",
    "Transform2D", "Node", "Callable", "Performance", "TYPE", "Math",
}

FORBIDDEN = [
    (re.compile(r"\byield\s*\("), "yield() is Godot 3 — use await"),
    (re.compile(r"\bKinematicBody2D\b"), "KinematicBody2D is Godot 3 — use CharacterBody2D"),
    (re.compile(r"\bRigidBody\b(?!2D|3D)"), "RigidBody is Godot 3 — use RigidBody2D"),
    (re.compile(r"\bFile\s*\.\s*new\s*\("), "File.new() is Godot 3 — use FileAccess.open()"),
    (re.compile(r"\bDirectory\s*\.\s*new\s*\("), "Directory.new() is Godot 3 — use DirAccess.open()"),
    (re.compile(r"\bOS\s*\.\s*get_ticks_msec\s*\(\s*\)\s*/\s*1000\b"), "prefer Time.get_ticks_msec()"),
    (re.compile(r"(?<!@)\bexport\s*\("), "export(...) is Godot 3 — use @export"),
    (re.compile(r"(?<!@)\bonready\s+var\b"), "onready is Godot 3 — use @onready"),
    (re.compile(r"\bsetget\b"), "setget is Godot 3 — use GDScript 2.0 'get:' and 'set:' property syntax"),
    (re.compile(r"\bNone\b"), "Python 'None' is invalid in GDScript — use 'null'"),
    (re.compile(r"\bTrue\b"), "Python 'True' is invalid in GDScript — use 'true'"),
    (re.compile(r"\bFalse\b"), "Python 'False' is invalid in GDScript — use 'false'"),
    (re.compile(r"\bdef\s+[A-Za-z0-9_]+\s*\("), "Python 'def' is invalid in GDScript — use 'func'"),
    (re.compile(r"\bisinstance\s*\("), "Python 'isinstance()' is invalid in GDScript — use 'is' operator"),
    (re.compile(r"\blen\s*\("), "Python 'len()' is invalid in GDScript — use '.size()' on arrays/dicts or '.length()' on strings"),
    (re.compile(r"^\s*(?:from\s+[A-Za-z0-9_.]+\s+import\b|import\s+[A-Za-z0-9_.]+\b)"), "Python 'import' statement is invalid in GDScript — use 'preload()' or global class names"),
]

STRING_RE = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')
IDENT = r"[A-Za-z_][A-Za-z0-9_]*"


class Problem:
    def __init__(self, level: str, path: str, line: int, message: str) -> None:
        self.level = level
        self.path = path
        self.line = line
        self.message = message

    def __str__(self) -> str:
        rel = os.path.relpath(self.path, ROOT)
        return "%-7s %s:%d  %s" % (self.level, rel, self.line, self.message)


def strip_code(line: str) -> str:
    """Remove string literals and trailing comments so regexes see code only."""
    line = STRING_RE.sub('""', line)
    hash_at = line.find("#")
    if hash_at >= 0:
        line = line[:hash_at]
    return line


def gd_files() -> list[str]:
    out = []
    # "autoload" (singular) is the godot-bridge MCP interaction server injected by the
    # editor tooling at runtime; this project's own autoloads live in "autoloads".
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in (".git", "addons", ".claude", "legacy", "autoload")]
        for name in filenames:
            if name.endswith(".gd"):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


class ScriptInfo:
    def __init__(self, path: str) -> None:
        self.path = path
        self.class_name: str | None = None
        self.extends: str | None = None
        self.members: set[str] = set()
        self.inner_classes: set[str] = set()


def parse(path: str, text: str, problems: list[Problem]) -> ScriptInfo:
    info = ScriptInfo(path)
    lines = text.split("\n")

    depth = 0
    indent_style: str | None = None

    for idx, raw in enumerate(lines, start=1):
        code = strip_code(raw)

        # Indentation: Godot rejects a file mixing tabs and spaces.
        stripped = raw.lstrip()
        if stripped and raw[0] in " \t":
            lead = raw[: len(raw) - len(stripped)]
            style = "tab" if "\t" in lead else "space"
            if "\t" in lead and " " in lead:
                problems.append(Problem("ERROR", path, idx, "indent mixes tabs and spaces"))
            elif indent_style is None:
                indent_style = style
            elif style != indent_style:
                problems.append(
                    Problem("ERROR", path, idx,
                            "indent style %s conflicts with file style %s" % (style, indent_style)))

        depth += code.count("(") + code.count("[") + code.count("{")
        depth -= code.count(")") + code.count("]") + code.count("}")
        if depth < 0:
            problems.append(Problem("ERROR", path, idx, "unbalanced closing bracket"))
            depth = 0

        for pattern, message in FORBIDDEN:
            if pattern.search(code):
                problems.append(Problem("ERROR", path, idx, "forbidden API: " + message))

        m = re.match(r"\s*class_name\s+(%s)" % IDENT, code)
        if m:
            info.class_name = m.group(1)
            continue

        m = re.match(r"\s*extends\s+(%s)" % IDENT, code)
        if m and info.extends is None and not raw.startswith((" ", "\t")):
            info.extends = m.group(1)
            continue

        # Top-level members only (column 0) — locals and inner-class fields are
        # not part of the class's static surface.
        top = not raw.startswith((" ", "\t"))

        m = re.match(r"(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?func\s+(%s)" % IDENT, code.strip())
        if m and top:
            info.members.add(m.group(1))
            continue

        m = re.match(r"(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?var\s+(%s)" % IDENT, code.strip())
        if m and top:
            info.members.add(m.group(1))
            # Strict typing: `var x = ...` with no `:` type and no `:=` infer.
            decl = code.strip()
            after = decl.split(m.group(1), 1)[1]
            if after.lstrip().startswith("=") and not after.lstrip().startswith("=="):
                problems.append(
                    Problem("WARN", path, idx,
                            "untyped declaration `var %s = ...` — annotate the type" % m.group(1)))
            continue

        m = re.match(r"const\s+(%s)" % IDENT, code.strip())
        if m and top:
            info.members.add(m.group(1))
            if ":" not in code.split("=", 1)[0]:
                problems.append(
                    Problem("WARN", path, idx,
                            "untyped constant `const %s` — annotate the type" % m.group(1)))
            continue

        m = re.match(r"signal\s+(%s)" % IDENT, code.strip())
        if m and top:
            info.members.add(m.group(1))
            continue

        m = re.match(r"enum\s+(%s)?\s*\{(.*)" % IDENT, code.strip())
        if m and top:
            if m.group(1):
                info.members.add(m.group(1))
            else:
                for part in re.findall(IDENT, m.group(2)):
                    info.members.add(part)
            continue

        m = re.match(r"class\s+(%s)" % IDENT, code.strip())
        if m and top:
            info.members.add(m.group(1))
            info.inner_classes.add(m.group(1))
            continue

    if depth != 0:
        problems.append(Problem("ERROR", path, len(lines), "unbalanced brackets at end of file (%+d)" % depth))

    return info


def parse_autoload_entries(problems: list[Problem]) -> list[tuple[str, int, str]]:
    """Reads the [autoload] section of project.godot: (name, line, relative path)."""
    project = os.path.join(ROOT, "project.godot")
    if not os.path.exists(project):
        return []
    with open(project, encoding="utf-8") as handle:
        lines = handle.read().split("\n")

    entries: list[tuple[str, int, str]] = []
    in_section = False
    for idx, raw in enumerate(lines, start=1):
        line = raw.strip()
        if line.startswith("["):
            in_section = line == "[autoload]"
            continue
        if not in_section or not line or line.startswith(";"):
            continue
        m = re.match(r'(%s)\s*=\s*"\*?res://(.+)"' % IDENT, line)
        if not m:
            problems.append(Problem("ERROR", project, idx, "malformed autoload entry: " + line))
            continue
        entries.append((m.group(1), idx, m.group(2)))
    return entries


def check_static_access(
    scripts: dict[str, ScriptInfo], problems: list[Problem], autoload_names: set[str]
) -> None:
    by_name = {s.class_name: s for s in scripts.values() if s.class_name}

    def members_of(name: str, seen: set[str]) -> set[str]:
        if name in seen or name not in by_name:
            return set()
        seen.add(name)
        info = by_name[name]
        out = set(info.members)
        if info.extends:
            out |= members_of(info.extends, seen)
        return out

    access_re = re.compile(r"\b(%s)\s*\.\s*(%s)" % (IDENT, IDENT))
    type_re = re.compile(r"(?::\s*|\bas\s+|->\s*)(%s)" % IDENT)

    for path, info in scripts.items():
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().split("\n")
        for idx, raw in enumerate(lines, start=1):
            code = strip_code(raw)

            for cls, member in access_re.findall(code):
                if cls in ENGINE_STATIC or cls not in by_name:
                    continue
                # An instance variable can shadow a class name only if it is
                # lowercase; project class_names are PascalCase by convention.
                if not cls[0].isupper():
                    continue
                if member in UNIVERSAL_MEMBERS:
                    continue
                allowed = members_of(cls, set())
                if member not in allowed:
                    problems.append(
                        Problem("ERROR", path, idx,
                                "%s.%s — `%s` is not declared on %s" % (cls, member, member, cls)))

            for typename in type_re.findall(code):
                if typename in ENGINE_TYPES or typename in by_name:
                    continue
                if typename in autoload_names:
                    continue
                if typename in info.inner_classes or typename in info.members:
                    continue
                if not typename[0].isupper():
                    continue
                problems.append(
                    Problem("ERROR", path, idx,
                            "unknown type `%s` — no class_name and not an engine type" % typename))


def check_autoloads(
    scripts: dict[str, ScriptInfo], problems: list[Problem], entries: list[tuple[str, int, str]]
) -> None:
    project = os.path.join(ROOT, "project.godot")

    order: list[str] = []
    for name, idx, rel in entries:
        order.append(name)
        target = os.path.join(ROOT, rel)
        if not os.path.exists(target):
            problems.append(Problem("ERROR", project, idx, "autoload %s points at missing %s" % (name, rel)))
            continue
        info = scripts.get(os.path.abspath(target))
        if info and info.class_name and info.class_name != name:
            problems.append(
                Problem("WARN", project, idx,
                        "autoload %s declares class_name %s" % (name, info.class_name)))

    # Boot-order invariant, post manager-only pivot. MatchWorldModel (the old
    # first autoload) was archived with the real-time match layer, so the signal
    # bus now boots first. The loader/WorldEventLog/CareerManager ordering is the
    # constraint that actually matters: WorldEventLog and CareerManager must stay
    # AFTER the loaders, and WorldEventLog before CareerManager.
    if order and order[0] != "GameEvents":
        problems.append(
            Problem("ERROR", project, 1,
                    "GameEvents must be the FIRST autoload; found %s" % order[0]))

    def _precedes(earlier: str, later: str) -> bool:
        if earlier not in order or later not in order:
            return True  # absent autoloads are reported elsewhere, not here
        return order.index(earlier) < order.index(later)

    for loader in ("DataLoader", "RefereeLoader", "ManagerLoader", "StaffLoader"):
        if not _precedes(loader, "WorldEventLog"):
            problems.append(
                Problem("ERROR", project, 1,
                        "%s must precede WorldEventLog in [autoload]" % loader))
        if not _precedes(loader, "CareerManager"):
            problems.append(
                Problem("ERROR", project, 1,
                        "%s must precede CareerManager in [autoload]" % loader))
    if not _precedes("WorldEventLog", "CareerManager"):
        problems.append(
            Problem("ERROR", project, 1,
                    "WorldEventLog must precede CareerManager in [autoload]"))


def main() -> int:
    problems: list[Problem] = []
    scripts: dict[str, ScriptInfo] = {}

    for path in gd_files():
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        scripts[os.path.abspath(path)] = parse(path, text, problems)

    seen: dict[str, str] = {}
    for path, info in scripts.items():
        if not info.class_name:
            continue
        if info.class_name in seen:
            problems.append(
                Problem("ERROR", path, 1,
                        "class_name %s already declared in %s"
                        % (info.class_name, os.path.relpath(seen[info.class_name], ROOT))))
        seen[info.class_name] = path

    autoload_entries = parse_autoload_entries(problems)
    autoload_names = {name for name, _idx, _rel in autoload_entries}

    check_static_access(scripts, problems, autoload_names)
    check_autoloads(scripts, problems, autoload_entries)

    errors = [p for p in problems if p.level == "ERROR"]
    warns = [p for p in problems if p.level == "WARN"]

    for problem in errors:
        print(problem)
    for problem in warns:
        print(problem)

    print("")
    print("gdcheck: %d scripts, %d errors, %d warnings" % (len(scripts), len(errors), len(warns)))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
