# Graph Report - sim-tuning-calibration  (2026-09-08)

## Corpus Check
- 151 files · ~324,567 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1551 nodes · 1791 edges · 135 communities (96 shown, 30 thin omitted)
- Extraction: 94% EXTRACTED · 6% INFERRED · 0% AMBIGUOUS · INFERRED: 101 edges (avg confidence: 0.92)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e07e79d2`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Api Surface
- graphify
- Course Implementation Specification
- Anti Patterns
- Agents Errata
- Powerfootball Master Vision
- mcp_server.py
- Team Flag Textures
- Update
- Vector2
- Claude
- Json Schema
- gdcheck.py
- Core Invariants
- lint_invariants.py
- Math Solvers
- Readme
- Agents
- Readme
- Readme
- semantic_search.py
- Readme
- Readme
- Readme
- Ai Architect
- Readme
- Graphify Lifecycle & Agent Navigation Protocol — PowerFootball-2D
- run_update
- lint_scope.py
- SpatialGrid
- Query
- Readme
- Context Hygiene
- fuzz_utility_scorer.py
- test_quick_sim.py
- SchemaViolation
- Exports
- Github And Merge
- 2. Public API, Signals, Events, Contracts & Dependencies
- lint_type_comparisons.py
- DeterministicMatchSimulator
- Soccer Physics
- Readme
- The 10-Step Mandatory Protocol
- worktree_manager.py
- Gdscript Antipatterns
- Gdscript Antipatterns
- Compounded corrections — verified against the source
- graphify
- 2. Public API, Signals, Events, Contracts & Dependencies
- lint_shadowing.py
- graphify
- eval-sim
- formation-audit
- perf-benchmark
- graphify
- Scratchpad
- eval-sim
- formation-audit
- perf-benchmark
- Transcribe
- expand_database.py
- formation_ascii.py
- ast-refactor
- formation-fuzzer
- ast-refactor
- formation-fuzzer
- Research Index
- Add Watch
- dump_match_frames.py
- git_pre_commit.py
- hook_gdcheck.py
- layer_context.py
- lint_allocations.py
- lint_stringnames.py
- audit_process_modes.py
- lint_signal_races.py
- 2. Public API, Signals, Events, Contracts & Dependencies
- Ai Architect
- Godot 47 Core
- Graphify
- Research Index
- Soccer Physics
- graphify
- Claude
- Extraction Spec
- Godot 4 Football Ai Overhaul Optimization Plan
- Ball
- Ball Classic Texture
- Logo
- Player
- Shadow
- Studio Logo
- Turf
- 2D Soccer Game Design Guide
- Godot Football Games Research
- Intuitive Soccer Controls Research
- Pes 6 Gameplay Physics Research
- generate_symbols.py
- 2. Public API, Signals, Events, Contracts & Dependencies
- Architecture Hub: PitchScene
- Architecture Hub: SetPieceCoordinator
- Player AI & Spatial Navigation Errata
- benchmark_math.py
- The 10-Step Mandatory Protocol
- AnalyticalSimulationHarness
- verify_gate.py
- Roadmap
- Set Pieces & Restarts Errata
- Match State, Pacing & Urgency Errata
- Physics, Ball Dynamics & Kinematics Errata
- Complete Item Migration Manifest
- UI, HUD & Signal Bus Errata
- Scene Tree, Node Hierarchy & Cross-Referencing Errata
- session-history.md
- README.md
- compact_errata.py
- dump_api.py
- Workflow: cross-system-feature
- sync_rules.py
- Workflow: bug-investigation
- Workflow: data-database
- Workflow: feature-implementation
- Workflow: performance-work
- Workflow: session-bootstrap
- Workflow: task-intake-routing

## God Nodes (most connected - your core abstractions)
1. `Api Surface` - 151 edges
2. `graphify` - 80 edges
3. `Course Implementation Specification` - 69 edges
4. `Agents Errata` - 60 edges
5. `Anti Patterns` - 50 edges
6. `Agents` - 40 edges
7. `Powerfootball Master Vision` - 39 edges
8. `Team Flag Textures` - 35 edges
9. `Update` - 35 edges
10. `Readme` - 29 edges

## Surprising Connections (you probably didn't know these)
- `Agents` --references--> `Api Surface`  [INFERRED]
  AGENTS.md → docs/API_SURFACE.md
- `Llms` --references--> `Api Surface`  [INFERRED]
  llms.txt → docs/API_SURFACE.md
- `Readme` --references--> `Api Surface`  [INFERRED]
  tools/README.md → docs/API_SURFACE.md
- `Claude` --references--> `Agents Errata`  [INFERRED]
  CLAUDE.md → AGENTS_ERRATA.md
- `Claude` --references--> `Core Invariants`  [INFERRED]
  CLAUDE.md → docs/CORE_INVARIANTS.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Gdscript Antipatterns Concepts** — agents_rules_gdscript_antipatterns_gdscript_20_antipatterns___postmortem_sa, agents_rules_gdscript_antipatterns_1_object_vs_literal_equality_comparisons, agents_rules_gdscript_antipatterns_2_function_scope___duplicate_declaration, agents_rules_gdscript_antipatterns_3_hotpath_zeroallocation_discipline, agents_rules_gdscript_antipatterns_4_distance_calculation_discipline [INFERRED 0.85]
- **ast-refactor Concepts** — agents_skills_ast_refactor_skill_ast_refactor___invariant_preservation_sk, agents_skills_ast_refactor_skill_strict_refactoring_rules, agents_skills_ast_refactor_skill_verification_loop [INFERRED 0.85]
- **eval-sim Concepts** — agents_skills_eval_sim_skill_headless_simulation_evaluation_skill, agents_skills_eval_sim_skill_execution_command, agents_skills_eval_sim_skill_assertion_thresholds___failure_criteria, agents_skills_eval_sim_skill_postrun_actions [INFERRED 0.85]
- **Context Hygiene Concepts** — claude_rules_context_hygiene_context_hygiene, claude_rules_context_hygiene_prohibited, claude_rules_context_hygiene_wrong___pastes_200_lines_of_find_output, claude_rules_context_hygiene_correct___pasted_summary, claude_rules_context_hygiene_tool_output_rule [INFERRED 0.85]
- **Gdscript Antipatterns Concepts** — claude_rules_gdscript_antipatterns_gdscript_20_antipatterns___postmortem_sa, claude_rules_gdscript_antipatterns_1_object_vs_literal_equality_comparisons, claude_rules_gdscript_antipatterns_2_function_scope___duplicate_declaration, claude_rules_gdscript_antipatterns_3_hotpath_zeroallocation_discipline, claude_rules_gdscript_antipatterns_4_distance_calculation_discipline [INFERRED 0.85]
- **Godot 47 Core Concepts** — claude_rules_godot_47_core_godot_47_gdscript_20_invariants, claude_rules_godot_47_core_compounded_corrections___verified_agains, claude_rules_godot_47_core_managerloader_emits_no_formation_signal, claude_rules_godot_47_core_entities_manager_managerdirectorgd___shi, claude_rules_godot_47_core_deprecated__export___unused_export [INFERRED 0.85]
- **Anti Patterns Concepts** — docs_anti_patterns_antipatternsmd___antihallucination___arc, docs_anti_patterns_1_complete_godot_47___gdscript_20_pitfal, docs_anti_patterns_2_engine___gdscript_20_syntax_antipatter, docs_anti_patterns_3_strict_type_system___autoload_invarian, docs_anti_patterns_antipattern_31__untyped_declarations [INFERRED 0.85]
- **Api Surface Concepts** — docs_api_surface_powerfootball2d___public_api_surface_map, docs_api_surface_table_of_contents, docs_api_surface_layer_1___physics___kinematics, docs_api_surface_entities_ball_ballstategd, docs_api_surface_entities_ball_ballstatefactorygd [INFERRED 0.85]
- **Core Invariants Concepts** — docs_core_invariants_coreinvariantsmd___powerfootball2d_archi, docs_core_invariants_1_engine_lock, docs_core_invariants_prohibited___strictly_forbidden_apis, docs_core_invariants_strict_typing_invariant, docs_core_invariants_scene_initialization___serialization [INFERRED 0.85]

## Communities (135 total, 30 thin omitted)

### Community 0 - "Api Surface"
Cohesion: 0.01
Nodes (148): Api Surface, autoloads/CareerManagergd, autoloads/DataLoadergd, autoloads/GameEventsgd, autoloads/GameManagergd, autoloads/InputHelpergd, autoloads/ManagerLoadergd, autoloads/MatchStatsTrackergd (+140 more)

### Community 1 - "graphify"
Cohesion: 0.02
Nodes (81): graphify, a detected file whose chunk failed or was omitted must stay unstamped so the, a stale semantichash from a prior run; clear it so detectincremental requeues, Always rewrite the cache file: write hits else DELETE any leftover from a prior, base so the full build and incremental update never drift apart on reextract, by the AST pass Part A; flattening every category here makes subagents reread, clistampedmanifestfiles  clearsemantic  scancorpus; do not stamp the, deletions; untouched files' prior rows are still preserved 1908 (+73 more)

### Community 2 - "Course Implementation Specification"
Cohesion: 0.03
Nodes (64): Course Implementation Specification, 10 Main Algorithms and Business Rules, 11 Setup and Build Instructions, 12 Implementation Phases, 13 Detailed Requirements by Phase, 14 Known Constraints Gotchas & Errata, 15 AI Agent Protocol, 1 Course Objective (+56 more)

### Community 3 - "Anti Patterns"
Cohesion: 0.04
Nodes (50): Anti Patterns, 1 Complete Godot 47 / GDScript 20 Pitfall Matrix, 2 Engine & GDScript 20 Syntax AntiPatterns, 3 Strict Type System & Autoload Invariants, 4 FiveLayer Simulation Stack & Choke Point Invariants, 5 Physics & Collision Matrix AntiPatterns, 6 AI Tactical & Spatial Logic AntiPatterns, AntiPattern 31: Untyped Declarations (+42 more)

### Community 4 - "Agents Errata"
Cohesion: 0.05
Nodes (40): Agents Errata, affectedfiles:, agent: string, AGENTSERRATAmd, Calibration is not optional and the first guess was wrong twice, category: engine | physics | ai | social | data | architecture, date: YYYYMMDD, Discovered Rules (+32 more)

### Community 5 - "Powerfootball Master Vision"
Cohesion: 0.05
Nodes (42): Powerfootball Master Vision, Aerial Contact Personality Weighting Future Refinement, Context Hygiene, Deep Simulation Gaps, Design References, "Dwarf Fortress with a football" Simple visuals; deep social simulation, Error Compounding, Feature Development Loop (+34 more)

### Community 6 - "mcp_server.py"
Cohesion: 0.12
Nodes (30): list_symbols_in_file(), load_file_lines(), main(), slice_class_header(), slice_enum(), slice_function(), slice_signals(), calculate_blast_radius() (+22 more)

### Community 7 - "Team Flag Textures"
Cohesion: 0.06
Nodes (36): Argentina Flag, Argentine Flag, Austria Flag, Batavian Flag, Belgium Flag, Brasilian Flag, Brazil Flag, Britannic Flag (+28 more)

### Community 8 - "Update"
Cohesion: 0.06
Nodes (36): Update, are dropped rather than masquerading as deletions; untouched rows preserved 1908, as the freshly merged nodes and would DELETE the reextracted content 1178 is moot, cached files instead of missing every one after a move 1417, Changed semantic files dispatched this run but NOT stamped had their chunk fail, clistampedmanifestfiles  clearsemantic  scancorpus, directed=ISDIRECTED: replace ISDIRECTED with True if directed was given else, Do NOT add changed here: with root= passed pruneset relativizes to the same base (+28 more)

### Community 9 - "Vector2"
Cohesion: 0.13
Nodes (19): ballistic_trajectory_z(), calculate_intercept_point(), calculate_packing(), calculate_psxg(), calculate_vaep_value(), calculate_xg(), calculate_xg_logit(), clampf() (+11 more)

### Community 10 - "Claude"
Cohesion: 0.07
Nodes (31): Claude, Architectural Choke Points, Boot Order projectgodot, CLAUDEmd — Agent Entry Point, Context Budget — Claude Code Sessions, graphify, Process Priority, READ FIRST (+23 more)

### Community 11 - "Json Schema"
Cohesion: 0.07
Nodes (28): Json Schema, Biography PLANNED, Complete Manager Example, Complete Player Example, Complete Team Example, Contract Data PLANNED, DataLoader IMPLEMENTED, Decision Attributes IMPLEMENTED (+20 more)

### Community 12 - "gdcheck.py"
Cohesion: 0.12
Nodes (23): Godot 47 Core, Compounded corrections — verified against the source, "Deprecated" export ≠ unused export, entities/manager/ManagerDirectorgd — shiftto, gdcheck resolves autoload singleton names as types — never "fix" this by adding classname, Godot 47 GDScript 20 Invariants, ManagerLoader emits NO formation signal — ManagerDirector does, new is inherited not declared (+15 more)

### Community 13 - "Core Invariants"
Cohesion: 0.07
Nodes (27): Core Invariants, 1 Engine Lock, 2 Simulation Stack, 3 Critical File Contracts Choke Points, 4 Physics & Spatial AI Invariants, 5 Static Verification & Autoload Handling, Autoload Handling Contract, COREINVARIANTSmd — PowerFootball2D Architectural & Engine Invariants (+19 more)

### Community 14 - "lint_invariants.py"
Cohesion: 0.15
Nodes (17): check_brain_mutations(), check_choke_point_bypass(), check_collision_matrix_gd(), check_collision_matrix_tscn(), check_hot_path_allocations(), format_xml_output(), get_all_gd_files(), get_all_tscn_files() (+9 more)

### Community 15 - "Math Solvers"
Cohesion: 0.13
Nodes (15): Math Solvers, 1 Kinematic PointtoSegment Projection & Distance, 1 Quadratic Distance Utility Decay, 2 Angular Cosine Alignment, 2 Kinematic Turning Penalty & Acceleration Curve, 3 Ballistic Pseudo3D Flight & Height Trajectory, 3 Receiver Openness, 4 Bisection RootFinding Ball Intercept Algorithm (+7 more)

### Community 16 - "Readme"
Cohesion: 0.11
Nodes (19): Errata History, Errata History Archive, Readme, 10 layercontextpy, 11 mcpserverpy & lspclientpy, 12 worktreemanagerpy, 13 syncrulespy & compacterratapy, 14 hookgdcheckpy (+11 more)

### Community 17 - "Agents"
Cohesion: 0.13
Nodes (14): Agents, 1 Core Architecture & Invariants, 2 Verification & Static Analysis, 3 Developer Tooling & Slash Commands, 4 Gemini Context Protocol & Antigravity Autonomy, AGENTSmd, Atomic Feature Discipline, Autoload Handling Contract (+6 more)

### Community 18 - "Readme"
Cohesion: 0.12
Nodes (16): Readme, Architecture Overview, Ball State Machine, CORRECT — passes deceleration in px/s² not bare coefficient, DeadBallState &"DeadBall", entities/ball/ — Ball Physics & Possession State, FlightState &"Flight", Foot Sensor Layer 4 & Aerial Hitbox Layer 5 (+8 more)

### Community 19 - "Readme"
Cohesion: 0.14
Nodes (14): Readme, Architecture Overview, Camera Systems MatchCameragd, HUD Rendering Contract, HUDgd MatchHUD, Key Scenes, MainMenutscn, MatchStatsUItscn (+6 more)

### Community 20 - "semantic_search.py"
Cohesion: 0.29
Nodes (9): Context Hygiene, Context Hygiene & Token Discipline, BM25Index, build_corpus(), chunk_gdscript_docstrings(), chunk_markdown_file(), DocumentChunk, main() (+1 more)

### Community 21 - "Readme"
Cohesion: 0.15
Nodes (13): Readme, Adding a New Autoload, autoloads/ — Singletons & Global Services, Boot Order projectgodot, DataLoadergd, GameEventsgd, GameManagergd, InputHelpergd (+5 more)

### Community 22 - "Readme"
Cohesion: 0.15
Nodes (13): Readme, Architecture Overview, Collision Invariants, GoalZonegd per goal, Key Scenes & Systems, Minimapgd, Notes, pitch/ — Field Boundaries & Scoring Zones (+5 more)

### Community 23 - "Readme"
Cohesion: 0.15
Nodes (13): Readme, CollisionLayersgd, Data Models, FormationAnchorMathgd, ManagerDatagd, PassUtilityScorergd, PlayerDatagd, PlayerRoleConfiggd (+5 more)

### Community 24 - "Ai Architect"
Cohesion: 0.17
Nodes (12): Ai Architect, A shared scratch buffer must have exactly one live call site, AI & Spatial Decision Invariants, Child ready runs BEFORE parent ready, Compounded corrections — verified against the source, Defensive line depth is computed ONCE in MatchWorldModel never perdefender, GameEventsgoalscored carries no scorer by default — check the source not the READMEs, Group scans that must NOT be routed through MatchWorldModel (+4 more)

### Community 25 - "Readme"
Cohesion: 0.17
Nodes (12): Readme, Architecture Overview, CORRECT, entities/player/ — Player Controller & Brain, HeavyPlayerControllergd, INCORRECT — scene tree polling, Key Spatial Queries DO NOT VIOLATE, Notes (+4 more)

### Community 26 - "Graphify Lifecycle & Agent Navigation Protocol — PowerFootball-2D"
Cohesion: 0.15
Nodes (12): 1.1. Initial Build, 1.2. Normal Update (Incremental Sync), 1.3. Update After Source Changes (Verification Battery), 1.4. Update After Git Operations (Hooks & Merge Driver), 1. Project-Local Graphify Lifecycle, 2.1. When Graphify MUST Be Queried, 2.2. Important Scope Clarification, 2. Agent Navigation Protocol (Claude Code & Antigravity) (+4 more)

### Community 27 - "run_update"
Cohesion: 0.29
Nodes (8): build_player(), generate_league(), main(), get_club_staff(), get_free_agent_staff(), make_player_dob(), make_player_languages(), run_update()

### Community 28 - "lint_scope.py"
Cohesion: 0.32
Nodes (9): count_bracket_delta(), format_xml_output(), get_all_gd_files(), get_line_indent(), lint_file_scope(), main(), run_scope_linter(), ScopeViolation (+1 more)

### Community 29 - "SpatialGrid"
Cohesion: 0.26
Nodes (6): benchmark_grid(), benchmark_linear_scan(), generate_match_positions(), main(), run_spatial_benchmark(), SpatialGrid

### Community 30 - "Query"
Cohesion: 0.18
Nodes (11): Query, Find best matching node, Find bestmatching start nodes, For /graphify explain, For /graphify path, graphify reference: query path explain, or: graphify query "QUESTION" dfs budget 3000, Score each node by term overlap for ranked output (+3 more)

### Community 31 - "Readme"
Cohesion: 0.18
Nodes (11): Readme, 1 MatchRefereegd, 2 MatchOfficialCrewgd, 3 CenterRefereeVisualgd, 4 AssistantRefereeVisualgd Linesmen AR1 & AR2, 5 FourthOfficialVisualgd, 6 WhistleSynthesizergd, Architecture Overview (+3 more)

### Community 32 - "Context Hygiene"
Cohesion: 0.20
Nodes (10): Context Hygiene, Context Budget Tracking, Context Hygiene, CORRECT — pasted summary, PreLoad Rule, PROHIBITED, Scope Rule, Session State: date model (+2 more)

### Community 33 - "fuzz_utility_scorer.py"
Cohesion: 0.51
Nodes (8): clampf(), quadratic_decay(), run_fuzz_tests(), score_dribble(), score_pass(), score_pass_action(), score_shoot(), UtilityContext

### Community 34 - "test_quick_sim.py"
Cohesion: 0.40
Nodes (9): compute_analytical_probs(), dixon_coles_tau(), main(), poisson_pmf(), test_home_advantage(), test_player_rating_formula(), test_probability_distribution(), test_referee_strictness() (+1 more)

### Community 35 - "SchemaViolation"
Cohesion: 0.42
Nodes (7): format_xml_output(), main(), run_all_schema_validations(), SchemaViolation, validate_league_schema(), validate_managers_schema(), validate_referees_schema()

### Community 36 - "Exports"
Cohesion: 0.22
Nodes (9): Exports, graphify reference: extra exports and benchmark, Step 6b  Wiki only if wiki flag, Step 7  Neo4j export only if neo4j or neo4jpush flag, Step 7a  FalkorDB export only if falkordb or falkordbpush flag, Step 7b  SVG export only if svg flag, Step 7c  GraphML export only if graphml flag, Step 7d  MCP server only if mcp flag (+1 more)

### Community 37 - "Github And Merge"
Cohesion: 0.22
Nodes (9): Github And Merge, Add backend gemini|kimi|openai|deepseek|claudecli depending on which API key you have set, Clone each repo run the full pipeline on each then merge, graphify reference: GitHub clone and crossrepo merge, Run /graphify on each local path to produce their graphjson files, Step 0  Clone GitHub repos only if a GitHub URL was given, Then merge:, Then merge at the project root: (+1 more)

### Community 38 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.11
Nodes (18): 1. Purpose and Non-Responsibilities, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: CareerManager, Career-to-Match Morale Seeding Invariant (+10 more)

### Community 39 - "lint_type_comparisons.py"
Cohesion: 0.42
Nodes (6): ComparisonViolation, format_xml_output(), get_all_gd_files(), lint_file_comparisons(), main(), run_comparison_linter()

### Community 40 - "DeterministicMatchSimulator"
Cohesion: 0.28
Nodes (5): DeterministicMatchSimulator, main(), Packs the complete simulation state into binary representation for exact…, 60Hz Headless Match Physics & AI Simulator with PRNG seeding., run_simulation()

### Community 41 - "Soccer Physics"
Cohesion: 0.25
Nodes (8): Soccer Physics, Ball friction is PROPORTIONAL not a constant deceleration, Compounded corrections — verified against the source, FEEL pass proportional friction / gaussian scatter, PowerFootball2d Physics Invariants, Pseudo3DBallpredicttrajectory returns RENDER points not ground points, Pseudo3DBallsimulatexyaxis, The ball has TWO ownership properties and they mean different things

### Community 42 - "Readme"
Cohesion: 0.25
Nodes (8): Readme, Architecture Overview, entities/manager/ — Manager AI & Formations, Manager Data Schema, ManagerDirectorgd, ManagerLoadergd autoload, Notes, PressOfficegd

### Community 43 - "The 10-Step Mandatory Protocol"
Cohesion: 0.14
Nodes (13): Cross-System Gameplay Feature Workflow, Invocation in Antigravity, Step 10: Final Verification Report, Step 1: Restate Requested Outcome and Non-Goals, Step 2: Classify Change-Impact Tier, Step 3: Graphify Impact Query Before Reading Broad Source Files, Step 4: Reading Only Relevant Module READMEs, Hub Maps, and Targeted Files, Step 5: Short Written Implementation Plan (+5 more)

### Community 44 - "worktree_manager.py"
Cohesion: 0.68
Nodes (7): cmd_cleanup(), cmd_create(), cmd_list(), cmd_merge(), cmd_verify(), main(), run_cmd()

### Community 45 - "Gdscript Antipatterns"
Cohesion: 0.29
Nodes (7): Gdscript Antipatterns, 1 Object vs Literal Equality Comparisons, 2 Function Scope & Duplicate Declaration Rules, 3 HotPath ZeroAllocation Discipline, 4 Distance Calculation Discipline, 5 StringName Literal Discipline, GDScript 20 AntiPatterns & Postmortem Safeguards

### Community 46 - "Gdscript Antipatterns"
Cohesion: 0.29
Nodes (7): Gdscript Antipatterns, 1 Object vs Literal Equality Comparisons, 2 Function Scope & Duplicate Declaration Rules, 3 HotPath ZeroAllocation Discipline, 4 Distance Calculation Discipline, 5 StringName Literal Discipline, GDScript 20 AntiPatterns & Postmortem Safeguards

### Community 47 - "Compounded corrections — verified against the source"
Cohesion: 0.18
Nodes (10): Career Mode (Layer 4) Invariants, Compounded corrections — verified against the source, gdcheck cannot see through autoloads — use lint_xref, Inbox options are deliberately NOT serialised, Match side is NOT the league team index, squad_index IS the identity, so removing a player renumbers everyone behind them, The career -> match bridge runs through PlayerFactory, once per player per bind, The season calendar is derived, never a fixed weekly rhythm (+2 more)

### Community 48 - "graphify"
Cohesion: 0.40
Nodes (4): Enforcement & Git Hooks, graphify, Non-Destructive Validation Checklist, Strict Context & Token Optimization Rules

### Community 49 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.11
Nodes (18): 1. Purpose and Non-Responsibilities, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: HeavyPlayerController, Brain / Controller Choke Point (+10 more)

### Community 50 - "lint_shadowing.py"
Cohesion: 0.48
Nodes (6): audit_file_shadowing(), find_gd_files(), get_autoload_names(), main(), parse_function_params(), Parses comma-separated parameter declarations into (param_name,…

### Community 51 - "graphify"
Cohesion: 0.38
Nodes (6): PYTHONIOENCODING, PYTHONUNBUFFERED, C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe, python, graphify, powerfootball

### Community 52 - "eval-sim"
Cohesion: 0.40
Nodes (5): eval-sim, Assertion Thresholds & Failure Criteria, Execution Command, Headless Simulation Evaluation Skill, PostRun Actions

### Community 53 - "formation-audit"
Cohesion: 0.40
Nodes (5): formation-audit, Evaluated Spacing Metrics, Execution Command, Formation & Tactical Spacing Audit Skill, Supported Formations

### Community 54 - "perf-benchmark"
Cohesion: 0.40
Nodes (5): perf-benchmark, 1 Mathematical Solvers MicroBenchmark, 2 Spatial Hash Grid Latency Benchmark, Execution Commands, Performance Benchmark & Solvers Profiling Skill

### Community 55 - "graphify"
Cohesion: 0.38
Nodes (6): PYTHONIOENCODING, PYTHONUNBUFFERED, C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe, python, graphify, powerfootball

### Community 56 - "Scratchpad"
Cohesion: 0.40
Nodes (5): Scratchpad, Active Invariants Checked, Antigravity Scratchpad — MultiStep Reasoning & Active State, Current Subsystem Focus, StepbyStep Task Plan

### Community 57 - "eval-sim"
Cohesion: 0.40
Nodes (5): eval-sim, Assertion Thresholds & Failure Criteria, Execution Command, Headless Simulation Evaluation Skill, PostRun Actions

### Community 58 - "formation-audit"
Cohesion: 0.40
Nodes (5): formation-audit, Evaluated Spacing Metrics, Execution Command, Formation & Tactical Spacing Audit Skill, Supported Formations

### Community 59 - "perf-benchmark"
Cohesion: 0.40
Nodes (5): perf-benchmark, 1 Mathematical Solvers MicroBenchmark, 2 Spatial Hash Grid Latency Benchmark, Execution Commands, Performance Benchmark & Solvers Profiling Skill

### Community 60 - "Transcribe"
Cohesion: 0.40
Nodes (5): Transcribe, graphify reference: transcribe video and audio, print progress to stdout which would otherwise corrupt the JSON file 1392, Step 25  Transcribe video / audio files only if video files detected, Write the JSON from Python NOT a shell '>' redirect: transcribeall/Whisper

### Community 61 - "expand_database.py"
Cohesion: 0.70
Nodes (4): generate_manager(), generate_player(), generate_staff(), main()

### Community 62 - "formation_ascii.py"
Cohesion: 0.90
Nodes (4): calculate_phase_positions(), display_all_phases(), main(), render_ascii_pitch()

### Community 63 - "ast-refactor"
Cohesion: 0.50
Nodes (4): ast-refactor, AST Refactor & Invariant Preservation Skill, Strict Refactoring Rules, Verification Loop

### Community 64 - "formation-fuzzer"
Cohesion: 0.50
Nodes (4): formation-fuzzer, Evaluated Invariants, Execution Command, Formation Anchor & Boundary Fuzzing Skill

### Community 65 - "ast-refactor"
Cohesion: 0.50
Nodes (4): ast-refactor, AST Refactor & Invariant Preservation Skill, Strict Refactoring Rules, Verification Loop

### Community 66 - "formation-fuzzer"
Cohesion: 0.50
Nodes (4): formation-fuzzer, Evaluated Invariants, Execution Command, Formation Anchor & Boundary Fuzzing Skill

### Community 67 - "Research Index"
Cohesion: 0.50
Nodes (4): Research Index, Consult before writing any code where implementation intent is unclear, Do not guess at physics values feel parameters or AI thresholds, researchindexmd

### Community 68 - "Add Watch"
Cohesion: 0.50
Nodes (4): Add Watch, For /graphify add, For watch, graphify reference: add a URL and watch a folder

### Community 69 - "dump_match_frames.py"
Cohesion: 0.83
Nodes (3): generate_simulated_match_frames(), main(), render_svg_frame()

### Community 70 - "git_pre_commit.py"
Cohesion: 0.83
Nodes (3): install_hook(), main(), run_checks()

### Community 71 - "hook_gdcheck.py"
Cohesion: 0.83
Nodes (3): format_xml_diagnostics(), main(), parse_gdcheck_output()

### Community 72 - "layer_context.py"
Cohesion: 0.83
Nodes (3): main(), print_layer_context(), read_rule_excerpt()

### Community 73 - "lint_allocations.py"
Cohesion: 0.83
Nodes (3): check_file_allocations_and_distance(), find_gd_files(), main()

### Community 74 - "lint_stringnames.py"
Cohesion: 0.83
Nodes (3): check_file(), find_gd_files(), main()

### Community 77 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.11
Nodes (18): 1. Purpose and Non-Responsibilities, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: MatchWorldModel, Constants & Enums (+10 more)

### Community 107 - "generate_symbols.py"
Cohesion: 0.33
Nodes (8): find_gd_files(), get_autoload_map(), main(), parse_file_symbols(), parse_function_signature(), Any, Returns mapping from relative file path to autoload global name., Parses `func_name(arg1: Type, ...) -> RetType` into (name, args_list, ret_type).

### Community 108 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.11
Nodes (18): 1. Purpose and Non-Responsibilities, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: PlayerBrain, Core Dependencies (+10 more)

### Community 109 - "Architecture Hub: PitchScene"
Cohesion: 0.11
Nodes (17): 1. Purpose and Non-Responsibilities, 22-Player Declarative Layout Invariant, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: PitchScene (+9 more)

### Community 110 - "Architecture Hub: SetPieceCoordinator"
Cohesion: 0.11
Nodes (17): 1. Purpose and Non-Responsibilities, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Anti-Double-Touch Law, Architecture Hub: SetPieceCoordinator (+9 more)

### Community 111 - "Player AI & Spatial Navigation Errata"
Cohesion: 0.12
Nodes (17): arrive-radius-strands-correct-chase-decision, bresenham-threat-shadowed-real-lane-check-match-wide, chase-radius-crushes-legal-loose-ball-chase-score, cpu-players-never-gated-into-tackle-state, defender-marking-was-uncoordinated-and-boundary-clamp-already-existed, Discovered Rules, ERR-20260830-01, Error Logs (+9 more)

### Community 112 - "benchmark_math.py"
Cohesion: 0.22
Nodes (16): calculate_intercept_point_fast(), calculate_psxg_fast(), calculate_xg_fast(), clampf(), is_lane_blocked_fast(), main(), quadratic_decay(), run_benchmarks() (+8 more)

### Community 113 - "The 10-Step Mandatory Protocol"
Cohesion: 0.14
Nodes (13): Cross-System Gameplay Feature Workflow, Invocation in Antigravity, Step 10: Final Verification Report, Step 1: Restate Requested Outcome and Non-Goals, Step 2: Classify Change-Impact Tier, Step 3: Graphify Impact Query Before Reading Broad Source Files, Step 4: Reading Only Relevant Module READMEs, Hub Maps, and Targeted Files, Step 5: Short Written Implementation Plan (+5 more)

### Community 114 - "AnalyticalSimulationHarness"
Cohesion: 0.23
Nodes (9): range, AnalyticalSimulationHarness, find_godot_binary(), main(), print_summary_table(), Any, Deterministic analytical 60Hz match physics & AI decision simulator. Simulates…, run_analytical_trials() (+1 more)

### Community 115 - "verify_gate.py"
Cohesion: 0.60
Nodes (3): CheckResult, main(), run_step()

### Community 116 - "Roadmap"
Cohesion: 0.29
Nodes (7): Roadmap, PHASE 1 — Gameplay Completeness, PHASE 2 — Personality and Traits, PHASE 3 — Club World, PHASE 4 — Career Mode, PHASE 5 — Polish, ROADMAPmd

### Community 118 - "Set Pieces & Restarts Errata"
Cohesion: 0.22
Nodes (9): Discovered Rules, ERR-20260831-01, ERR-20260831-02, ERR-20260831-03, Error Logs, kickoff-backward-pass-veto-starves-taker, Set Pieces & Restarts Errata, Table of Contents (+1 more)

### Community 119 - "Match State, Pacing & Urgency Errata"
Cohesion: 0.25
Nodes (7): Discovered Rules, manager-risk-profile-is-derived-not-authored, match-stage-boundaries-are-fractions-not-literal-seconds, Match State, Pacing & Urgency Errata, possession-hold-timer-has-two-non-interchangeable-variants, stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate, Table of Contents

### Community 120 - "Physics, Ball Dynamics & Kinematics Errata"
Cohesion: 0.22
Nodes (8): bicycle-kick-dominates-ambiguous-facing, Discovered Rules, dribble-claim-ignores-existing-possessor-dual-driver-jitter, dribble-magnet-forward-overshoot-oscillation, eval-simulation-harness-was-decoupled-from-gdscript-tuning, Physics, Ball Dynamics & Kinematics Errata, Table of Contents, verify-external-agent-prompts-against-source-before-executing

### Community 121 - "Complete Item Migration Manifest"
Cohesion: 0.25
Nodes (8): Agent Errata & Lessons Learned Index, Ambiguous Entries Report, Complete Item Migration Manifest, Discovered Rules (24 Items), Error Logs (7 Items), Narrative Subsections (4 Items), Session Handoff States, Topic Reference Pages

### Community 122 - "UI, HUD & Signal Bus Errata"
Cohesion: 0.25
Nodes (7): ball-struck-signal-arg-count-mismatch, Discovered Rules, ERR-20260830-02, Error Logs, Table of Contents, touchline-bubble-is-one-shared-instance-home-perspective-only, UI, HUD & Signal Bus Errata

### Community 123 - "Scene Tree, Node Hierarchy & Cross-Referencing Errata"
Cohesion: 0.25
Nodes (7): Cross-Module Architecture Findings, ERR-20260901-01, Error Logs, Non-ASCII identifiers parse here but not in Godot, Scene Tree, Node Hierarchy & Cross-Referencing Errata, Table of Contents, Three latent runtime crashes found by static cross-referencing

### Community 124 - "session-history.md"
Cohesion: 0.15
Nodes (11): Calibration is not optional, and the first guess was wrong twice, Career Calibration Findings, Data, Persistence & Career Calibration Errata, Table of Contents, The season calendar cannot be a fixed weekly rhythm, Architectural & Gotcha Findings from this Session, Errata Session History & Handoff Logs, Next Steps Handoff (+3 more)

### Community 125 - "README.md"
Cohesion: 0.25
Nodes (4): crowding-space-creation-diagnostics, Discovered Rules, Table of Contents, Telemetry, Diagnostics & Match Stats Errata

### Community 126 - "compact_errata.py"
Cohesion: 0.48
Nodes (6): archive_sessions(), compact_errata_file(), extract_session_blocks(), main(), Splits session_state YAML into individual session item blocks., run_sync_rules()

### Community 127 - "dump_api.py"
Cohesion: 0.52
Nodes (5): generate_markdown(), get_layer_for_path(), main(), parse_gd_file(), ScriptAPI

## Knowledge Gaps
- **719 isolated node(s):** `python`, `C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe`, `python`, `C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe`, `Career Mode (Layer 4) Invariants` (+714 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1132 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **30 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Agents` connect `Agents` to `Api Surface`, `sync_rules.py`, `Course Implementation Specification`, `Anti Patterns`, `Agents Errata`, `Powerfootball Master Vision`, `mcp_server.py`, `Vector2`, `Claude`, `Core Invariants`, `lint_invariants.py`, `Math Solvers`, `semantic_search.py`, `Graphify Lifecycle & Agent Navigation Protocol — PowerFootball-2D`, `DeterministicMatchSimulator`, `generate_symbols.py`, `benchmark_math.py`, `AnalyticalSimulationHarness`, `Roadmap`, `README.md`, `compact_errata.py`, `dump_api.py`?**
  _High betweenness centrality (0.148) - this node is a cross-community bridge._
