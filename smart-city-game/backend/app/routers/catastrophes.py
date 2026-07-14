from fastapi import APIRouter, HTTPException
from ..services import mapping, clock
from ..repositories import catalogs_repo, events_repo
from ..services import operator, game_feed
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
    
    _last_used[req.catastropheType] = now

    if sensor is None:
        game_feed.add(
            kind="attack",
            title="Reporte ciudadano",
            message=f"Catástrofe {req.catastropheType.replace('_', ' ')} reportada manualmente por ciudadanos en zona {req.zoneId}.",
            zona_id=req.zoneId,
            severity="danger",
            dedupe_key=f"attack-manual:{req.catastropheType}:{req.zoneId}:{int(now)}",
            meta={"catastrophe": req.catastropheType},
        )
        
        review_delay = operator.enqueue_operator_review(
            evento_id=None,
            zona_id=req.zoneId,
            tipo_evento_id=info["tipo_evento_id"],
            sensor_id=None,
            sensor_nombre=None,
            tipo_sensor="Reporte telefónico",
            sensor_confianza=0,
        )
        
        return {
            "data": {
                "eventId": None,
                "incidentId": None,
                "coverage": "none",
                "detectionMode": "operator_review",
                "sensorConfidence": 0,
                "reviewDelaySeconds": review_delay,
                "sensorName": "Llamado telefónico",
                "sensorType": "Reporte ciudadano",
            }
        }

    game_feed.add(
        kind="attack",
        title="Ataque del jugador",
        message=f"Evento {req.catastropheType.replace('_', ' ')} inyectado en zona {req.zoneId}.",
        zona_id=req.zoneId,
        severity="danger",
        dedupe_key=f"attack:{req.catastropheType}:{req.zoneId}:{int(now)}",
        meta={"catastrophe": req.catastropheType},
    )

    sim = clock.sim_now()
    evento_id = events_repo.insert_evento_sync(
        sensor_id=sensor["id_sensor"],
        tipo_evento_id=info["tipo_evento_id"],
        sim_date=sim,
    )

    incidente = events_repo.find_incidente_by_evento_sync(evento_id)
    detection_mode = "immediate" if incidente else "operator_review"

    if detection_mode == "operator_review":
        review_delay = operator.enqueue_operator_review(
            evento_id=evento_id,
            zona_id=req.zoneId,
            tipo_evento_id=info["tipo_evento_id"],
            sensor_id=sensor["id_sensor"],
            sensor_nombre=sensor.get("sensor_nombre"),
            tipo_sensor=sensor.get("tipo_sensor_nombre"),
            sensor_confianza=sensor["confianza"],
        )
    else:
        review_delay = None
        game_feed.add(
            kind="sensor",
            title="Sensor confirma incidente",
            message=f"{sensor.get('tipo_sensor_nombre')} confirmó el evento con confianza {round(float(sensor['confianza']))}.",
            zona_id=req.zoneId,
            severity="success",
            dedupe_key=f"incident:{evento_id}",
            meta={"eventId": evento_id, "incidentId": incidente["id_incidente"] if incidente else None},
        )

    return {
        "data": {
            "eventId": evento_id,
            "incidentId": incidente["id_incidente"] if incidente else None,
            "coverage": "covered",
            "detectionMode": detection_mode,
            "sensorConfidence": sensor["confianza"],
            "reviewDelaySeconds": review_delay,
            "sensorName": sensor.get("sensor_nombre"),
            "sensorType": sensor.get("tipo_sensor_nombre"),
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
