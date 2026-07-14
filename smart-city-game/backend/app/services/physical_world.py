from datetime import datetime, timedelta
import random
from ..repositories import assignments_repo
from . import clock, game_feed

_trips: dict[int, dict] = {}


def schedule_trip(
    assignment_id: int,
    zona_origen: int,
    zona_destino: int,
    timestamp_asignacion: datetime,
    sla_minutos: int | None = None,
    gravedad_id: int = 3,
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

    # Duración de la atención según gravedad (mínimo 15s reales = 5 min simulados a escala 20x)
    if gravedad_id == 1:
        atencion_minutos = random.uniform(5.0, 6.0)
    elif gravedad_id == 2:
        atencion_minutos = random.uniform(7.0, 8.0)
    elif gravedad_id == 3:
        atencion_minutos = random.uniform(9.0, 10.0)
    elif gravedad_id == 4:
        atencion_minutos = random.uniform(11.0, 13.0)
    elif gravedad_id == 5:
        atencion_minutos = random.uniform(15.0, 18.0)
    else:
        atencion_minutos = random.uniform(5.0, 10.0)

    atencion = timedelta(minutes=atencion_minutos)

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
        "fire_inicio": base_sim,
        "fire_llegada": fire_llegada,
        "fire_finalizacion": fire_finalizacion,
        "llegada_valor": llegada_valor,
        "finalizacion_valor": finalizacion_valor,
        "is_late": is_late,
        "arrived": False,
        "finished": False,
    }

    game_feed.add(
        kind="resource",
        title="Recurso despachado",
        message=f"Asignación A{assignment_id} viaja de zona {zona_origen} a zona {zona_destino}.",
        zona_id=zona_destino,
        severity="warning" if is_late else "info",
        dedupe_key=f"trip-start:{assignment_id}",
        meta={"assignmentId": assignment_id, "origin": zona_origen, "target": zona_destino, "isLateRisk": is_late},
    )
    return _trips[assignment_id]


def get_active_trips() -> list[dict]:
    now_sim = clock.sim_now()
    trips = []
    for k, v in _trips.items():
        if v["finished"]:
            continue
        started_at = v.get("fire_inicio", v["fire_llegada"])
        travel_seconds = max((v["fire_llegada"] - started_at).total_seconds(), 1)
        elapsed = (now_sim - started_at).total_seconds()
        progress = 1 if v["arrived"] else max(0, min(1, elapsed / travel_seconds))
        trips.append({
            "assignment_id": k,
            "zona_origen": v["zona_origen"],
            "zona_destino": v["zona_destino"],
            "arrived": v["arrived"],
            "finished": v["finished"],
            "is_late": v["is_late"],
            "progress": progress,
        })
    return trips


def process_arrivals_sync():
    now_sim = clock.sim_now()
    results = []

    for aid, trip in list(_trips.items()):
        if not trip["arrived"] and now_sim >= trip["fire_llegada"]:
            success = assignments_repo.set_arrival_sync(aid, trip["llegada_valor"])
            trip["arrived"] = True
            game_feed.add(
                kind="resource",
                title="Recurso llega a destino",
                message=f"Asignación A{aid} llegó a zona {trip['zona_destino']}.",
                zona_id=trip["zona_destino"],
                severity="warning" if trip["is_late"] else "success",
                dedupe_key=f"trip-arrive:{aid}",
                meta={"assignmentId": aid, "success": success, "isLate": trip["is_late"]},
            )
            results.append({"assignment_id": aid, "status": "arrived", "success": success})

    return results


def process_finishes_sync():
    now_sim = clock.sim_now()
    results = []

    for aid, trip in list(_trips.items()):
        if trip["arrived"] and not trip["finished"] and now_sim >= trip["fire_finalizacion"]:
            success = assignments_repo.set_finish_sync(aid, trip["finalizacion_valor"])
            trip["finished"] = True
            game_feed.add(
                kind="resource",
                title="Atención finalizada",
                message=f"Asignación A{aid} cerró la atención en zona {trip['zona_destino']}.",
                zona_id=trip["zona_destino"],
                severity="success",
                dedupe_key=f"trip-finish:{aid}",
                meta={"assignmentId": aid, "success": success},
            )
            results.append({"assignment_id": aid, "status": "finished", "success": success})

    return results
