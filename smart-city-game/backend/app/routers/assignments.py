from fastapi import APIRouter
from ..repositories import assignments_repo
from ..services import clock

router = APIRouter(prefix="/api/v1", tags=["assignments"])


@router.get("/assignments")
async def get_assignments():
    data = assignments_repo.get_assignments_sync()
    return {"data": {"assignments": data}}


@router.post("/assignments/{assignment_id}/arrive")
async def arrive(assignment_id: int):
    sim = clock.sim_now()
    ok = assignments_repo.set_arrival_sync(assignment_id, sim)
    return {"data": {"arrived": ok, "assignmentId": assignment_id}}


@router.post("/assignments/{assignment_id}/fail")
async def fail(assignment_id: int):
    ok = assignments_repo.set_failure_sync(assignment_id)
    return {"data": {"failed": ok, "assignmentId": assignment_id}}


@router.post("/assignments/{assignment_id}/finish")
async def finish(assignment_id: int):
    sim = clock.sim_now()
    ok = assignments_repo.set_finish_sync(assignment_id, sim)
    return {"data": {"finished": ok, "assignmentId": assignment_id}}
