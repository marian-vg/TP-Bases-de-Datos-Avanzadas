from fastapi import APIRouter
from ..db import check_db_health_sync
from ..services.mapping import validate_mapping_sync, get_catastrofes_list_sync

router = APIRouter(prefix="/api/v1/health", tags=["health"])


@router.get("")
async def health():
    return {"status": "ok", "service": "pulse-city-backend"}


@router.get("/db")
async def health_db():
    result = check_db_health_sync()
    if "error" in result:
        return {"status": "error", **result}
    return {"status": "ok", **result}


@router.get("/config")
async def health_config():
    result = validate_mapping_sync()
    return result
