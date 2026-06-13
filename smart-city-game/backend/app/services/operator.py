from datetime import datetime
import random

from ..repositories import events_repo
from ..config import OPERATOR_REVIEW_MIN_DELAY, OPERATOR_REVIEW_MAX_DELAY
from . import clock

_pending_reviews: dict[int, dict] = {}


def enqueue_operator_review(evento_id: int, zona_id: int, tipo_evento_id: int):
    delay = random.randint(OPERATOR_REVIEW_MIN_DELAY, OPERATOR_REVIEW_MAX_DELAY)
    _pending_reviews[evento_id] = {
        "evento_id": evento_id,
        "zona_id": zona_id,
        "tipo_evento_id": tipo_evento_id,
        "scheduled_at_real": datetime.utcnow().timestamp() + delay,
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

        # Mismo origen de verdad que el camino inmediato (>80%): el mapeo
        # tipo_evento -> tipo_incidente/gravedad vive en la BD, no en config del juego.
        mapeo = events_repo.get_promocion_mapeo_sync(review["tipo_evento_id"])

        if mapeo:
            sim = clock.sim_now()
            try:
                incidente_id = events_repo.insert_incidente_sync(
                    evento_id=evento_id,
                    tipo_incidente_id=mapeo["tipo_incidente_id"],
                    gravedad_id=mapeo["gravedad_id"],
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
