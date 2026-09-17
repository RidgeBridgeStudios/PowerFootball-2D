# Graph Report - PowerFootball-Simulation  (2026-09-18)

## Corpus Check
- 207 files · ~1,251,657 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 103 file(s) not represented in the graph (top: .gd 74, .tres 13, .tscn 8)

## Summary
- 1916 nodes · 2540 edges · 141 communities (115 shown, 26 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 132 edges (avg confidence: 0.92)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e28645b9`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Api Surface
- graphify
- Course Implementation Specification
- Anti Patterns
- Readme
- mcp_server.py
- Agents Errata
- Team Flag Textures
- Update
- Vector2
- lint_invariants.py
- Powerfootball Master Vision
- AnalyticalSimulationHarness
- gdcheck.py
- **Bayesian Uncertainty Quantification and Positional Rating Systems in Football Simulation Engine Architectures**
- Json Schema
- Core Invariants
- SOCIAL_SIMULATION_ARCHITECTURE.md
- semantic_search.py
- **Econometric Refactoring of Football Player Valuation and Transfer Market Dynamics**
- **Combinatorial Round-Robin Architecture: Zero-Allocation Generation, Break Minimization, and Constraint Fulfillment in Godot 4.7**
- **Engineering Research Plan v2: Empirical Football Analytics Infrastructure for PowerFootball-2D**
- **Algorithmic and Architectural Specification for PowerFootball-2D: Semi-Markov Simulation, Social Graph Dynamics, and Continuous Valuation**
- **Automated Commentary Systems in Sports Simulation: Knowledge Graph Extraction, Deterministic Synthesis, and Trait-Driven Narrative Architecture in PowerFootball-2D**
- **Core Component Implementations in GDScript 2.0**
- Player AI & Spatial Navigation Errata
- 2. Public API, Signals, Events, Contracts & Dependencies
- 4. Non-obvious consequences an agent can trip over
- Architecture Hub: PitchScene
- Architecture Hub: SetPieceCoordinator
- Phase 0 Architectural Fixes (P1–P4) — Final Report
- football_mcp.py
- **Comprehensive Data Source Audit and Artifact Reconnaissance for PowerFootball-2D: Systematic Investigation of Datasets, Parsers, Player Attributes, Fan Culture, Club Infrastructure, Sample Joins, and Integration Architecture**
- **Architecture and Implementation of a Zero-Allocation 90-Tick Utility AI Match Simulation Engine in GDScript 2.0**
- Execution Command
- Math Solvers
- Agents
- The 10-Step Mandatory Protocol
- The 10-Step Mandatory Protocol
- generate_db.py
- lint_scope.py
- Readme
- Graphify Lifecycle & Agent Navigation Protocol — PowerFootball-2D
- **Agent-Based Dressing Room Dynamics: Graph-Theoretic Morale Propagation and Mutiny Simulation in Godot 4**
- Readme
- spatial_grid_bench.py
- Ai Architect
- Readme
- Claude
- 2. Public API, Signals, Events, Contracts & Dependencies
- Compounded corrections — verified against the source
- Query
- **Mathematical Calibration of Player Development and Senescence in Association Football Simulation**
- benchmark_math.py
- fuzz_utility_scorer.py
- test_quick_sim.py
- validate_schemas.py
- Career Mode
- Scene Tree, Node Hierarchy & Cross-Referencing Errata
- Llms
- gdscript_slice_server.py
- sys
- lint_type_comparisons.py
- DeterministicMatchSimulator
- Architecture Hub: CareerManager
- Context Hygiene
- Exports
- Github And Merge
- Physics, Ball Dynamics & Kinematics Errata
- Set Pieces & Restarts Errata
- fuzz_formations.py
- worktree_manager.py
- football-expert
- Gdscript Antipatterns
- football-expert
- Complete Item Migration Manifest
- 2. Public API, Signals, Events, Contracts & Dependencies
- Architecture Hub: MatchWorldModel
- Readme
- generate_phony_db.py
- argparse
- test_pass_starvation.py
- Match State, Pacing & Urgency Errata
- UI, HUD & Signal Bus Errata
- dump_dep_graph.py
- tscn_linter.py
- .agents/rules/graphify.md
- Engine: Godot 4.7-stable | GDScript 2.0 ONLY | Strict Static Typing
- Soccer Physics
- perf-benchmark
- Errata Session History & Handoff Logs
- Graphify Knowledge Graph Setup
- CLIProxyAPI Setup Instructions
- expand_database.py
- formation_ascii.py
- lint_stringnames.py
- os
- GDScript 2.0 & Simulation Architectural Invariants
- ast-refactor
- Scratchpad
- graphify
- Transcribe
- Data, Persistence & Career Calibration Errata
- football-expert
- replay_test.py
- git_pre_commit.py
- lint_xref.py
- 2. Public API, Signals, Events, Contracts & Dependencies
- layer_context.py
- Roadmap
- re
- 3. State Model & Architectural Invariants
- 3. State Model & Architectural Invariants
- Add Watch
- Telemetry, Diagnostics & Match Stats Errata
- Workflow: bug-investigation
- Workflow: cross-system-feature
- Workflow: data-database
- Workflow: session-bootstrap
- Workflow: task-intake-routing
- Research Index
- tool_gatekeeper.sh script
- check_blast_radius.md
- check-blast-radius/SKILL.md
- graphify
- Extraction Spec
- Godot 4 Football Ai Overhaul Optimization Plan
- agv_route.sh
- worktree_harness.sh
- Research Index
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

## God Nodes (most connected - your core abstractions)
1. `Api Surface` - 156 edges
2. `graphify` - 81 edges
3. `Course Implementation Specification` - 67 edges
4. `Agents Errata` - 65 edges
5. `Anti Patterns` - 52 edges
6. `Core Invariants` - 41 edges
7. `Agents` - 40 edges
8. `Powerfootball Master Vision` - 39 edges
9. `Team Flag Textures` - 35 edges
10. `Update` - 35 edges

## Surprising Connections (you probably didn't know these)
- `4. Change-Impact Checklist` --references--> `Vector2`  [INFERRED]
  docs/architecture/hubs/player-brain.md → tools/fuzz_solvers.py
- `Non-Responsibilities` --references--> `Vector2`  [INFERRED]
  docs/architecture/hubs/player-brain.md → tools/fuzz_solvers.py
- `4.2 Star-Marking Utility Scorer — Full Specification` --references--> `Vector2`  [INFERRED]
  docs/SOCIAL_SIMULATION_ARCHITECTURE.md → tools/fuzz_solvers.py
- `Purpose` --references--> `UtilityContext`  [INFERRED]
  docs/architecture/hubs/player-brain.md → tools/fuzz_utility_scorer.py
- `When to call it` --references--> `verify_kinematics()`  [INFERRED]
  .agents/rules/football-domain.md → tools/football_mcp.py

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Gdscript Antipatterns Concepts** — agents_rules_gdscript_antipatterns_gdscript_20_antipatterns___postmortem_sa, agents_rules_gdscript_antipatterns_1_object_vs_literal_equality_comparisons, agents_rules_gdscript_antipatterns_2_function_scope___duplicate_declaration, agents_rules_gdscript_antipatterns_3_hotpath_zeroallocation_discipline, agents_rules_gdscript_antipatterns_4_distance_calculation_discipline [INFERRED 0.85]
- **ast-refactor Concepts** — agents_skills_ast_refactor_skill_ast_refactor___invariant_preservation_sk, agents_skills_ast_refactor_skill_strict_refactoring_rules, agents_skills_ast_refactor_skill_verification_loop [INFERRED 0.85]
- **eval-sim Concepts** — agents_skills_eval_sim_skill_headless_simulation_evaluation_skill, agents_skills_eval_sim_skill_execution_command, agents_skills_eval_sim_skill_assertion_thresholds___failure_criteria, agents_skills_eval_sim_skill_postrun_actions [INFERRED 0.85]
- **Context Hygiene Concepts** — claude_rules_context_hygiene, claude_rules_context_hygiene_prohibited, claude_rules_context_hygiene_wrong___pastes_200_lines_of_find_output, claude_rules_context_hygiene_correct___pasted_summary, claude_rules_context_hygiene_tool_output_rule [INFERRED 0.85]
- **Gdscript Antipatterns Concepts** — agents_rules_gdscript_antipatterns_gdscript_20_antipatterns___postmortem_sa, agents_rules_gdscript_antipatterns_1_object_vs_literal_equality_comparisons, agents_rules_gdscript_antipatterns_2_function_scope___duplicate_declaration, agents_rules_gdscript_antipatterns_3_hotpath_zeroallocation_discipline, agents_rules_gdscript_antipatterns_4_distance_calculation_discipline [INFERRED 0.85]
- **Godot 47 Core Concepts** — claude_rules_godot_47_core_godot_47_gdscript_20_invariants, claude_rules_career_mode_compounded_corrections___verified_agains, claude_rules_godot_47_core_managerloader_emits_no_formation_signal, claude_rules_godot_47_core_entities_manager_managerdirectorgd___shi, claude_rules_godot_47_core_deprecated__export___unused_export [INFERRED 0.85]
- **Anti Patterns Concepts** — docs_anti_patterns_antipatternsmd___antihallucination___arc, docs_anti_patterns_1_complete_godot_47___gdscript_20_pitfal, docs_anti_patterns_2_engine___gdscript_20_syntax_antipatter, docs_anti_patterns_3_strict_type_system___autoload_invarian, docs_anti_patterns_antipattern_31__untyped_declarations [INFERRED 0.85]
- **Api Surface Concepts** — docs_api_surface_powerfootball2d___public_api_surface_map, docs_api_surface_table_of_contents, llms_layer_1___physics___kinematics, docs_api_surface_entities_ball_ballstategd, docs_api_surface_entities_ball_ballstatefactorygd [INFERRED 0.85]
- **Core Invariants Concepts** — docs_core_invariants_coreinvariantsmd___powerfootball2d_archi, docs_core_invariants_1_engine_lock, docs_core_invariants_prohibited___strictly_forbidden_apis, docs_core_invariants_strict_typing_invariant, docs_core_invariants_scene_initialization___serialization [INFERRED 0.85]

## Communities (141 total, 26 thin omitted)

### Community 0 - "Api Surface"
Cohesion: 0.01
Nodes (142): Api Surface, autoloads/CareerManagergd, autoloads/DataLoadergd, autoloads/GameEventsgd, autoloads/GameManagergd, autoloads/InputHelpergd, autoloads/ManagerLoadergd, autoloads/MatchStatsTrackergd (+134 more)

### Community 1 - "graphify"
Cohesion: 0.03
Nodes (80): Claude, graphify, a detected file whose chunk failed or was omitted must stay unstamped so the, a stale semantichash from a prior run; clear it so detectincremental requeues, Always rewrite the cache file: write hits else DELETE any leftover from a prior, base so the full build and incremental update never drift apart on reextract, by the AST pass Part A; flattening every category here makes subagents reread, clistampedmanifestfiles  clearsemantic  scancorpus; do not stamp the (+72 more)

### Community 2 - "Course Implementation Specification"
Cohesion: 0.03
Nodes (62): Course Implementation Specification, 10 Main Algorithms and Business Rules, 11 Setup and Build Instructions, 12 Implementation Phases, 13 Detailed Requirements by Phase, 14 Known Constraints Gotchas & Errata, 15 AI Agent Protocol, 1 Course Objective (+54 more)

### Community 3 - "Anti Patterns"
Cohesion: 0.04
Nodes (50): Anti Patterns, 1 Complete Godot 47 / GDScript 20 Pitfall Matrix, 2 Engine & GDScript 20 Syntax AntiPatterns, 3 Strict Type System & Autoload Invariants, 4 FiveLayer Simulation Stack & Choke Point Invariants, 5 Physics & Collision Matrix AntiPatterns, 6 AI Tactical & Spatial Logic AntiPatterns, AntiPattern 31: Untyped Declarations (+42 more)

### Community 4 - "Readme"
Cohesion: 0.09
Nodes (25): Errata History, Errata History Archive, generate_markdown(), get_layer_for_path(), main(), parse_gd_file(), dump_api.py — Public API Surface Generator for PowerFootball-2D. Parses all .gd…, ScriptAPI (+17 more)

### Community 5 - "mcp_server.py"
Cohesion: 0.22
Nodes (19): io, list_symbols_in_file(), load_file_lines(), main(), codebase_slice.py — Targeted Code Slicing CLI Utility. Extracts specific class…, slice_class_header(), slice_enum(), slice_function() (+11 more)

### Community 6 - "Agents Errata"
Cohesion: 0.05
Nodes (38): Agents Errata, affectedfiles:, agent: string, Calibration is not optional and the first guess was wrong twice, category: engine | physics | ai | social | data | architecture, date: YYYYMMDD, Discovered Rules, discoveredby: string model/agent identifier (+30 more)

### Community 7 - "Team Flag Textures"
Cohesion: 0.06
Nodes (36): Argentina Flag, Argentine Flag, Austria Flag, Batavian Flag, Belgium Flag, Brasilian Flag, Brazil Flag, Britannic Flag (+28 more)

### Community 8 - "Update"
Cohesion: 0.06
Nodes (36): Update, are dropped rather than masquerading as deletions; untouched rows preserved 1908, as the freshly merged nodes and would DELETE the reextracted content 1178 is moot, cached files instead of missing every one after a move 1417, Changed semantic files dispatched this run but NOT stamped had their chunk fail, clistampedmanifestfiles  clearsemantic  scancorpus, directed=ISDIRECTED: replace ISDIRECTED with True if directed was given else, Do NOT add changed here: with root= passed pruneset relativizes to the same base (+28 more)

### Community 9 - "Vector2"
Cohesion: 0.06
Nodes (39): 1. Strict Typing Discipline, 2. Forbidden Pythonisms, 3. GDScript 2.0 Language Invariants, 4. Hot-Path Performance Rules, GDScript 2.0 & Godot 4.7 Strict Architecture Rules, Ponytail Decision Ladder (Reuse & Complexity Gating), Real navigation/verification stack — do not reinvent it, Step 7: Targeted Validation and Diff Review (+31 more)

### Community 10 - "lint_invariants.py"
Cohesion: 0.13
Nodes (22): check_game_manager_thin_shell(), check_hot_path_allocations(), check_publish_ownership(), check_scene_tree_crawl(), check_signal_bus_surface(), check_state_ownership(), _enum_members(), format_xml_output() (+14 more)

### Community 11 - "Powerfootball Master Vision"
Cohesion: 0.06
Nodes (32): Powerfootball Master Vision, Aerial Contact Personality Weighting Future Refinement, Deep Simulation Gaps, Design References, "Dwarf Fortress with a football" Simple visuals; deep social simulation, Error Compounding, Feature Development Loop, Immediate Match Completeness (+24 more)

### Community 12 - "AnalyticalSimulationHarness"
Cohesion: 0.12
Nodes (14): range, AnalyticalSimulationHarness, find_godot_binary(), main(), print_summary_table(), Any, eval_simulation.py — Headless Simulation Assertion & Telemetry Evaluation…, Deterministic analytical 60Hz match physics & AI decision simulator. Simulates… (+6 more)

### Community 13 - "gdcheck.py"
Cohesion: 0.10
Nodes (25): Godot 47 Core, Godot 47 Core, "Deprecated" export ≠ unused export, entities/manager/ManagerDirectorgd — shiftto, gdcheck resolves autoload singleton names as types — never "fix" this by adding classname, Godot 47 GDScript 20 Invariants, ManagerLoader emits NO formation signal — ManagerDirector does, new is inherited not declared (+17 more)

### Community 14 - "**Bayesian Uncertainty Quantification and Positional Rating Systems in Football Simulation Engine Architectures**"
Cohesion: 0.07
Nodes (28): **1.1 Structural Discrepancy Between PyScoutFM and PowerFootball-2D**, **1.2 The 36-to-13 Dimensional Reduction and Aggregation Matrix**, **1.3 Score Normalization to the PowerFootball-2D Metric Scale**, **1\. Positional Attribute Weightings & Structural Ingestion**, **2.1 Licensing Boundaries and Legal Isolation**, **2.2 Clean-Room Architectural Extraction**, **2\. Clean-Room Architectural Separation of External Scouting Frameworks**, **3.1 Limitations of Heuristic Knowledge Accumulation** (+20 more)

### Community 15 - "Json Schema"
Cohesion: 0.07
Nodes (28): Json Schema, Biography PLANNED, Complete Manager Example, Complete Player Example, Complete Team Example, Contract Data PLANNED, DataLoader IMPLEMENTED, Decision Attributes IMPLEMENTED (+20 more)

### Community 16 - "Core Invariants"
Cohesion: 0.13
Nodes (16): Core Invariants, 1 Engine Lock, 2 Simulation Stack, 3 Critical File Contracts Choke Points, 4 Physics & Spatial AI Invariants, 5 Static Verification & Autoload Handling, COREINVARIANTSmd — PowerFootball2D Architectural & Engine Invariants, CrossLayer Architectural Invariant (+8 more)

### Community 17 - "SOCIAL_SIMULATION_ARCHITECTURE.md"
Cohesion: 0.08
Nodes (23): 0. Ground Truth — What Already Exists vs. What This Document Adds, 1.1 Existing Bitmask (unchanged), 1.2 Mechanical Lever Table, 1.3 `PressureImmune` — Closing the Live-Match Gap, 1.4 The `TraitEffectResolver` Pattern, 1.5 Trait Interaction & Anti-Snowball Guard, 1. The Psychological Trait & Archetype Matrix, 2.1 Existing Schema (unchanged) (+15 more)

### Community 18 - "semantic_search.py"
Cohesion: 0.16
Nodes (17): Context Hygiene, Context Hygiene & Token Discipline, archive_sessions(), compact_errata_file(), extract_session_blocks(), main(), compact_errata.py — Errata memory compaction and archiving tool. 1.…, Splits session_state YAML into individual session item blocks. (+9 more)

### Community 19 - "**Econometric Refactoring of Football Player Valuation and Transfer Market Dynamics**"
Cohesion: 0.09
Nodes (21): **1\. player-value-lgbm**, **2\. fair-ds-experiment**, **3\. football-analysis-predicting-market**, **4\. football\_analytics**, **Architecture Alignment: Seed Generation versus Dynamic Transfer Valuation**, **Citerade verk**, **Conclusions and Implementation Recommendations**, **Deconstruction of 0xagarg/football-analysis-predicting-market** (+13 more)

### Community 20 - "**Combinatorial Round-Robin Architecture: Zero-Allocation Generation, Break Minimization, and Constraint Fulfillment in Godot 4.7**"
Cohesion: 0.10
Nodes (20): **Academic Break Minimization and Fairness Metrics**, **Architectural Synthesis and Implementation Conclusions**, **babafemi99/fas**, **Break Dynamics and Lower Bounds**, **Carry-Over Effect Dynamics and Opponent Sequencing**, **Citerade verk**, **Combinatorial Round-Robin Architecture: Zero-Allocation Generation, Break Minimization, and Constraint Fulfillment in Godot 4.7**, **Comparative Benchmark and Structural Performance Analysis** (+12 more)

### Community 21 - "**Engineering Research Plan v2: Empirical Football Analytics Infrastructure for PowerFootball-2D**"
Cohesion: 0.10
Nodes (20): **Appendix 1: Corrected Engineering Plan Summary and Topological Execution Matrix**, **Appendix 2: Mathematical Formulations for Pitch Analytics**, **Appendix 3: Third-Party Licensing and Attribution Specifications**, **Appendix 4: GDScript Implementation and Porting Specifications**, **Citerade verk**, **Dynamic Grid Serialization and Verification Harness (tools/test\_xt\_grid.py)**, **Engineering Research Plan v2: Empirical Football Analytics Infrastructure for PowerFootball-2D**, **Expected Goals (xG) Calibrated Logistic Model** (+12 more)

### Community 22 - "**Algorithmic and Architectural Specification for PowerFootball-2D: Semi-Markov Simulation, Social Graph Dynamics, and Continuous Valuation**"
Cohesion: 0.10
Nodes (20): **Algorithmic and Architectural Specification for PowerFootball-2D: Semi-Markov Simulation, Social Graph Dynamics, and Continuous Valuation**, **Algorithmic Blueprint**, **Citerade verk**, **Comparative Architectural Analysis**, **Complete GDScript 2.0 Implementation (shared/QuickSimEngine.gd)**, **Conclusions and Implementation Invariants**, **Continuous Valuation Model**, **Contract Depreciation Schedule (![][image64])** (+12 more)

### Community 23 - "**Automated Commentary Systems in Sports Simulation: Knowledge Graph Extraction, Deterministic Synthesis, and Trait-Driven Narrative Architecture in PowerFootball-2D**"
Cohesion: 0.10
Nodes (20): **Apache License, Version 2.0**, **Architectural Synthesis and Systemic Conclusions**, **Automated Commentary Systems in Sports Simulation: Knowledge Graph Extraction, Deterministic Synthesis, and Trait-Driven Narrative Architecture in PowerFootball-2D**, **BSD 3-Clause License**, **Citerade verk**, **Comparative Corpus Analysis and Dataset Topology**, **Complete Implementation: entities/manager/PressOffice.gd**, **Dataset Ingestion Constraints and Access Topologies** (+12 more)

### Community 24 - "**Core Component Implementations in GDScript 2.0**"
Cohesion: 0.10
Nodes (19): **Allocation-Free Panel Navigation Stack (ui/manager\_mode/UIPanelStack.gd)**, **Citerade verk**, **Comparative Tactics Interface Analysis: 99Managers Futsal Edition vs. PowerFootball-2D**, **Core Component Implementations in GDScript 2.0**, **Direct-Mutation Simulation Inspector (ui/debug/PlayerInspector.gd)**, **High-Performance Virtual Table (ui/manager\_mode/VirtualTable.gd)**, **Information Architecture and Screen Decomposition**, **Lazy-List Recycling Control (ui/manager\_mode/LazyListBox.gd)** (+11 more)

### Community 25 - "Player AI & Spatial Navigation Errata"
Cohesion: 0.11
Nodes (19): arrive-radius-strands-correct-chase-decision, bresenham-threat-shadowed-real-lane-check-match-wide, chase-radius-crushes-legal-loose-ball-chase-score, cpu-players-never-gated-into-tackle-state, defender-marking-was-uncoordinated-and-boundary-clamp-already-existed, Discovered Rules, ERR-20260830-01, Error Logs (+11 more)

### Community 26 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.17
Nodes (11): 2. Public API, Signals, Events, Contracts & Dependencies, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: PlayerBrain, Core Dependencies, Enums & Types, Exported Properties (+3 more)

### Community 27 - "4. Non-obvious consequences an agent can trip over"
Cohesion: 0.11
Nodes (18): 1. What changed and why, 2. The `legacy/` archive, 3. The new 3-layer stack, 4. Non-obvious consequences an agent can trip over, 5. Tooling, verification, and where to look next, Architecture Pivot Errata — Manager-Only Quick-Sim, Autoload boot order (9, in `project.godot` order), Career match-day flow (+10 more)

### Community 28 - "Architecture Hub: PitchScene"
Cohesion: 0.11
Nodes (17): 1. Purpose and Non-Responsibilities, 22-Player Declarative Layout Invariant, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: PitchScene (+9 more)

### Community 29 - "Architecture Hub: SetPieceCoordinator"
Cohesion: 0.11
Nodes (17): 1. Purpose and Non-Responsibilities, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Anti-Double-Touch Law, Architecture Hub: SetPieceCoordinator (+9 more)

### Community 30 - "Phase 0 Architectural Fixes (P1–P4) — Final Report"
Cohesion: 0.12
Nodes (16): 1. What shipped, 2. Verification status, 3. Known limitations carried into Phase 1, 4. How to run the tests, 5. Manual test scripts, 6. Appendix — Raw Outputs, Dead Code Grep Output, `godot --headless tests/TestRunner.tscn` (+8 more)

### Community 31 - "football_mcp.py"
Cohesion: 0.12
Nodes (24): Football Domain Intelligence (`football-expert` MCP server), Keeping it current, When to call it, Football Domain Intelligence (`football-expert` MCP server), Keeping it current, When to call it, Connection, fastmcp (+16 more)

### Community 32 - "**Comprehensive Data Source Audit and Artifact Reconnaissance for PowerFootball-2D: Systematic Investigation of Datasets, Parsers, Player Attributes, Fan Culture, Club Infrastructure, Sample Joins, and Integration Architecture**"
Cohesion: 0.12
Nodes (15): **Citerade verk**, **Comprehensive Data Source Audit and Artifact Reconnaissance for PowerFootball-2D: Systematic Investigation of Datasets, Parsers, Player Attributes, Fan Culture, Club Infrastructure, Sample Joins, and Integration Architecture**, **Executive Synthesis**, **Procedural Generation Fallbacks for Missing Data**, **Scraper Ecosystem Inventory**, **Section 1: Football Manager (FM) Ecosystem Reconnaissance**, **Section 2: Non-FM Rating Matrices, Granular Attributes, and Statistical Aggregators**, **Section 3: Biographical Identity, Relational Contracts, and Career Registries** (+7 more)

### Community 33 - "**Architecture and Implementation of a Zero-Allocation 90-Tick Utility AI Match Simulation Engine in GDScript 2.0**"
Cohesion: 0.12
Nodes (15): **10\. Implementation Synthesis**, **1\. Architectural Paradigm Shift: From Continuous Poisson Aggregation to Discrete Utility AI**, **2\. Comparative Analysis of Game AI Frameworks and GDScript Constraints**, **3\. Zero-Allocation Engine Discipline and Godot 4 Semantics**, **4\. Discrete State-Space and Transition Matrix Dynamics**, **5\. Mathematical Activation Curves and Utility Formulation**, **6\. Statistical Benchmarking and Calibration Across 10,000 Matches**, **7.1 shared/MatchTickState.gd** (+7 more)

### Community 34 - "Execution Command"
Cohesion: 0.21
Nodes (15): eval-sim, Assertion Thresholds & Failure Criteria, Execution Command, Headless Simulation Evaluation Skill, PostRun Actions, formation-audit, Evaluated Spacing Metrics, Formation & Tactical Spacing Audit Skill (+7 more)

### Community 35 - "Math Solvers"
Cohesion: 0.13
Nodes (15): Math Solvers, 1 Kinematic PointtoSegment Projection & Distance, 1 Quadratic Distance Utility Decay, 2 Angular Cosine Alignment, 2 Kinematic Turning Penalty & Acceleration Curve, 3 Ballistic Pseudo3D Flight & Height Trajectory, 3 Receiver Openness, 4 Bisection RootFinding Ball Intercept Algorithm (+7 more)

### Community 36 - "Agents"
Cohesion: 0.14
Nodes (14): Agents, 1 Core Architecture & Invariants, 2 Verification & Static Analysis, 3 Developer Tooling & Slash Commands, 4 Gemini Context Protocol & Antigravity Autonomy, AGENTSmd, Atomic Feature Discipline, Autoload Handling Contract (+6 more)

### Community 37 - "The 10-Step Mandatory Protocol"
Cohesion: 0.15
Nodes (12): Cross-System Gameplay Feature Workflow, Invocation in Antigravity, Step 10: Final Verification Report, Step 1: Restate Requested Outcome and Non-Goals, Step 2: Classify Change-Impact Tier, Step 3: Graphify Impact Query Before Reading Broad Source Files, Step 4: Reading Only Relevant Module READMEs, Hub Maps, and Targeted Files, Step 5: Short Written Implementation Plan (+4 more)

### Community 38 - "The 10-Step Mandatory Protocol"
Cohesion: 0.15
Nodes (12): Cross-System Gameplay Feature Workflow, Invocation in Antigravity, Step 10: Final Verification Report, Step 1: Restate Requested Outcome and Non-Goals, Step 2: Classify Change-Impact Tier, Step 3: Graphify Impact Query Before Reading Broad Source Files, Step 4: Reading Only Relevant Module READMEs, Hub Maps, and Targeted Files, Step 5: Short Written Implementation Plan (+4 more)

### Community 39 - "generate_db.py"
Cohesion: 0.23
Nodes (10): build_player(), generate_league(), main(), generate_db.py — Generates Layer 4 Club World JSON databases for PowerFootball…, get_club_staff(), get_free_agent_staff(), make_player_dob(), make_player_languages() (+2 more)

### Community 40 - "lint_scope.py"
Cohesion: 0.31
Nodes (11): count_bracket_delta(), format_xml_output(), get_all_gd_files(), get_line_indent(), lint_file_scope(), lint_lambda_and_callable(), main(), lint_scope.py — Scope and Dead-Code AST Linter for PowerFootball-2D (GDScript… (+3 more)

### Community 41 - "Readme"
Cohesion: 0.14
Nodes (14): Readme, Architecture Overview, Camera Systems MatchCameragd, HUD Rendering Contract, HUDgd MatchHUD, Key Scenes, MainMenutscn, MatchStatsUItscn (+6 more)

### Community 42 - "Graphify Lifecycle & Agent Navigation Protocol — PowerFootball-2D"
Cohesion: 0.15
Nodes (12): 1.1. Initial Build, 1.2. Normal Update (Incremental Sync), 1.3. Update After Source Changes (Verification Battery), 1.4. Update After Git Operations (Hooks & Merge Driver), 1. Project-Local Graphify Lifecycle, 2.1. When Graphify MUST Be Queried, 2.2. Important Scope Clarification, 2. Agent Navigation Protocol (Claude Code & Antigravity) (+4 more)

### Community 43 - "**Agent-Based Dressing Room Dynamics: Graph-Theoretic Morale Propagation and Mutiny Simulation in Godot 4**"
Cohesion: 0.15
Nodes (12): **Agent-Based Dressing Room Dynamics: Graph-Theoretic Morale Propagation and Mutiny Simulation in Godot 4**, **Algorithmic Design: Bitmask Bron–Kerbosch with Pivoting**, **Citerade verk**, **Compatibility Layer and Stub Ecosystem**, **Computational Architecture and Theoretical Framework**, **Empirical Validation and Regression Testing**, **Implementation: Social Dynamics Engine**, **Mathematical Modeling of Social Dynamics** (+4 more)

### Community 44 - "Readme"
Cohesion: 0.15
Nodes (13): Readme, CollisionLayersgd, Data Models, FormationAnchorMathgd, ManagerDatagd, PassUtilityScorergd, PlayerDatagd, PlayerRoleConfiggd (+5 more)

### Community 45 - "spatial_grid_bench.py"
Cohesion: 0.23
Nodes (7): benchmark_grid(), benchmark_linear_scan(), generate_match_positions(), main(), spatial_grid_bench.py — 22-Entity Spatial Query & Grid Cell Latency Benchmark.…, run_spatial_benchmark(), SpatialGrid

### Community 46 - "Ai Architect"
Cohesion: 0.17
Nodes (12): Ai Architect, Ai Architect, A shared scratch buffer must have exactly one live call site, AI & Spatial Decision Invariants, Child ready runs BEFORE parent ready, Defensive line depth is computed ONCE in MatchWorldModel never perdefender, GameEventsgoalscored carries no scorer by default — check the source not the READMEs, Group scans that must NOT be routed through MatchWorldModel (+4 more)

### Community 47 - "Readme"
Cohesion: 0.17
Nodes (12): Readme, Adding a New Autoload, autoloads/ — Singletons & Global Services, DataLoadergd, GameEventsgd, GameManagergd, InputHelpergd, Key Responsibilities (+4 more)

### Community 48 - "Claude"
Cohesion: 0.15
Nodes (13): Claude, Architectural Choke Points, Boot Order projectgodot, CLAUDEmd — Agent Entry Point, Context Budget — Claude Code Sessions, Process Priority, READ FIRST, Shared Agent Memory (+5 more)

### Community 49 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.11
Nodes (18): 1. Purpose and Non-Responsibilities, 2. Public API, Signals, Events, Contracts & Dependencies, 3. State Model & Architectural Invariants, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: HeavyPlayerController, Brain / Controller Choke Point (+10 more)

### Community 50 - "Compounded corrections — verified against the source"
Cohesion: 0.18
Nodes (10): Career Mode (Layer 1) Invariants, Compounded corrections — verified against the source, gdcheck cannot see through autoloads — use lint_xref, Inbox options are deliberately NOT serialised, Match side is NOT the league team index, squad_index IS the identity, so removing a player renumbers everyone behind them, The career -> match bridge is the quick-sim result folded back by CareerManager, The season calendar is derived, never a fixed weekly rhythm (+2 more)

### Community 51 - "Query"
Cohesion: 0.18
Nodes (11): Query, Find best matching node, Find bestmatching start nodes, For /graphify explain, For /graphify path, graphify reference: query path explain, or: graphify query "QUESTION" dfs budget 3000, Score each node by term overlap for ranked output (+3 more)

### Community 52 - "**Mathematical Calibration of Player Development and Senescence in Association Football Simulation**"
Cohesion: 0.18
Nodes (10): **Attribute Family Calibration and Archetype Architecture**, **Automated Parameter Estimation Pipeline: tools/fit\_age\_curves.py**, **Citerade verk**, **Domain Discrepancies and Methodological Boundaries**, **Empirical Biomechanical and Longitudinal Foundations**, **Engine Runtime Architecture: PlayerDevelopmentEngine.gd**, **Mathematical Calibration of Player Development and Senescence in Association Football Simulation**, **Mathematical Formulation and Functional Form Selection** (+2 more)

### Community 53 - "benchmark_math.py"
Cohesion: 0.40
Nodes (10): calculate_intercept_point_fast(), calculate_psxg_fast(), calculate_xg_fast(), clampf(), is_lane_blocked_fast(), main(), quadratic_decay(), benchmark_math.py — Mathematical Solvers Micro-Benchmark Suite. Micro-… (+2 more)

### Community 54 - "fuzz_utility_scorer.py"
Cohesion: 0.30
Nodes (12): 1. Purpose and Non-Responsibilities, Non-Responsibilities, Purpose, clampf(), quadratic_decay(), fuzz_utility_scorer.py — Property-Based Fuzzer for AI Utility Scoring., run_fuzz_tests(), score_dribble() (+4 more)

### Community 55 - "test_quick_sim.py"
Cohesion: 0.32
Nodes (11): compute_analytical_probs(), dixon_coles_tau(), main(), poisson_pmf(), tools/test_quick_sim.py Automated validation suite for PowerFootball-2D…, test_home_advantage(), test_player_rating_formula(), test_probability_distribution() (+3 more)

### Community 56 - "validate_schemas.py"
Cohesion: 0.36
Nodes (8): format_xml_output(), main(), validate_schemas.py — Strict JSON Schema & Invariant Validator for…, run_all_schema_validations(), SchemaViolation, validate_league_schema(), validate_managers_schema(), validate_referees_schema()

### Community 57 - "Career Mode"
Cohesion: 0.20
Nodes (10): Career Mode, Career Mode Layer 4 Invariants, gdcheck cannot see through autoloads — use lintxref, Inbox options are deliberately NOT serialised, Match side is NOT the league team index, squadindex IS the identity so removing a player renumbers everyone behind them, The career > match bridge runs through PlayerFactory once per player per bind, The season calendar is derived never a fixed weekly rhythm (+2 more)

### Community 58 - "Scene Tree, Node Hierarchy & Cross-Referencing Errata"
Cohesion: 0.20
Nodes (10): Cross-Module Architecture Findings, ERR-20260901-01, ERR-20260910-01, Error Logs, Non-ASCII identifiers parse here but not in Godot, Remediation, Scene Tree, Node Hierarchy & Cross-Referencing Errata, Self inside lambda closure parse failures in GDScript 2.0 (+2 more)

### Community 59 - "Llms"
Cohesion: 0.20
Nodes (10): Llms, 1 Vision & Architectural Invariants, 2 FiveLayer Simulation Stack Semantic Routing, 3 Tooling & Automation, Layer 1 — Physics & Kinematics, Layer 2 — Match AI & Spatial Navigation, Layer 3 — Match Social & Dynamic Psychology, Layer 4 — Club World & Persistent Entities (+2 more)

### Community 60 - "gdscript_slice_server.py"
Cohesion: 0.28
Nodes (8): pathlib, extract_signatures(), walk(), handle_request(), main(), MCP Server for GDScript 2.0 AST Slicing. Uses tree-sitter-gdscript to return…, tree_sitter, tree_sitter_gdscript

### Community 61 - "sys"
Cohesion: 0.16
Nodes (12): json, sys, find_gd_files(), get_autoload_map(), main(), parse_file_symbols(), parse_function_signature(), Any (+4 more)

### Community 62 - "lint_type_comparisons.py"
Cohesion: 0.36
Nodes (7): ComparisonViolation, format_xml_output(), get_all_gd_files(), lint_file_comparisons(), main(), lint_type_comparisons.py — Type Comparison & Object-Literal Safety Linter for…, run_comparison_linter()

### Community 63 - "DeterministicMatchSimulator"
Cohesion: 0.33
Nodes (3): DeterministicMatchSimulator, Packs the complete simulation state into binary representation for exact…, 60Hz Headless Match Physics & AI Simulator with PRNG seeding.

### Community 64 - "Architecture Hub: CareerManager"
Cohesion: 0.25
Nodes (7): 1. Purpose and Non-Responsibilities, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: CareerManager, Non-Responsibilities, Purpose

### Community 65 - "Context Hygiene"
Cohesion: 0.22
Nodes (9): Context Hygiene, Context Budget Tracking, CORRECT — pasted summary, PreLoad Rule, PROHIBITED, Scope Rule, Session State: date model, Tool Output Rule (+1 more)

### Community 66 - "Exports"
Cohesion: 0.22
Nodes (9): Exports, graphify reference: extra exports and benchmark, Step 6b  Wiki only if wiki flag, Step 7  Neo4j export only if neo4j or neo4jpush flag, Step 7a  FalkorDB export only if falkordb or falkordbpush flag, Step 7b  SVG export only if svg flag, Step 7c  GraphML export only if graphml flag, Step 7d  MCP server only if mcp flag (+1 more)

### Community 67 - "Github And Merge"
Cohesion: 0.22
Nodes (9): Github And Merge, Add backend gemini|kimi|openai|deepseek|claudecli depending on which API key you have set, Clone each repo run the full pipeline on each then merge, graphify reference: GitHub clone and crossrepo merge, Run /graphify on each local path to produce their graphjson files, Step 0  Clone GitHub repos only if a GitHub URL was given, Then merge:, Then merge at the project root: (+1 more)

### Community 68 - "Physics, Ball Dynamics & Kinematics Errata"
Cohesion: 0.22
Nodes (9): bicycle-kick-dominates-ambiguous-facing, Discovered Rules, dribble-claim-ignores-existing-possessor-dual-driver-jitter, dribble-magnet-forward-overshoot-oscillation, eval-harness-index-phase-and-claim-gate-were-structural-artifacts, eval-simulation-harness-was-decoupled-from-gdscript-tuning, Physics, Ball Dynamics & Kinematics Errata, Table of Contents (+1 more)

### Community 69 - "Set Pieces & Restarts Errata"
Cohesion: 0.22
Nodes (9): Discovered Rules, ERR-20260831-01, ERR-20260831-02, ERR-20260831-03, Error Logs, kickoff-backward-pass-veto-starves-taker, Set Pieces & Restarts Errata, Table of Contents (+1 more)

### Community 70 - "fuzz_formations.py"
Cohesion: 0.33
Nodes (9): enum, clampf(), get_dynamic_anchor_position(), lerpf(), main(), fuzz_formations.py — Dynamic Formation Anchor Property & Boundary Fuzzer.…, Role, run_formation_fuzzer() (+1 more)

### Community 71 - "worktree_manager.py"
Cohesion: 0.56
Nodes (8): cmd_cleanup(), cmd_create(), cmd_list(), cmd_merge(), cmd_verify(), main(), worktree_manager.py — Isolated Git Worktree Sandbox & Verification Manager.…, run_cmd()

### Community 72 - "football-expert"
Cohesion: 0.43
Nodes (7): PYTHONIOENCODING, PYTHONUNBUFFERED, C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe, py, football-expert, graphify, powerfootball

### Community 73 - "Gdscript Antipatterns"
Cohesion: 0.43
Nodes (8): Gdscript Antipatterns, 1 Object vs Literal Equality Comparisons, 2 Function Scope & Duplicate Declaration Rules, 3 HotPath ZeroAllocation Discipline, 4 Distance Calculation Discipline, 5 StringName Literal Discipline, GDScript 20 AntiPatterns & Postmortem Safeguards, Gdscript Antipatterns

### Community 74 - "football-expert"
Cohesion: 0.43
Nodes (7): PYTHONIOENCODING, PYTHONUNBUFFERED, C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe, py, football-expert, graphify, powerfootball

### Community 75 - "Complete Item Migration Manifest"
Cohesion: 0.25
Nodes (8): Agent Errata & Lessons Learned Index, Ambiguous Entries Report, Complete Item Migration Manifest, Discovered Rules (24 Items), Error Logs (7 Items), Narrative Subsections (4 Items), Session Handoff States, Topic Reference Pages

### Community 76 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.29
Nodes (7): 2. Public API, Signals, Events, Contracts & Dependencies, Core Dependencies, Enums & Constants, Key Public Methods, Process Mode & Boot Order, Public Properties, Signals & Event Bus

### Community 77 - "Architecture Hub: MatchWorldModel"
Cohesion: 0.25
Nodes (7): 1. Purpose and Non-Responsibilities, 4. Change-Impact Checklist, 5. Known Risks & Errata Search Terms, 6. Sources Examined, Architecture Hub: MatchWorldModel, Non-Responsibilities, Purpose

### Community 78 - "Readme"
Cohesion: 0.25
Nodes (8): Readme, Architecture at a Glance, Controls, First Setup in Godot, Measured behaviour of the weight model 75kg defaults, PowerFootball 2D, Running it, What's Next?

### Community 79 - "generate_phony_db.py"
Cohesion: 0.50
Nodes (7): clamp(), generate_manager(), generate_player(), generate_staff(), generate_world(), get_stature(), tools/generate_phony_db.py Generates a complete, realistic fictional world…

### Community 80 - "argparse"
Cohesion: 0.13
Nodes (18): argparse, socket, audit_process_modes(), main(), audit_process_modes.py — Process Mode Consistency Auditor. Audits all `.gd` and…, check_file_allocations_and_distance(), find_gd_files(), main() (+10 more)

### Community 81 - "test_pass_starvation.py"
Cohesion: 0.60
Nodes (5): calculate_pass_starvation_delta(), clampf(), lerp(), tools/test_pass_starvation.py Targeted property and integration test suite for…, run_tests()

### Community 82 - "Match State, Pacing & Urgency Errata"
Cohesion: 0.29
Nodes (7): Discovered Rules, manager-risk-profile-is-derived-not-authored, match-stage-boundaries-are-fractions-not-literal-seconds, Match State, Pacing & Urgency Errata, possession-hold-timer-has-two-non-interchangeable-variants, stage-3-fraction-is-83-percent-not-90-and-urgency-doesnt-self-saturate, Table of Contents

### Community 83 - "UI, HUD & Signal Bus Errata"
Cohesion: 0.29
Nodes (7): ball-struck-signal-arg-count-mismatch, Discovered Rules, ERR-20260830-02, Error Logs, Table of Contents, touchline-bubble-is-one-shared-instance-home-perspective-only, UI, HUD & Signal Bus Errata

### Community 84 - "dump_dep_graph.py"
Cohesion: 0.35
Nodes (9): calculate_blast_radius(), export_graph_json(), get_layer(), main(), print_blast_radius_report(), Any, dump_dep_graph.py — Static Dependency DAG & Blast Radius Analyzer for…, scan_repository() (+1 more)

### Community 85 - "tscn_linter.py"
Cohesion: 0.36
Nodes (7): format_xml_output(), get_all_tscn_files(), lint_tscn_file(), main(), tscn_linter.py — Scene Graph & TSCN Static Invariant Linter for…, run_tscn_linter(), TSCNViolation

### Community 87 - "Engine: Godot 4.7-stable | GDScript 2.0 ONLY | Strict Static Typing"
Cohesion: 0.29
Nodes (6): ARCHITECTURAL CHOKE POINTS & LAYER BOUNDARIES, CRITICAL SYNTAX RULES: ZERO-TOLERANCE ENFORCEMENT, Engine: Godot 4.7-stable | GDScript 2.0 ONLY | Strict Static Typing, GEMINI.md - Google Antigravity & Gemini 3.8 Flash Protocol, Graphify-First Tool Routing, VERIFICATION

### Community 88 - "Soccer Physics"
Cohesion: 0.22
Nodes (9): Soccer Physics, Compounded corrections — verified against the source, Soccer Physics, Ball friction is PROPORTIONAL not a constant deceleration, FEEL pass proportional friction / gaussian scatter, PowerFootball2d Physics Invariants, Pseudo3DBallpredicttrajectory returns RENDER points not ground points, Pseudo3DBallsimulatexyaxis (+1 more)

### Community 89 - "perf-benchmark"
Cohesion: 0.53
Nodes (6): perf-benchmark, 1 Mathematical Solvers MicroBenchmark, 2 Spatial Hash Grid Latency Benchmark, Execution Commands, Performance Benchmark & Solvers Profiling Skill, perf-benchmark

### Community 90 - "Errata Session History & Handoff Logs"
Cohesion: 0.33
Nodes (6): Architectural & Gotcha Findings from this Session, Errata Session History & Handoff Logs, Next Steps Handoff, Recent Session State Archive, Session State: 2026-09-02 (Manager Career Mode, Phase 4), Table of Contents

### Community 91 - "Graphify Knowledge Graph Setup"
Cohesion: 0.33
Nodes (5): Graphify Knowledge Graph Setup, Initialization, Installation, Query Commands, Refresh

### Community 92 - "CLIProxyAPI Setup Instructions"
Cohesion: 0.33
Nodes (5): CLIProxyAPI Setup Instructions, Configuration, Installation, Running, Verification

### Community 93 - "expand_database.py"
Cohesion: 0.53
Nodes (5): generate_manager(), generate_player(), generate_staff(), main(), tools/expand_database.py Generates 8 realistic Division 2 (Tier 2) clubs…

### Community 94 - "formation_ascii.py"
Cohesion: 0.67
Nodes (5): calculate_phase_positions(), display_all_phases(), main(), formation_ascii.py — Terminal ASCII Tactical Pitch & Formation Spacing…, render_ascii_pitch()

### Community 95 - "lint_stringnames.py"
Cohesion: 0.47
Nodes (4): check_file(), find_gd_files(), main(), lint_stringnames.py — StringName Literal Enforcement Linter. Audits all…

### Community 96 - "os"
Cohesion: 0.09
Nodes (24): html, os, Path, shutil, subprocess, time, prune_brain_store(), LRU-based Antigravity brain store pruner. Purges sessions older than 12 hours… (+16 more)

### Community 97 - "GDScript 2.0 & Simulation Architectural Invariants"
Cohesion: 0.40
Nodes (4): ARCHITECTURAL CHOKE POINTS & LAYER BOUNDARIES, CRITICAL SYNTAX RULES: ZERO-TOLERANCE ENFORCEMENT, GDScript 2.0 & Simulation Architectural Invariants, VERIFICATION

### Community 98 - "ast-refactor"
Cohesion: 0.60
Nodes (5): ast-refactor, AST Refactor & Invariant Preservation Skill, Strict Refactoring Rules, Verification Loop, ast-refactor

### Community 99 - "Scratchpad"
Cohesion: 0.40
Nodes (5): Scratchpad, Active Invariants Checked, Antigravity Scratchpad — MultiStep Reasoning & Active State, Current Subsystem Focus, StepbyStep Task Plan

### Community 100 - "graphify"
Cohesion: 0.40
Nodes (4): Enforcement & Git Hooks, graphify, Non-Destructive Validation Checklist, Strict Context & Token Optimization Rules

### Community 101 - "Transcribe"
Cohesion: 0.40
Nodes (5): Transcribe, graphify reference: transcribe video and audio, print progress to stdout which would otherwise corrupt the JSON file 1392, Step 25  Transcribe video / audio files only if video files detected, Write the JSON from Python NOT a shell '>' redirect: transcribeall/Whisper

### Community 102 - "Data, Persistence & Career Calibration Errata"
Cohesion: 0.40
Nodes (5): Calibration is not optional, and the first guess was wrong twice, Career Calibration Findings, Data, Persistence & Career Calibration Errata, Table of Contents, The season calendar cannot be a fixed weekly rhythm

### Community 103 - "football-expert"
Cohesion: 0.40
Nodes (4): PYTHONIOENCODING, PYTHONUNBUFFERED, py, football-expert

### Community 104 - "replay_test.py"
Cohesion: 0.21
Nodes (11): hashlib, math, random, struct, generate_simulated_match_frames(), main(), dump_match_frames.py — Visual Match Frame Exporter for Multimodal Agent…, render_svg_frame() (+3 more)

### Community 105 - "git_pre_commit.py"
Cohesion: 0.47
Nodes (5): stat, install_hook(), main(), git_pre_commit.py — Git Pre-Commit Hook Installer & Runner. Executes the…, run_checks()

### Community 106 - "lint_xref.py"
Cohesion: 0.36
Nodes (7): collect(), gd_files(), main(), lint_xref.py — cross-reference qualified member access against real…, (class_name, surface_set, source) for one .gd file., Remove string literals and trailing comments so paths are not scanned., strip_noise()

### Community 107 - "2. Public API, Signals, Events, Contracts & Dependencies"
Cohesion: 0.29
Nodes (7): 2. Public API, Signals, Events, Contracts & Dependencies, Constants & Enums, Core Dependencies, Key Public Methods, Process Priority & Boot Order, Public Data Properties, Signals & Event Bus

### Community 108 - "layer_context.py"
Cohesion: 0.60
Nodes (4): main(), print_layer_context(), layer_context.py — Targeted Simulation Layer Context Extractor. Extracts layer-…, read_rule_excerpt()

### Community 109 - "Roadmap"
Cohesion: 0.29
Nodes (7): Roadmap, PHASE 1 — Gameplay Completeness, PHASE 2 — Personality and Traits, PHASE 3 — Club World, PHASE 4 — Career Mode, PHASE 5 — Polish, ROADMAPmd

### Community 110 - "re"
Cohesion: 0.14
Nodes (4): re, audit_file_signal_races(), main(), lint_signal_races.py — Signal Emission & State Update Order Race Linter. Audits…

### Community 111 - "3. State Model & Architectural Invariants"
Cohesion: 0.50
Nodes (4): 3. State Model & Architectural Invariants, Push-Registration Invariant, Shared Defensive Line Contract, Zero Hot-Path Scene Querying

### Community 112 - "3. State Model & Architectural Invariants"
Cohesion: 0.50
Nodes (4): 3. State Model & Architectural Invariants, Career-to-Match Morale Seeding Invariant, Dynamic Calendar Spacing, Single Ownership Contract

### Community 113 - "Add Watch"
Cohesion: 0.50
Nodes (4): Add Watch, For /graphify add, For watch, graphify reference: add a URL and watch a folder

### Community 115 - "Telemetry, Diagnostics & Match Stats Errata"
Cohesion: 0.50
Nodes (4): crowding-space-creation-diagnostics, Discovered Rules, Table of Contents, Telemetry, Diagnostics & Match Stats Errata

### Community 127 - "Research Index"
Cohesion: 0.67
Nodes (3): Research Index, Consult before writing any code where implementation intent is unclear, Do not guess at physics values feel parameters or AI thresholds

## Knowledge Gaps
- **856 isolated node(s):** `C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe`, `tool_gatekeeper.sh script`, `C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe`, `py`, `PYTHONIOENCODING` (+851 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 1289 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **26 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Agents` connect `Agents` to `Api Surface`, `Course Implementation Specification`, `Anti Patterns`, `Readme`, `mcp_server.py`, `Agents Errata`, `Vector2`, `lint_invariants.py`, `Powerfootball Master Vision`, `AnalyticalSimulationHarness`, `Core Invariants`, `semantic_search.py`, `football_mcp.py`, `Math Solvers`, `Graphify Lifecycle & Agent Navigation Protocol — PowerFootball-2D`, `Claude`, `benchmark_math.py`, `sys`, `fuzz_formations.py`, `dump_dep_graph.py`, `os`, `replay_test.py`, `Roadmap`?**
  _High betweenness centrality (0.166) - this node is a cross-community bridge._
- **Why does `Api Surface` connect `Api Surface` to `Architecture Hub: CareerManager`, `Agents`, `Readme`, `Architecture Hub: MatchWorldModel`, `2. Public API, Signals, Events, Contracts & Dependencies`, `2. Public API, Signals, Events, Contracts & Dependencies`, `Llms`, `Architecture Hub: PitchScene`, `Architecture Hub: SetPieceCoordinator`?**
  _High betweenness centrality (0.125) - this node is a cross-community bridge._
- **Why does `Agents Errata` connect `Agents Errata` to `os`, `Architecture Hub: CareerManager`, `Course Implementation Specification`, `Agents`, `Readme`, `lint_xref.py`, `Powerfootball Master Vision`, `gdcheck.py`, `Architecture Hub: MatchWorldModel`, `Core Invariants`, `Claude`, `2. Public API, Signals, Events, Contracts & Dependencies`, `2. Public API, Signals, Events, Contracts & Dependencies`, `Llms`, `Architecture Hub: PitchScene`, `Architecture Hub: SetPieceCoordinator`?**
  _High betweenness centrality (0.115) - this node is a cross-community bridge._
- **Are the 4 inferred relationships involving `Api Surface` (e.g. with `Agents` and `dump_api.py`) actually correct?**
  _`Api Surface` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `Course Implementation Specification` (e.g. with `Agents` and `Core Invariants`) actually correct?**
  _`Course Implementation Specification` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 11 inferred relationships involving `Agents Errata` (e.g. with `Agents` and `Core Invariants`) actually correct?**
  _`Agents Errata` has 11 INFERRED edges - model-reasoned connections that need verification._
- **What connects `C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe`, `tool_gatekeeper.sh script`, `C:\Users\emanu\AppData\Roaming\uv\tools\graphifyy\Scripts\python.exe` to the rest of the system?**
  _856 weakly-connected nodes found - possible documentation gaps or missing edges._