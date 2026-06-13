from ..config import (
    CATASTROPHE_TO_EVENT_TYPE,
    CATASTROPHE_SENSOR_TYPES,
    CATASTROPHE_COOLDOWNS,
    CATASTROPHE_GRAVEDAD,
)
from ..repositories import catalogs_repo

_mapping_cache = None


def load_mapping_sync() -> dict:
    global _mapping_cache
    if _mapping_cache is not None:
        return _mapping_cache

    _mapping_cache = {}
    for catastrofe, tipo_evento_nombre in CATASTROPHE_TO_EVENT_TYPE.items():
        tipos_sensor_nombres = CATASTROPHE_SENSOR_TYPES.get(catastrofe, [])
        resolved = catalogs_repo.resolve_ids_by_name_sync(tipo_evento_nombre, tipos_sensor_nombres)
        _mapping_cache[catastrofe] = {
            "tipo_evento_id": resolved["tipo_evento_id"],
            "tipo_evento_nombre": tipo_evento_nombre,
            "tipos_sensor_ids": resolved["tipos_sensor_ids"],
            "incidentes": resolved["incidentes"],
            "cooldown": CATASTROPHE_COOLDOWNS.get(catastrofe, 10),
            "gravedad": CATASTROPHE_GRAVEDAD.get(catastrofe, 1),
        }

    return _mapping_cache


def validate_mapping_sync() -> dict:
    mapping = load_mapping_sync()
    complete = True
    faltantes = []
    for catastrofe, info in mapping.items():
        issues = []
        if info["tipo_evento_id"] is None:
            issues.append(f"TipoEvento '{info['tipo_evento_nombre']}' no encontrado")
        if not info["tipos_sensor_ids"]:
            issues.append("Sin tipos de sensor")
        if not info["incidentes"]:
            issues.append("Sin TipoIncidente mapeado")
        if issues:
            complete = False
            faltantes.append({"catastrofe": catastrofe, "issues": issues})

    return {
        "status": "complete" if complete else "incomplete",
        "faltantes": faltantes,
        "mapping": {
            k: {
                "tipo_evento_id": v["tipo_evento_id"],
                "tipos_sensor_ids": v["tipos_sensor_ids"],
                "incidentes_count": len(v["incidentes"]),
            }
            for k, v in mapping.items()
        },
    }


def get_cooldown_sync(catastrofe: str) -> int:
    return CATASTROPHE_COOLDOWNS.get(catastrofe, 10)


def get_catastrofes_list_sync() -> list[dict]:
    return [
        {
            "id": k,
            "nombre": k.replace("_", " ").title(),
            "gravedad": CATASTROPHE_GRAVEDAD.get(k, 1),
            "cooldown": CATASTROPHE_COOLDOWNS.get(k, 10),
        }
        for k in CATASTROPHE_TO_EVENT_TYPE
    ]
