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

    scale = clock.get_scale()
    sla = sla_minutos if sla_minutos and sla_minutos > 0 else 5

    # 1) Calcular duración de viaje en SEGUNDOS REALES de reloj de pared
    if same_zone:
        viaje_real_segundos = random.uniform(2.0, 4.0)
    else:
        if is_late:
            # Supera el SLA del incidente para que la BD calcule la penalización proporcional (P4)
            # SLA real en segundos = (SLA_minutos * 60) / escala
            sla_real_segundos = (sla * 60.0) / scale
            viaje_real_segundos = sla_real_segundos + random.uniform(2.0, 8.0)
        else:
            viaje_real_segundos = random.uniform(5.0, 10.0)

    viaje = timedelta(seconds=viaje_real_segundos * scale)

    # 2) Calcular duración de la atención en SEGUNDOS REALES (mínimo 5s, máximo 30s)
    if gravedad_id == 1:
        atencion_real_segundos = random.uniform(5.0, 7.0)
    elif gravedad_id == 2:
        atencion_real_segundos = random.uniform(8.0, 12.0)
    elif gravedad_id == 3:
        atencion_real_segundos = random.uniform(13.0, 18.0)
    elif gravedad_id == 4:
        atencion_real_segundos = random.uniform(19.0, 24.0)
    elif gravedad_id == 5:
        atencion_real_segundos = random.uniform(25.0, 30.0)
    else:
        atencion_real_segundos = random.uniform(5.0, 15.0)

    atencion = timedelta(seconds=atencion_real_segundos * scale)

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
