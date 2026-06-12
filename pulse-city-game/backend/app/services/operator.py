from datetime import datetime, timedelta
import asyncio
from ..repositories import events_repo
from . import mapping, clock

_pending_reviews: dict[int, dict] = {}
_pending_tasks: set = set()


def enqueue_operator_review(evento_id: int, zona_id: int, tipo_evento_id: int):
    _pending_reviews[evento_id] = {
        "evento_id": evento_id,
        "zona_id": zona_id,
        "tipo_evento_id": tipo_evento_id,
        "scheduled_at_real": datetime.utcnow().timestamp() + 15 + (hash(str(evento_id)) % 46),
    }


def get_pending_reviews() -> list[dict]:
    now = datetime.utcnow().timestamp()
    return [
        {"evento_id": v["evento_id"], "seconds_remaining": max(0, int(v["scheduled_at_real"] - now))}
        for v in _pending_reviews.values()
        if v["scheduled_at_real"] > now
    ]


def process_pending_reviews_sync():
    now = datetime.utcnow().timestamp()
    due = [
        (eid, v)
        for eid, v in _pending_reviews.items()
        if v["scheduled_at_real"] <= now
    ]
    results = []

    for evento_id, review in due:
        del _pending_reviews[evento_id]
        mapping_data = mapping.load_mapping_sync()

        incidencias = None
        for cat, info in mapping_data.items():
            if info["tipo_evento_id"] == review["tipo_evento_id"]:
                incidencias = info["incidentes"]
                break

        if incidencias and len(incidencias) > 0:
            inc = incidencias[0]
            sim = clock.sim_now()
            try:
                incidente_id = events_repo.insert_incidente_sync(
                    evento_id=evento_id,
                    tipo_incidente_id=inc["tipo_incidente_id"],
                    gravedad_id=inc["gravedad_id"],
                    zona_id=review["zona_id"],
                    sim_now=sim,
                    descripcion=f"Operador confirma incidente por evento {evento_id}",
                )
                results.append({"evento_id": evento_id, "incidente_id": incidente_id, "status": "promoted"})
            except Exception as e:
                results.append({"evento_id": evento_id, "error": str(e), "status": "failed"})
        else:
            results.append({"evento_id": evento_id, "status": "no_mapping"})

    return results
