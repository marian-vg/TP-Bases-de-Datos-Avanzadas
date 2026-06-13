from fastapi import APIRouter
from ..repositories import state_repo
from ..services import clock, scheduler, scoring
from ..services.mapping import get_catastrofes_list_sync

router = APIRouter(prefix="/api/v1", tags=["state"])


@router.get("/state")
async def get_state():
    sim = clock.sim_now()
    data = state_repo.get_full_state_sync(sim)
    data["reloj"] = clock.get_status()
    data["scheduler"] = scheduler.get_status()
    data["score"] = scoring.get_score()
    data["catastrofesList"] = get_catastrofes_list_sync()
    return {
        "data": data,
        "meta": {
            "simNow": sim.isoformat(),
        },
    }
