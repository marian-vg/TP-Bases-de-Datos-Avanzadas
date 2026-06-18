from __future__ import annotations

from datetime import datetime
from itertools import count
from typing import Any

from . import clock

_MAX_ITEMS = 120
_counter = count(1)
_feed: list[dict[str, Any]] = []
_seen_keys: set[str] = set()


def add(
    kind: str,
    title: str,
    message: str,
    zona_id: int | None = None,
    zona: str | None = None,
    severity: str = "info",
    dedupe_key: str | None = None,
    meta: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if dedupe_key and dedupe_key in _seen_keys:
        return {}
    if dedupe_key:
        _seen_keys.add(dedupe_key)

    item = {
        "id": next(_counter),
        "kind": kind,
        "severity": severity,
        "title": title,
        "message": message,
        "zona_id": zona_id,
        "zona": zona,
        "timestamp": datetime.utcnow().isoformat(),
        "sim_time": clock.sim_now().isoformat(),
        "meta": meta or {},
    }
    _feed.insert(0, item)
    del _feed[_MAX_ITEMS:]
    return item


def recent(limit: int = 60) -> list[dict[str, Any]]:
    return _feed[:limit]