- **Why does `Agents Errata` connect `Agents Errata` to `Course Implementation Specification`, `Powerfootball Master Vision`, `Claude`, `gdcheck.py`, `Core Invariants`, `Readme`, `Agents`, `verify_gate.py`, `Match State, Pacing & Urgency Errata`, `Physics, Ball Dynamics & Kinematics Errata`, `UI, HUD & Signal Bus Errata`, `Scene Tree, Node Hierarchy & Cross-Referencing Errata`, `session-history.md`, `README.md`?**
  _High betweenness centrality (0.104) - this node is a cross-community bridge._
- **Why does `Api Surface` connect `Api Surface` to `Readme`, `Agents`, `Core Invariants`, `dump_api.py`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `Api Surface` (e.g. with `Agents` and `dump_api.py`) actually correct?**
  _`Api Surface` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 5 inferred relationships involving `Course Implementation Specification` (e.g. with `Agents` and `Core Invariants`) actually correct?**
  _`Course Implementation Specification` has 5 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `Agents Errata` (e.g. with `Agents` and `Core Invariants`) actually correct?**
  _`Agents Errata` has 11 INFERRED edges - model-reasoned connections that need verification._
- **What connects `python`, `C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe`, `python` to the rest of the system?**
  _719 weakly-connected nodes found - possible documentation gaps or missing edges._