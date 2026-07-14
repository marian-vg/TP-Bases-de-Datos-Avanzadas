from datetime import datetime
import random

from ..repositories import events_repo
from ..config import OPERATOR_REVIEW_MIN_DELAY, OPERATOR_REVIEW_MAX_DELAY
from . import clock, game_feed

_pending_reviews: dict[str | int, dict] = {}
_review_counter = 0


def enqueue_operator_review(
    evento_id: int | None,
    zona_id: int,
    tipo_evento_id: int,
    sensor_id: int | None = None,
    sensor_nombre: str | None = None,
    tipo_sensor: str | None = None,
    sensor_confianza=None,
):
    global _review_counter
    _review_counter += 1
    review_key = evento_id if evento_id is not None else f"manual-{_review_counter}"

    mapeo = events_repo.get_promocion_mapeo_sync(tipo_evento_id)
    if not mapeo:
        mapeo = events_repo.get_accidente_fallback_mapeo_sync()
    gravedad_id = mapeo["gravedad_id"] if mapeo else 3

    delay = random.randint(OPERATOR_REVIEW_MIN_DELAY, OPERATOR_REVIEW_MAX_DELAY)
    _pending_reviews[review_key] = {
        "review_key": review_key,
        "evento_id": evento_id,
        "zona_id": zona_id,
        "tipo_evento_id": tipo_evento_id,
        "sensor_id": sensor_id,
        "sensor_nombre": sensor_nombre,
        "tipo_sensor": tipo_sensor,
        "sensor_confianza": float(sensor_confianza or 0),
        "delay_seconds": delay,
        "scheduled_at_real": datetime.utcnow().timestamp() + delay,
        "gravedad_id": gravedad_id,
    }
    
    msg = (
        f"Llamada ciudadana reporta emergencia en zona {zona_id}; validación estimada en {delay}s."
        if evento_id is None
        else f"La señal requiere validación manual; confirmación estimada en {delay}s."
    )
    game_feed.add(
        kind="operator",
        title="Llamada reportada" if evento_id is None else "Operador inicia revisión",
        message=msg,
        zona_id=zona_id,
        severity="warning",
        dedupe_key=f"review-start:{review_key}",
        meta={"reviewKey": review_key, "eventId": evento_id, "confidence": float(sensor_confianza or 0), "delay": delay},
    )
    return delay


def get_pending_reviews() -> list[dict]:
    now = datetime.utcnow().timestamp()
    pending = []
    for k, v in _pending_reviews.items():
        if v["scheduled_at_real"] <= now:
            continue
        pending.append({
            "review_key": k,
            "evento_id": v["evento_id"],
            "zona_id": v["zona_id"],
            "tipo_evento_id": v["tipo_evento_id"],
            "sensor_id": v.get("sensor_id"),
            "sensor_nombre": v.get("sensor_nombre"),
            "tipo_sensor": v.get("tipo_sensor"),
            "sensor_confianza": v.get("sensor_confianza", 0),
            "delay_seconds": v.get("delay_seconds"),
            "seconds_remaining": max(0, int(v["scheduled_at_real"] - now)),
            "gravedad_id": v.get("gravedad_id", 3),
        })
    return pending


def process_pending_reviews_sync():
    now = datetime.utcnow().timestamp()
    due = [
        (rk, v)
        for rk, v in _pending_reviews.items()
        if v["scheduled_at_real"] <= now
    ]
    results = []

    for review_key, review in due:
        del _pending_reviews[review_key]

        mapeo = events_repo.get_promocion_mapeo_sync(review["tipo_evento_id"])
        fallback_accidente = False
        if not mapeo:
            mapeo = events_repo.get_accidente_fallback_mapeo_sync()
            fallback_accidente = True

        if mapeo:
            sim = clock.sim_now()
            try:
                evento_id = review["evento_id"]
                incidente_id = events_repo.insert_incidente_sync(
                    evento_id=evento_id,
                    tipo_incidente_id=mapeo["tipo_incidente_id"],
                    gravedad_id=mapeo["gravedad_id"],
                    zona_id=review["zona_id"],
                    sim_now=sim,
                    descripcion=(
                        f"Llamado ciudadano: reporte de emergencia en zona {review['zona_id']}"
                        if evento_id is None
                        else (
                            f"Operador acredita accidente por evento {evento_id}"
                            if fallback_accidente
                            else f"Operador confirma incidente por evento {evento_id}"
                        )
                    ),
                )
                
                title = (
                    "Llamado confirmado"
                    if evento_id is None
                    else ("Operador acredita accidente" if fallback_accidente else "Operador confirma incidente")
                )
                msg = (
                    f"El reporte ciudadano de zona {review['zona_id']} fue validado como incidente {incidente_id}."
                    if evento_id is None
                    else (
                        f"El evento {evento_id} fue validado como accidente {incidente_id}."
                        if fallback_accidente
                        else f"El evento {evento_id} fue validado y se registró como incidente {incidente_id}."
                    )
                )
                game_feed.add(
                    kind="operator",
                    title=title,
                    message=msg,
                    zona_id=review["zona_id"],
                    severity="danger",
                    dedupe_key=f"review-promoted:{review_key}",
                    meta={"reviewKey": review_key, "eventId": evento_id, "incidentId": incidente_id},
                )
                results.append({"review_key": review_key, "incidente_id": incidente_id, "status": "promoted"})
            except Exception as e:
                results.append({"review_key": review_key, "error": str(e), "status": "failed"})
        else:
            results.append({"review_key": review_key, "status": "failed_no_fallback"})

    return results
