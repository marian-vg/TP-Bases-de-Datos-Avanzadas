from fastapi import APIRouter
from pydantic import BaseModel
from ..services import scheduler, clock

router = APIRouter(prefix="/api/v1/simulation", tags=["simulation"])


class AutoRequest(BaseModel):
    enabled: bool


class StormRequest(BaseModel):
    count: int = 20
    intensity: str = "high"


@router.post("/auto")
async def set_auto(req: AutoRequest):
    scheduler.set_auto(req.enabled)
    return {
        "data": {
            "auto": scheduler.is_auto(),
            "message": "Modo automatico " + ("activado" if req.enabled else "desactivado"),
        }
    }


@router.post("/tick")
async def manual_tick():
    from ..services import operator as op_svc
    from ..services import physical_world as pw_svc
    from ..repositories import assignments_repo

    new_assignments = assignments_repo.get_open_assignments_without_arrival_sync()
    for a in new_assignments:
        aid = a["id_asignacion"]
        if aid not in pw_svc._trips:
            pw_svc.schedule_trip(
                assignment_id=aid,
                zona_origen=a["zona_origen"],
                zona_destino=a["zona_destino"],
                timestamp_asignacion=a["timestamp_asignacion"],
            )

    arrivals = pw_svc.process_arrivals_sync()
    finishes = pw_svc.process_finishes_sync()
    reviews = op_svc.process_pending_reviews_sync()

    return {
        "data": {
            "arrivals": arrivals,
            "finishes": finishes,
            "reviews": reviews,
        }
    }


@router.post("/pause")
async def toggle_pause():
    if clock.is_paused():
        clock.resume()
        return {"data": {"paused": False}}
    else:
        clock.pause()
        return {"data": {"paused": True}}


@router.post("/storm")
async def storm_mode(req: StormRequest):
    import random
    from ..services import mapping as mapping_svc
    from ..repositories import catalogs_repo, events_repo
    from ..services import operator as op_svc

    mapping_data = mapping_svc.load_mapping_sync()
    catastrofes = list(mapping_data.keys())
    results = []

    for _ in range(min(req.count, 50)):
        cat = random.choice(catastrofes)
        info = mapping_data[cat]
        zona_id = random.randint(1, 12)
        sim = clock.sim_now()

        tipos_sensor_ids = list(info["tipos_sensor_ids"].values()) if info["tipos_sensor_ids"] else []
        sensor = catalogs_repo.find_capable_sensor_sync(zona_id, tipos_sensor_ids)

        if sensor is None:
            results.append({"catastrofe": cat, "zona": zona_id, "coverage": "none"})
            continue

        evento_id = events_repo.insert_evento_sync(
            sensor_id=sensor["id_sensor"],
            tipo_evento_id=info["tipo_evento_id"],
            sim_date=sim,
        )

        incidente = events_repo.find_incidente_by_evento_sync(evento_id)
        if incidente is None:
            op_svc.enqueue_operator_review(
                evento_id=evento_id,
                zona_id=zona_id,
                tipo_evento_id=info["tipo_evento_id"],
            )

        results.append({
            "catastrofe": cat,
            "zona": zona_id,
            "evento_id": evento_id,
            "incidente_id": incidente["id_incidente"] if incidente else None,
            "coverage": "covered",
        })

    return {"data": {"generated": len(results), "results": results}}
