from datetime import datetime, timedelta
import random
from ..repositories import assignments_repo
from . import clock

_trips: dict[int, dict] = {}
_trip_counter: int = 0


def schedule_trip(assignment_id: int, zona_origen: int, zona_destino: int, timestamp_asignacion: datetime):
    global _trip_counter
    _trip_counter += 1

    now = clock.sim_now()
    same_zone = zona_origen == zona_destino
    late_chance = 0.10 if same_zone else 0.50
    is_late = random.random() < late_chance

    travel_seconds = random.randint(5, 15)
    if is_late:
        travel_seconds += random.randint(10, 30)

    arrival_sim = now + timedelta(seconds=travel_seconds)
    finish_seconds = random.randint(5, 15)
    finish_sim = arrival_sim + timedelta(seconds=finish_seconds)

    _trips[assignment_id] = {
        "assignment_id": assignment_id,
        "zona_origen": zona_origen,
        "zona_destino": zona_destino,
        "arrival_sim": arrival_sim,
        "finish_sim": finish_sim,
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
    now = clock.sim_now()
    results = []

    for aid, trip in list(_trips.items()):
        if not trip["arrived"] and now >= trip["arrival_sim"]:
            success = assignments_repo.set_arrival_sync(aid, now)
            trip["arrived"] = True
            results.append({"assignment_id": aid, "status": "arrived", "success": success})

    return results


def process_finishes_sync():
    now = clock.sim_now()
    results = []

    for aid, trip in list(_trips.items()):
        if trip["arrived"] and not trip["finished"] and now >= trip["finish_sim"]:
            success = assignments_repo.set_finish_sync(aid, now)
            trip["finished"] = True
            results.append({"assignment_id": aid, "status": "finished", "success": success})

    return results
