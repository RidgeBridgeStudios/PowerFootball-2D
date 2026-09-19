#!/usr/bin/env python3
"""data_pipeline/clients.py -- cached API clients for the football data sources.

Every response lands in the SQLite cache at data/cache.db, keyed by
sha256(source + endpoint + sorted params), so a repeat call within the TTL never
touches the network. API keys come from the environment:

    BZZOIRO_API_KEY, FOOTBALL_DATA_API_KEY

TheSportsDB needs no key (the free "3" key is part of the base URL) and
StatsBomb open data needs no key either -- it is cache-only after the first fetch.
"""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from contextlib import closing
from typing import Any, Callable

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_PATH = os.path.join(REPO_ROOT, "data", "cache.db")

MAX_RETRIES = 5
RETRY_STATUS = {429, 500, 502, 503, 504}
TIMEOUT_SECONDS = 30.0

# --- SQLite cache ---------------------------------------------------------

_SCHEMA = """
CREATE TABLE IF NOT EXISTS cache (
    key TEXT PRIMARY KEY,
    source TEXT,
    response TEXT,
    fetched_at TIMESTAMP,
    ttl_seconds INTEGER
)
"""


def _db() -> sqlite3.Connection:
    """Open the cache database, creating the schema on first use."""
    connection = sqlite3.connect(CACHE_PATH, timeout=30.0)
    connection.execute(_SCHEMA)
    return connection


def cache_key(source: str, endpoint: str, params: dict[str, Any]) -> str:
    """Stable sha256 key over source, endpoint and order-independent params."""
    blob = json.dumps([source, endpoint, sorted(params.items())], default=str)
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def cache_get(key: str) -> Any | None:
    """Return the cached JSON payload, or None when absent or past its TTL."""
    with closing(_db()) as connection:
        row = connection.execute(
            "SELECT response FROM cache WHERE key = ? "
            "AND fetched_at > datetime('now', '-' || ttl_seconds || ' seconds')",
            (key,),
        ).fetchone()
    return json.loads(row[0]) if row else None


def cache_put(key: str, source: str, response: Any, ttl_seconds: int) -> None:
    """Write one JSON payload, stamping fetched_at in UTC."""
    with closing(_db()) as connection:
        connection.execute(
            "INSERT OR REPLACE INTO cache VALUES (?, ?, ?, datetime('now'), ?)",
            (key, source, json.dumps(response), ttl_seconds),
        )
        connection.commit()


# --- Rate limiting --------------------------------------------------------

class RateLimiter:
    """Thread-safe token bucket. rate is tokens/sec (0 = unlimited), burst is capacity."""

    def __init__(self, rate: float, burst: float = 1.0) -> None:
        self.rate: float = rate
        self.burst: float = max(burst, 1.0)
        self._tokens: float = self.burst
        self._stamp: float = time.monotonic()
        self._lock: threading.Lock = threading.Lock()

    def acquire(self) -> None:
        """Block until one token is available."""
        if self.rate <= 0:
            return
        with self._lock:
            while True:
                now = time.monotonic()
                self._tokens = min(self.burst, self._tokens + (now - self._stamp) * self.rate)
                self._stamp = now
                if self._tokens >= 1.0:
                    self._tokens -= 1.0
                    return
                time.sleep((1.0 - self._tokens) / self.rate)


# --- HTTP -----------------------------------------------------------------

def _env(name: str) -> str:
    """Read a required API key from the environment."""
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"missing environment variable {name}")
    return value


def http_json(
    url: str,
    headers: dict[str, str],
    timeout: float = TIMEOUT_SECONDS,
    retries: int = MAX_RETRIES,
) -> Any:
    """GET a URL and decode JSON, retrying 429/5xx/connection errors with exponential backoff."""
    request = urllib.request.Request(url, headers=headers)
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code not in RETRY_STATUS or attempt == retries:
                raise
        except urllib.error.URLError:
            if attempt == retries:
                raise
        time.sleep(2.0 ** attempt)
    raise AssertionError("unreachable")


# --- Base client ----------------------------------------------------------

class CachedSource:
    """Cache-first client. Subclasses set SOURCE, BASE, TTL, RATE and BURST."""

    SOURCE: str = ""
    BASE: str = ""
    TTL: int = 86400
    RATE: float = 0.0
    BURST: float = 1.0

    def __init__(self) -> None:
        self._limiter: RateLimiter = RateLimiter(self.RATE, self.BURST)

    def _headers(self) -> dict[str, str]:
        return {}

    def _fetch(self, endpoint: str, params: dict[str, Any]) -> Any:
        url = self.BASE + endpoint
        if params:
            url += "?" + urllib.parse.urlencode(sorted(params.items()))
        return http_json(url, self._headers())

    def get(self, endpoint: str, ttl: int | None = None, **params: Any) -> Any:
        """Return the cached payload for endpoint+params, fetching it on a miss."""
        params = {name: value for name, value in params.items() if value is not None}
        key = cache_key(self.SOURCE, endpoint, params)
        cached = cache_get(key)
        if cached is not None:
            return cached
        self._limiter.acquire()
        data = self._fetch(endpoint, params)
        cache_put(key, self.SOURCE, data, self.TTL if ttl is None else ttl)
        return data


