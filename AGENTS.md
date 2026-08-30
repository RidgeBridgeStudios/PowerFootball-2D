# AGENTS.md

Onboarding for non-Claude agents (DeepSeek, opencode, Copilot). Self-contained mirror of CLAUDE.md. No `.claude/` imports. Zero external references.

## 1. Engine Lock

**Godot 4.7-stable. GDScript 2.0 ONLY. Strictly typed.**

PROHIBITED — STRICTLY FORBIDDEN:
- NEVER yield()          → use await
- NEVER KinematicBody2D  → use CharacterBody2D
- NEVER RigidBody        → use RigidBody2D
- NEVER file.open()      → use FileAccess.open()
- NEVER dir.open()       → use DirAccess.open()

STRICT TYPING: Every var, param, return type MUST be explicitly typed.
- CORRECT:   var velocity: Vector2 = Vector2.ZERO
- INCORRECT: var velocity = Vector2.ZERO

## 2. Simulation Stack

Five-layer propagation model. Events bubble upward. Each layer feeds the next.

```
LAYER 5 — NARRATIVE      PressOffice, TouchlineBubble, WorldEvent log
                            ↑ quote generation from layers 3 & 4
LAYER 4 — CLUB WORLD     RelationshipGraph, OffPitchEventEngine, TrainingSystem
                            ↑ trust decay, dressing room events, injuries
LAYER 3 — MATCH SOCIAL   MoodSystem (SLUMP/STREAK), StarMarking, SubReactions
                            ↑ relationship-weighted passing, foul heat
LAYER 2 — MATCH AI       UtilityScorer, FormationAnchors, GK, RoleChaseBudgets
                            ↑ MatchWorldModel spatial cache, 15-frame jitter
LAYER 1 — PHYSICS        Pseudo3DBall, CharacterBody2D, CollisionLayers, SetPieces
```

Every major feature touches at least two layers. Single-layer systems are ornamental.

## 3. Critical Files

| File | Contract | Must Never Do |
|------|----------|---------------|
| autoloads/MatchWorldModel.gd | ALL spatial position reads go here. Cache of 22 players + ball. | Call get_tree().get_nodes_in_group() in _process/_physics_process |
| autoloads/GameEvents.gd | ALL inter-system events propagate via signals on this bus. | Emit signals from components; route through GameEvents only |
| autoloads/GameManager.gd | Match phase, score, clock, set pieces. Single source of truth. | Query multiple files for match state |
| entities/player/PlayerBrain.gd | Utility-scored AI. Runs on 15-frame jitter per player_index. | Allocate or scan trees inside _physics_process |
| shared/PlayerData.gd | Player attributes, traits, relationships. Persists across matches. | Mutate attributes directly; use methods only |
| shared/CollisionLayers.gd | Layer constants. CharacterBody2D masks Layer 1+2 ONLY. | Mask Layer 3 in CharacterBody2D |
| docs/course_implementation_specification.md | READ-ONLY. Course-derived build phases 1–10, FSM patterns, physics formulas, data models, known gotchas, and agent protocol. Consult before starting any new phase or implementing any system described in Sections 7–13. | Modify this file. It is a reference artifact only. |

## 4. Verification

After every .gd file write:
```bash
python3 tools/gdcheck.py
```
Do not stop until output shows `0 errors`.

## 5. Context Budget — Non-Claude Sessions

Hard limits (no `/compact` available):

| Range | State | Action |
|-------|-------|--------|
| 0–40% | OPTIMAL | Proceed normally. Multi-file work. |
| 40–60% | MONITOR | Reference by path; no full content paste. |
| 60–80% | DANGER | Finish current file only. Write Session State to AGENTS_ERRATA.md. Exit. |
| 80%+ | STOP | Write Session State to AGENTS_ERRATA.md. Do NOT write .gd files. Exit. |

Atomic rule: One session = one file + one method + one gdcheck pass.
