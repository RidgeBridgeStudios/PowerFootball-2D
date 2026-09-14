## Football Domain Intelligence (`football-expert` MCP server)

A local, offline football-analytics reference is available as an MCP server: `football-expert` (`tools/football_mcp.py`, backed by the SQLite knowledge base at `.agents/football_domain.db`, built by `scripts/build_football_kb.py`). It holds curated kinematic/tactical benchmark ranges, IFAB Law summaries, known match-AI tactical anomaly patterns, and minimum action-transition latencies — compiled from public sports-science/tracking-data ranges and the IFAB Laws of the Game. Treat its numeric bounds as tuning-plausibility heuristics, not hard physical constants.

### When to call it

Call these tools when the task is actually about football realism, not on every incidental mention of a football-flavored word:

- **`verify_kinematics`** — when tuning a player attribute or shot/pass parameter that drives the statistical resolver (`shared/PlayerData.gd` movement/technical attributes consumed by `shared/QuickSimEngine.gd`, plus the retained `shared/UtilityMath.gd` solvers), to sanity-check the new value against human plausibility bounds. The archived real-time kinematics (`legacy/entities/player/HeavyPlayerController.gd`, `legacy/entities/ball/Pseudo3DBall.gd`) are historical reference only.
- **`audit_tactical_compactness`** — when tuning the manager's tactical inputs in `ui/manager_mode/TacticsPanel.gd` / `shared/TeamManagementData.gd` / `shared/FormationLibrary.gd`, or the defensive-line and pressing multipliers read by `shared/QuickSimEngine.gd`.
- **`query_ifab_rule`** — before modifying foul, card, or offside logic in `shared/QuickSimEngine.gd`, or the referee attributes in `shared/RefereeData.gd`.
- **`audit_action_transition`** — the pre-pivot player-FSM latency check. There is no live player FSM any more, so it applies only to the archived match layer under `legacy/`.
- **`diagnose_tactical_deviation`** — when the user describes simulated match behavior that looks tactically wrong (e.g. "defenders don't track runs," "the team stretches out too much," "nobody presses as a unit"). It returns a hypothesis — the real-world expectation, the observed deviation, and the likely GDScript source file — to investigate, not a certain diagnosis. Confirm against the actual code before changing tuning values.

Do not call it for generic code questions, unrelated bugs, or every time the words "football," "position," or "tactics" appear — most of those are just normal GDScript/architecture work covered by the existing rules and Graphify.

### Keeping it current

If you add a new kinematic/tactical benchmark, IFAB rule, anomaly pattern, or transition latency, edit the seed data in `scripts/build_football_kb.py` and re-run `py -3 scripts/build_football_kb.py` to rebuild `.agents/football_domain.db` — don't hand-edit the `.db` file.
