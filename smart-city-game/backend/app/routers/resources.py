from fastapi import APIRouter
from ..repositories import resources_repo

router = APIRouter(prefix="/api/v1", tags=["resources"])


@router.get("/resources")
async def get_resources():
    all_resources = resources_repo.get_all_resources_sync()
    disponibles = resources_repo.get_disponibles_sync()
    ocupados = resources_repo.get_ocupados_sync()
    penalizados = resources_repo.get_penalizados_sync()
    return {
        "data": {
            "recursos": all_resources,
            "disponibles": disponibles,
            "ocupados": ocupados,
            "penalizados": penalizados,
        }
    }


@router.post("/resources/reactivate-due")
async def reactivate_due():
    resources_repo.call_reactivar_recursos_sync()
    return {"data": {"reactivated": True}}
