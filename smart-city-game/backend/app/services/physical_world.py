from datetime import datetime, timedelta
import random
from ..repositories import assignments_repo
from . import clock

_trips: dict[int, dict] = {}


def schedule_trip(
    assignment_id: int,
    zona_origen: int,
    zona_destino: int,
    timestamp_asignacion: datetime,
    sla_minutos: int | None = None,
):
    same_zone = zona_origen == zona_destino
    late_chance = 0.10 if same_zone else 0.50
    is_late = random.random() < late_chance

    sla = sla_minutos if sla_minutos and sla_minutos > 0 else 5

    # Duracion del viaje EN TIEMPO SIMULADO, relativa al SLA del incidente:
    #  - is_late: supera el SLA -> la BD (sp_CalcularPenalizacion) penaliza.
    #  - en hora: queda dentro del SLA -> sin penalizacion.
    if is_late:
        viaje = timedelta(minutes=sla + random.uniform(1.0, sla))
    else:
        viaje = timedelta(minutes=random.uniform(0.2, max(0.5, sla * 0.7)))

    atencion = timedelta(minutes=random.uniform(0.5, 2.0))

    # Valor ESCRITO en la BD: anclado a timestamp_asignacion (reloj real de la BD,
    # CURRENT_TIMESTAMP). Asi (timestamp_llegada - timestamp_asignacion) == viaje y
    # el SLA, que compara ambos timestamps, penaliza de forma coherente.
    llegada_valor = timestamp_asignacion + viaje
    finalizacion_valor = llegada_valor + atencion

    # Disparo/animacion EN RELOJ SIMULADO (respeta pausa y escala). La espera real
    # del jugador es viaje / ESCALA_TIEMPO (ver specs.md §15).
    base_sim = clock.sim_now()
    fire_llegada = base_sim + viaje
    fire_finalizacion = fire_llegada + atencion

    _trips[assignment_id] = {
        "assignment_id": assignment_id,
        "zona_origen": zona_origen,
        "zona_destino": zona_destino,
        "fire_llegada": fire_llegada,
        "fire_finalizacion": fire_finalizacion,
        "llegada_valor": llegada_valor,
        "finalizacion_valor": finalizacion_valor,
        "is_late": is_late,
        "arrived": False,
        "finished": False,
    }

    return _trips[assignment_id]


def get_active_trips() -> list[dict]:
    return [
        {
            "assignment_id": k,
            "zona_origen": v["zona_origen"],
            "zona_destino": v["zona_destino"],
            "arrived": v["arrived"],
            "finished": v["finished"],
            "is_late": v["is_late"],
        }
        for k, v in _trips.items()
        if not v["finished"]
    ]


def process_arrivals_sync():
    now_sim = clock.sim_now()
    results = []

    for aid, trip in list(_trips.items()):
        if not trip["arrived"] and now_sim >= trip["fire_llegada"]:
            success = assignments_repo.set_arrival_sync(aid, trip["llegada_valor"])
            trip["arrived"] = True
            results.append({"assignment_id": aid, "status": "arrived", "success": success})

    return results


def process_finishes_sync():
    now_sim = clock.sim_now()
    results = []

    for aid, trip in list(_trips.items()):
        if trip["arrived"] and not trip["finished"] and now_sim >= trip["fire_finalizacion"]:
            success = assignments_repo.set_finish_sync(aid, trip["finalizacion_valor"])
            trip["finished"] = True
            results.append({"assignment_id": aid, "status": "finished", "success": success})

    return results
