# research-index.md
# Consult before writing any code where implementation intent is unclear.
# Do not guess at physics values, feel parameters, or AI thresholds.
#
# POST-PIVOT NOTE: these documents predate the manager-only pivot and describe
# the archived real-time match layer under legacy/. They are retained only as
# plausibility references for shared/QuickSimEngine.gd tuning — live code has no
# player control, ball physics, per-frame AI, or formation-anchor maths.

CONTROLS / INPUT FEEL
  File: docs/research/Intuitive-Soccer-Controls-Research.txt
  When: player input → physics translation, button timing,
        action cancellation windows, analog curves

BALL + PLAYER PHYSICS
  File: docs/research/PES-6-Gameplay-Physics-Research.txt
  When: turning arc, first-touch scatter, shot trajectory,
        keeper dive, aerial duel, tackle collision response

GODOT-SPECIFIC PATTERNS
  File: docs/research/Godot-Football-Games-Research.txt
  When: CharacterBody2D approach, signal topology,
        scene composition for player nodes

2D SOCCER DESIGN
  File: docs/research/2D-Soccer-Game-Design-Guide.txt
  When: camera design, formation display, minimap, UI feedback

AI ARCHITECTURE
  File: docs/research/Godot-4-Football-AI-Overhaul-Optimization-Plan.txt
  When: utility scoring, pathfind budget, stagger frames,
        defensive shape, pressing triggers
