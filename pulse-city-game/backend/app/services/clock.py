from datetime import datetime, timedelta, timezone

_real_start: datetime | None = None
_sim_start: datetime | None = None
_time_scale: int = 20
_paused: bool = False
_paused_at_real: datetime | None = None
_paused_at_sim: datetime | None = None


def init_clock(scale: int = 20, start: datetime | None = None):
    global _real_start, _sim_start, _time_scale
    _time_scale = scale
    _real_start = datetime.now(timezone.utc)
    _sim_start = start if start else _real_start


def sim_now() -> datetime:
    global _paused, _paused_at_sim
    if _paused and _paused_at_sim is not None:
        return _paused_at_sim
    elapsed = (datetime.now(timezone.utc) - _real_start).total_seconds()
    sim_elapsed = elapsed * _time_scale
    return _sim_start + timedelta(seconds=sim_elapsed)


def real_from_sim(sim_dt: datetime) -> float:
    return (sim_dt - _sim_start).total_seconds() / _time_scale


def pause():
    global _paused, _paused_at_real, _paused_at_sim
    _paused = True
    _paused_at_real = datetime.now(timezone.utc)
    _paused_at_sim = sim_now()


def resume():
    global _paused, _paused_at_real, _paused_at_sim, _real_start, _sim_start
    if not _paused:
        return
    _paused = False
    pause_duration = (datetime.now(timezone.utc) - _paused_at_real).total_seconds()
    _real_start += timedelta(seconds=pause_duration)


def is_paused() -> bool:
    return _paused


def get_scale() -> int:
    return _time_scale


def get_status() -> dict:
    return {
        "scale": _time_scale,
        "paused": _paused,
        "simNow": sim_now().isoformat(),
        "realStart": _real_start.isoformat() if _real_start else None,
        "simStart": _sim_start.isoformat() if _sim_start else None,
    }
