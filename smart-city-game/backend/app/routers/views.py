from fastapi import APIRouter, HTTPException
from ..repositories import views_repo

router = APIRouter(prefix="/api/v1", tags=["views"])


@router.get("/views/{view_name}")
async def get_view(view_name: str, limit: int = 100):
    data = views_repo.get_view_sync(view_name, limit)
    if data is None:
        raise HTTPException(status_code=404, detail={
            "error": {"code": "VIEW_NOT_ALLOWED", "message": f"Vista no permitida: {view_name}"}
        })
    return {"data": {"view": view_name, "rows": data}}
