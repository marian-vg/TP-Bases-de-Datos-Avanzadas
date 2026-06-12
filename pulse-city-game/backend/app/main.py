from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError

from .config import FRONTEND_URL, TIME_SCALE
from .errors import validation_exception_handler
from .services import clock, scheduler


@asynccontextmanager
async def lifespan(app: FastAPI):
    clock.init_clock(scale=TIME_SCALE)
    scheduler.start()
    yield
    scheduler.stop()


app = FastAPI(
    title="Pulse City: Operador de Crisis",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[FRONTEND_URL, "http://localhost:5173", "http://localhost:8000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.exception_handler(RequestValidationError)(validation_exception_handler)

from .routers import health, state, zones, catastrophes, incidents, resources, assignments, penalties, views, logs, simulation, legacy

app.include_router(health.router)
app.include_router(state.router)
app.include_router(zones.router)
app.include_router(catastrophes.router)
app.include_router(incidents.router)
app.include_router(resources.router)
app.include_router(assignments.router)
app.include_router(penalties.router)
app.include_router(views.router)
app.include_router(logs.router)
app.include_router(simulation.router)
app.include_router(legacy.router)
