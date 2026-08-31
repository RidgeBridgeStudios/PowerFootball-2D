---
description: Engine API version lock and GDScript 2.0 syntax invariants
paths: ["**/*.gd"]
---
## Godot 4.7 GDScript 2.0 Invariants

STRICT TYPING: Every var, param, and return type MUST be explicitly typed.
  CORRECT:   var velocity: Vector2 = Vector2.ZERO
  INCORRECT: var velocity = Vector2.ZERO

DEPRECATED API — STRICTLY FORBIDDEN:
  NEVER yield()          -> use await
  NEVER KinematicBody2D  -> use CharacterBody2D
  NEVER RigidBody        -> use RigidBody2D
  NEVER file.open()      -> use FileAccess.open()
  NEVER dir.open()       -> use DirAccess.open()

SCENE INIT:
  Node refs  -> @onready
  Exports    -> @export with explicit type

TSCN SERIALIZATION:
  Any node created in GDScript MUST have .owner = scene_root before save
  or it will silently vanish on reload.
