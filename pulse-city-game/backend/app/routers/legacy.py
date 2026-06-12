from fastapi import APIRouter

from ..schemas.catastrophes import CatastropheRequest
from . import catastrophes, incidents, penalties, resources, simulation, state, views, zones

router = APIRouter(tags=["secret-compatible"])


@router.get("/estado")
async def estado():
    return await state.get_state()


@router.get("/zonas")
async def zonas_legacy():
    return await zones.get_zones()


@router.get("/sensores")
async def sensores_legacy():
    return await zones.get_sensors()


@router.get("/catastrofes")
async def catastrofes_legacy():
    return await catastrophes.list_catastrophes()


@router.post("/catastrofes")
async def disparar_catastrofe_legacy(req: CatastropheRequest):
    return await catastrophes.trigger_catastrophe(req)


@router.get("/incidentes/activos")
async def incidentes_activos_legacy():
    return await incidents.get_active_incidents()


@router.get("/recursos")
async def recursos_legacy():
    return await resources.get_resources()


@router.get("/penalizaciones/recientes")
async def penalizaciones_recientes_legacy(limit: int = 50):
    return await penalties.get_recent_penalties(limit)


@router.get("/eventos/recientes")
async def eventos_recientes_legacy(limit: int = 50):
    return await catastrophes.get_recent_events(limit)


@router.get("/eventos/en-revision")
async def eventos_en_revision_legacy():
    return await catastrophes.get_pending_review()


@router.get("/vistas/{view_name}")
async def vistas_legacy(view_name: str, limit: int = 100):
    return await views.get_view(view_name, limit)


@router.post("/simulacion/auto")
async def simulacion_auto_legacy(req: simulation.AutoRequest):
    return await simulation.set_auto(req)


@router.post("/simulacion/tick")
async def simulacion_tick_legacy():
    return await simulation.manual_tick()


@router.post("/simulacion/pausa")
async def simulacion_pausa_legacy():
    return await simulation.toggle_pause()
