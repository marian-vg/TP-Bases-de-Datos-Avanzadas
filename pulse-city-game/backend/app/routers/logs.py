from fastapi import APIRouter, Query
from ..repositories import logs_repo

router = APIRouter(prefix="/api/v1", tags=["logs"])


@router.get("/logs/recent")
async def get_recent_logs(
    since_id: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=100),
    trigger: str = None,
):
    data = logs_repo.get_recent_logs_sync(since_id=since_id, limit=limit, trigger=trigger)
    return {"data": {"logs": data}}


@router.get("/logs/triggers")
async def get_trigger_history(limit: int = Query(50, ge=1, le=100)):
    data = logs_repo.get_historial_triggers_sync(limit)
    return {"data": {"triggers": data}}
