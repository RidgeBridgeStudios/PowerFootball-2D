## Football Domain Intelligence (`football-expert` MCP server)

A local, offline football-analytics reference is available as an MCP server: `football-expert` (`tools/football_mcp.py`, backed by the SQLite knowledge base at `.agents/football_domain.db`, built by `scripts/build_football_kb.py`). It holds curated kinematic/tactical benchmark ranges, IFAB Law summaries, known match-AI tactical anomaly patterns, and minimum action-transition latencies — compiled from public sports-science/tracking-data ranges and the IFAB Laws of the Game. Treat its numeric bounds as tuning-plausibility heuristics, not hard physical constants.

### When to call it

Call these tools when the task is actually about football realism, not on every incidental mention of a football-flavored word:

- **`verify_kinematics`** — when tuning or reviewing a movement constant (speed, acceleration, turn rate, shot/pass velocity, ball friction) in `entities/player/HeavyPlayerController.gd`, `entities/ball/Pseudo3DBall.gd`, or similar, to sanity-check the new value against human/physics plausibility bounds.
- **`audit_tactical_compactness`** — when tuning formation anchors, defensive line depth, or block shape in `shared/FormationAnchorMath.gd` / `autoloads/MatchWorldModel.gd`.
- **`query_ifab_rule`** — before modifying foul, card, offside, or restart logic (`MatchReferee`, `SetPieceCoordinator`).
- **`audit_action_transition`** — when tuning the minimum delay between two player FSM states.
- **`diagnose_tactical_deviation`** — when the user describes match-AI behavior that looks tactically wrong (e.g. "defenders don't track runs," "the team stretches out too much," "nobody presses as a unit"). It returns a hypothesis — the real-world expectation, the observed deviation, and the likely GDScript source file — to investigate, not a certain diagnosis. Confirm against the actual code before changing tuning values.

Do not call it for generic code questions, unrelated bugs, or every time the words "football," "position," or "tactics" appear — most of those are just normal GDScript/architecture work covered by the existing rules and Graphify.

### Keeping it current

If you add a new kinematic/tactical benchmark, IFAB rule, anomaly pattern, or transition latency, edit the seed data in `scripts/build_football_kb.py` and re-run `py -3 scripts/build_football_kb.py` to rebuild `.agents/football_domain.db` — don't hand-edit the `.db` file.
