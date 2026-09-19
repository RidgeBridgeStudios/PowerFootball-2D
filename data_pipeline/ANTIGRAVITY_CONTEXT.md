# Project Context: PowerFootball-2D Database Integration

## Engine & Runtime Target
- **Engine:** Godot Engine 4.7 (GDScript 2.0)
- **SQLite Driver:** `godot-sqlite` (GDExtension)
- **Database File:** `powerfootball_master.db`
- **Storage Strategy:** Read-only template in `res://data/`, copied to `user://` on first launch for writable save games.

## Active System Metrics
- **Competition Types:** {'CONTINENTAL_CUP': 33, 'DOMESTIC_CUP': 77, 'DOMESTIC_LEAGUE': 183}
- **Player Gender Breakdown:** {'men': 90070, 'women': 5305}
- **Team Gender Breakdown:** {'men': 5708, 'women': 239}

## Database Schema & Table Volume
| Table Name | Row Count | Primary Key | Key Foreign Keys |
| :--- | :--- | :--- | :--- |
| `leagues` | 293 | `league_id` | None |
| `seasons` | 226 | `season_id` | None |
| `venues` | 3,653 | `venue_id` | None |
| `teams` | 5,947 | `team_id` | None |
| `coaches` | 10,907 | `coach_id` | None |
| `team_rivals` | 1,223 | `team_id, rival_team_id` | None |
| `players` | 95,375 | `player_id` | None |
| `contracts` | 198,158 | `contract_id` | None |
| `tournament_participants` | 2,643 | `participant_id` | team_id -> teams.team_id, competition_id -> leagues.league_id, season_id -> seasons.season_id |

## Architectural Requirements for Generated GDScript
1. **Singleton Access (`DatabaseManager.gd`):** Must support global access via `DatabaseManager` autoload.
2. **Game Mode Isolation:** Every query fetching leagues, teams, or players must filter by `gender = current_game_mode` (`'men'` or `'women'`).
3. **Competition Routing:** Domestic leagues (`DOMESTIC_LEAGUE`) determine standings; cups and Champions League (`CONTINENTAL_CUP`) must query `tournament_participants`.
4. **Performance:** Match engine attributes (`mass`, `top_speed`, `vision`, `composure`, `reflexes`, etc.) must be instantiated as typed `Resource` objects (`PlayerData.gd`) to eliminate dictionary lookup overhead during 60 FPS simulations.

## Standard SQL Query Recipes
### 1. Fetch Squad Roster for Match Simulation
```sql
SELECT p.player_id, p.player_name, p.position_role, p.nationality,
       p.mass, p.top_speed, p.stamina_max, p.vision, p.composure,
       p.aggression, p.close_control, p.reflexes, p.determination, p.work_rate,
       c.jersey_number, c.position_name
FROM players p
JOIN contracts c ON p.player_id = c.player_id
WHERE c.team_id = ? AND p.gender = ?;
```

### 2. Fetch Active Tournament Participants (Champions League / Cups)
```sql
SELECT t.team_id, t.name, tp.seed_status, tp.stage_reached
FROM tournament_participants tp
JOIN teams t ON tp.team_id = t.team_id
WHERE tp.season_id = ? AND tp.competition_id = ?;
```