# --- Sources --------------------------------------------------------------

class BzzoiroClient(CachedSource):
    """Bzzoiro Sports Data (https://sports.bzzoiro.com/docs/) -- no rate limit."""

    SOURCE = "bzzoiro"
    BASE = "https://sports.bzzoiro.com/api/"
    TTL = 86400

    def _headers(self) -> dict[str, str]:
        return {"Authorization": f"Token {_env('BZZOIRO_API_KEY')}"}

    def leagues(self) -> Any:
        return self.get("leagues/")

    def teams(self, country: str) -> Any:
        return self.get("teams/", country=country)

    def players(self, team: Any = None, position: str | None = None) -> Any:
        return self.get("players/", team=team, position=position)

    def player_stats(self, player: Any, event: Any = None, team: Any = None) -> Any:
        return self.get("player-stats/", player=player, event=event, team=team)


class TheSportsDBClient(CachedSource):
    """TheSportsDB free tier (key "3" is in the URL) -- throttled to 1 request/second."""

    SOURCE = "thesportsdb"
    BASE = "https://www.thesportsdb.com/api/v1/json/3/"
    TTL = 604800
    RATE = 1.0
    BURST = 1.0

    def search_teams(self, name: str) -> Any:
        return self.get("searchteams.php", t=name)

    def all_players(self, team_id: Any) -> Any:
        return self.get("lookup_all_players.php", id=team_id)

    def team(self, team_id: Any) -> Any:
        return self.get("lookupteam.php", id=team_id)

    def next_events(self, team_id: Any) -> Any:
        return self.get("eventsnext.php", id=team_id)


class FootballDataClient(CachedSource):
    """football-data.org v4 -- 10 requests/minute."""

    SOURCE = "football-data.org"
    BASE = "http://api.football-data.org/v4"
    TTL = 86400
    RATE = 10.0 / 60.0
    BURST = 10.0

    def _headers(self) -> dict[str, str]:
        return {"X-Auth-Token": _env("FOOTBALL_DATA_API_KEY")}

    def competition_teams(self, code: str) -> Any:
        return self.get(f"/competitions/{code}/teams")

    def team(self, team_id: Any) -> Any:
        return self.get(f"/teams/{team_id}")


class StatsBombClient(CachedSource):
    """StatsBomb open data via statsbombpy -- local reads, cached 30 days.

    Frames are cached as list[dict] records, so a cold call and a cache hit return
    the same shape.
    """

    SOURCE = "statsbomb"
    TTL = 30 * 86400

    def _fetch(self, endpoint: str, params: dict[str, Any]) -> Any:
        try:
            from statsbombpy import sb
        except ImportError as exc:  # pragma: no cover - dependency guard
            raise RuntimeError("statsbombpy not installed: pip install statsbombpy") from exc
        return getattr(sb, endpoint)(**params).to_dict(orient="records")

    def competitions(self) -> Any:
        return self.get("competitions")

    def matches(self, competition_id: int, season_id: int) -> Any:
        return self.get("matches", competition_id=competition_id, season_id=season_id)

    def events(self, match_id: int) -> Any:
        return self.get("events", match_id=match_id)

    def lineups(self, match_id: int) -> Any:
        return self.get("lineups", match_id=match_id)


# --- Checks ---------------------------------------------------------------

def _self_check() -> None:
    """Smallest thing that fails if the cache key, cache or limiter break."""
    assert cache_key("s", "/e", {"b": 1, "a": 2}) == cache_key("s", "/e", {"a": 2, "b": 1})
    assert cache_key("s", "/e", {"a": 2}) != cache_key("s", "/f", {"a": 2})
    cache_put("self-check", "test", {"ok": True}, 60)
    assert cache_get("self-check") == {"ok": True}
    cache_put("self-check-stale", "test", {"ok": True}, -1)
    assert cache_get("self-check-stale") is None
    limiter = RateLimiter(rate=10.0)
    start = time.monotonic()
    limiter.acquire()
    limiter.acquire()
    assert time.monotonic() - start >= 0.09, "second token was not throttled"
    assert RateLimiter(rate=0.0).acquire() is None
    print("self-check ok")


def _one(data: Any) -> Any:
    """First record of a list payload, else the payload itself."""
    return data[0] if isinstance(data, list) and data else data


def _demo() -> None:
    """Fetch one team (or the nearest equivalent) from each source."""
    _self_check()
    probes: list[tuple[str, Callable[[], Any]]] = [
        ("bzzoiro", lambda: BzzoiroClient().teams(country="England")),
        ("thesportsdb", lambda: TheSportsDBClient().search_teams("Arsenal")),
        ("football-data.org", lambda: FootballDataClient().team(57)),  # 57 = Arsenal FC
        ("statsbomb", lambda: StatsBombClient().competitions()),
    ]
    for name, call in probes:
        try:
            print(f"[{name}] {json.dumps(_one(call()), default=str)[:300]}")
        except Exception as exc:
            print(f"[{name}] skipped: {type(exc).__name__}: {exc}")


if __name__ == "__main__":
    _demo()
