import asyncio
import random
from . import clock, physical_world, operator
from ..db import get_pool
from ..repositories import assignments_repo
from .mapping import load_mapping_sync

_running = False
_tasks: list[asyncio.Task] = []
_auto_enabled = False
_auto_interval = 15
_last_auto_tick: float = 0
_last_sla_tick: float = 0
_last_reactivation_tick: float = 0
_cooldowns_until: dict[str, float] = {}
_last_errors: list[str] = []


def _remember_error(exc: Exception):
    _last_errors.append(str(exc))
    del _last_errors[:-5]


def _call_temporal_procedure_sync(procedure_name: str):
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(f"CALL {procedure_name}();")


def _tick_sync():
    global _last_auto_tick, _last_sla_tick, _last_reactivation_tick

    if clock.is_paused():
        return

    try:
        new_assignments = assignments_repo.get_open_assignments_without_arrival_sync()
        for a in new_assignments:
            aid = a["id_asignacion"]
            if aid not in physical_world._trips:
                physical_world.schedule_trip(
                    assignment_id=aid,
                    zona_origen=a["zona_origen"],
                    zona_destino=a["zona_destino"],
                    timestamp_asignacion=a["timestamp_asignacion"],
                )

        physical_world.process_arrivals_sync()
        physical_world.process_finishes_sync()
        operator.process_pending_reviews_sync()

        now_real = asyncio.get_event_loop().time()

        if now_real - _last_sla_tick >= 2:
            _last_sla_tick = now_real
            _call_temporal_procedure_sync("sp_EscalarIncidente")

        if now_real - _last_reactivation_tick >= 5:
            _last_reactivation_tick = now_real
            _call_temporal_procedure_sync("sp_ReactivarRecursos")

        if _auto_enabled:
            if now_real - _last_auto_tick >= _auto_interval:
                _last_auto_tick = now_real
                _generate_random_catastrophe_sync()

    except Exception as exc:
        _remember_error(exc)


def _generate_random_catastrophe_sync():
    mapping_data = load_mapping_sync()
    if not mapping_data:
        return

    from ..repositories import catalogs_repo, events_repo
    from ..config import CONFIDENCE_THRESHOLD

    catastrofes = list(mapping_data.keys())
    ahora = asyncio.get_event_loop().time()
    available = [c for c in catastrofes if _cooldowns_until.get(c, 0) <= ahora]
    if not available:
        return

    cat = random.choice(available)
    info = mapping_data[cat]
    sim = clock.sim_now()
    zona_id = random.randint(1, 12)

    tipos_sensor_ids = list(info["tipos_sensor_ids"].values()) if info["tipos_sensor_ids"] else []
    sensor = catalogs_repo.find_capable_sensor_sync(zona_id, tipos_sensor_ids)

    if sensor is None:
        return

    evento_id = events_repo.call_simular_eventos_sync(
        sensor_id=sensor["id_sensor"],
        tipo_evento_id=info["tipo_evento_id"],
    )
    if evento_id is None:
        return

    from . import mapping as mapping_svc
    cooldown = mapping_svc.get_cooldown_sync(cat)
    _cooldowns_until[cat] = ahora + cooldown

    if sensor["confianza"] <= CONFIDENCE_THRESHOLD:
        operator.enqueue_operator_review(
            evento_id=evento_id,
            zona_id=zona_id,
            tipo_evento_id=info["tipo_evento_id"],
        )


async def _loop():
    global _running
    _running = True
    while _running:
        _tick_sync()
        await asyncio.sleep(1)


def start(event_loop=None):
    global _tasks
    loop = event_loop or asyncio.get_event_loop()
    for t in _tasks:
        t.cancel()
    _tasks = [loop.create_task(_loop())]


def stop():
    global _running, _tasks
    _running = False
    for t in _tasks:
        t.cancel()
    _tasks = []


def set_auto(enabled: bool):
    global _auto_enabled, _last_auto_tick
    _auto_enabled = enabled
    import asyncio
    _last_auto_tick = asyncio.get_event_loop().time()


def is_auto() -> bool:
    return _auto_enabled


def get_status() -> dict:
    return {
        "auto": _auto_enabled,
        "paused": clock.is_paused(),
        "activeTrips": len(physical_world.get_active_trips()),
        "pendingReviews": len(operator.get_pending_reviews()),
        "lastErrors": list(_last_errors),
    }
