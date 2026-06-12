from fastapi import APIRouter
from ..repositories import penalties_repo

router = APIRouter(prefix="/api/v1", tags=["penalties"])


@router.get("/penalties/recent")
async def get_recent_penalties(limit: int = 50):
    data = penalties_repo.get_recent_penalties_sync(limit)
    return {"data": {"penalties": data}}
