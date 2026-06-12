import os
from dotenv import load_dotenv

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = int(os.getenv("DB_PORT", "5433"))
DB_NAME = os.getenv("DB_NAME", "smart_city")
DB_USER = os.getenv("DB_USER", "postgres")
DB_PASSWORD = os.getenv("DB_PASSWORD", "password")

DB_POOL_MIN = int(os.getenv("DB_POOL_MIN", "2"))
DB_POOL_MAX = int(os.getenv("DB_POOL_MAX", "10"))

TIME_SCALE = int(os.getenv("TIME_SCALE", "20"))

FRONTEND_URL = os.getenv("FRONTEND_URL", "http://localhost:5173")

CATASTROPHE_COOLDOWNS = {
    "falla_estructural": 30,
    "incendio": 20,
    "emergencia_medica": 18,
    "accidente": 12,
    "evento_ambiental": 10,
    "robo": 8,
}

CATASTROPHE_GRAVEDAD = {
    "falla_estructural": 5,
    "incendio": 4,
    "emergencia_medica": 4,
    "accidente": 3,
    "evento_ambiental": 3,
    "robo": 2,
}

CATASTROPHE_TO_EVENT_TYPE = {
    "falla_estructural": "Vibración sísmica",
    "incendio": "Detección de humo",
    "emergencia_medica": "Activación de botón de pánico",
    "accidente": "Movimiento sospechoso",
    "evento_ambiental": "Inundación detectada",
    "robo": "Movimiento sospechoso",
}

CATASTROPHE_SENSOR_TYPES = {
    "falla_estructural": ["Sensor sísmico"],
    "incendio": ["Detector de humo", "Sensor de temperatura"],
    "emergencia_medica": ["Botón de pánico"],
    "accidente": ["Cámara de vigilancia", "Sensor de movimiento"],
    "evento_ambiental": ["Sensor de inundación", "Sensor de calidad del aire"],
    "robo": ["Cámara de vigilancia", "Sensor de movimiento"],
}

OPERATOR_REVIEW_MIN_DELAY = 15
OPERATOR_REVIEW_MAX_DELAY = 60

VIEW_ALLOWLIST = frozenset({
    "vincidentesactivos",
    "vrecursosdisponibles",
    "vrecursosocupados",
    "vincidentescriticos",
    "vhistorialincidentes",
    "vrecursospenalizados",
    "vrecursoscandidatos",
    "vhistorialasignaciones",
    "vhistorialtriggers",
    "vzonasincidentadas",
})

CONFIDENCE_THRESHOLD = 80
