from fastapi import APIRouter
from ..repositories import incidents_repo
from ..db import get_pool

router = APIRouter(prefix="/api/v1", tags=["incidents"])


@router.get("/incidents/active")
async def get_active_incidents():
    data = incidents_repo.get_active_incidents_sync()
    return {"data": {"incidents": data}}


@router.get("/incidents/{incident_id}")
async def get_incident(incident_id: int):
    data = incidents_repo.get_incident_detail_sync(incident_id)
    if data is None:
        return {"data": None}
    return {"data": {"incident": data}}


@router.post("/incidents/{incident_id}/close")
async def close_incident(incident_id: int):
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("CALL sp_CerrarIncidente(%s);", (incident_id,))
    return {"data": {"closed": True, "incidentId": incident_id}}


@router.post("/incidents/escalate-overdue")
async def escalate_overdue():
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("CALL sp_EscalarIncidente();")
    return {"data": {"escalated": True}}
