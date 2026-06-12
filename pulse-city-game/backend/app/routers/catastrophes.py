from fastapi import APIRouter, HTTPException
from ..services import mapping, clock
from ..repositories import catalogs_repo, events_repo
from ..services import operator
from ..config import CONFIDENCE_THRESHOLD
from ..schemas.catastrophes import CatastropheRequest

router = APIRouter(prefix="/api/v1", tags=["catastrophes"])

_last_used: dict[str, float] = {}

import asyncio


@router.post("/catastrophes")
async def trigger_catastrophe(req: CatastropheRequest):
    now = asyncio.get_event_loop().time()
    cooldown = mapping.get_cooldown_sync(req.catastropheType)
    last = _last_used.get(req.catastropheType, 0)
    if now - last < cooldown:
        remaining = int(cooldown - (now - last))
        raise HTTPException(
            status_code=429,
            detail={
                "error": {
                    "code": "COOLDOWN_ACTIVE",
                    "message": f"Enfriamiento activo. Espera {remaining}s.",
                    "details": {"remaining": remaining},
                }
            },
        )

    mapping_data = mapping.load_mapping_sync()
    info = mapping_data.get(req.catastropheType)
    if not info or info["tipo_evento_id"] is None:
        raise HTTPException(status_code=400, detail={
            "error": {"code": "UNKNOWN_CATASTROPHE", "message": f"Catastrofe desconocida: {req.catastropheType}"}
        })

    tipos_sensor_ids = list(info["tipos_sensor_ids"].values())
    if not tipos_sensor_ids:
        raise HTTPException(status_code=400, detail={
            "error": {"code": "NO_SENSOR_TYPE", "message": "Sin tipos de sensor configurados"}
        })

    sensor = catalogs_repo.find_capable_sensor_sync(req.zoneId, tipos_sensor_ids)
    if sensor is None:
        return {
            "data": {
                "eventId": None,
                "incidentId": None,
                "coverage": "none",
                "detectionMode": "none",
                "sensorConfidence": 0,
            }
        }

    _last_used[req.catastropheType] = now

    sim = clock.sim_now()
    evento_id = events_repo.insert_evento_sync(
        sensor_id=sensor["id_sensor"],
        tipo_evento_id=info["tipo_evento_id"],
        sim_date=sim,
    )

    incidente = events_repo.find_incidente_by_evento_sync(evento_id)
    detection_mode = "immediate" if incidente else "operator_review"

    if detection_mode == "operator_review":
        operator.enqueue_operator_review(
            evento_id=evento_id,
            zona_id=req.zoneId,
            tipo_evento_id=info["tipo_evento_id"],
        )

    return {
        "data": {
            "eventId": evento_id,
            "incidentId": incidente["id_incidente"] if incidente else None,
            "coverage": "covered",
            "detectionMode": detection_mode,
            "sensorConfidence": sensor["confianza"],
        }
    }


@router.get("/events/pending-review")
async def get_pending_review():
    return {"data": {"events": operator.get_pending_reviews()}}


@router.get("/events/recent")
async def get_recent_events(limit: int = 50):
    return {"data": {"events": events_repo.get_recent_events_sync(limit)}}


@router.get("/catastrophes")
async def list_catastrophes():
    return {"data": {"catastrophes": mapping.get_catastrofes_list_sync()}}
