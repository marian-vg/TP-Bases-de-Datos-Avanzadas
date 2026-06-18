from __future__ import annotations

from collections import defaultdict
from typing import Any


def _zone_id_for_incident(inc: dict[str, Any], zonas_by_name: dict[str, int]) -> int | None:
    return inc.get("fk_zona_id") or inc.get("zona_id") or zonas_by_name.get(inc.get("zona"))


def _numeric_gravity(value) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        text = str(value or "").lower()
        if "critic" in text or "crític" in text:
            return 5
        if "alta" in text or "alto" in text:
            return 4
        if "media" in text or "moder" in text:
            return 3
        if "baja" in text or "bajo" in text:
            return 2
        return 2


def _level(score: float) -> str:
    if score >= 80:
        return "colapsando"
    if score >= 55:
        return "critica"
    if score >= 30:
        return "tensionada"
    return "estable"


def sensor_confidence_by_zone(zonas: list[dict], sensores: list[dict], threshold: int = 80) -> dict[str, dict]:
    grouped: dict[int, list[float]] = defaultdict(list)
    for sensor in sensores:
        zid = sensor.get("fk_zona_id") or sensor.get("zona_id")
        if zid:
            grouped[int(zid)].append(float(sensor.get("confianza") or 0))

    result: dict[str, dict] = {}
    for zona in zonas:
        zid = int(zona["id_zona"])
        values = grouped.get(zid, [])
        avg = round(sum(values) / len(values), 1) if values else 0
        low = sum(1 for value in values if value < threshold)
        result[str(zid)] = {
            "zona_id": zid,
            "zona": zona.get("nombre"),
            "average": avg,
            "sensor_count": len(values),
            "low_confidence_count": low,
            "level": "alta" if avg >= 80 else "media" if avg >= 50 else "baja",
        }
    return result


def calculate(
    zonas: list[dict],
    incidentes: list[dict],
    recursos: list[dict],
    revisiones: list[dict],
    penalizaciones: list[dict],
) -> dict:
    zonas_by_name = {z.get("nombre"): int(z["id_zona"]) for z in zonas}
    by_zone: dict[int, dict[str, Any]] = {
        int(z["id_zona"]): {
            "zona_id": int(z["id_zona"]),
            "zona": z.get("nombre"),
            "score": 0,
            "level": "estable",
            "drivers": [],
        }
        for z in zonas
    }

    for inc in incidentes:
        zid = _zone_id_for_incident(inc, zonas_by_name)
        if zid in by_zone:
            gravedad = _numeric_gravity(inc.get("gravedad_id") or inc.get("gravedad") or 2)
            by_zone[zid]["score"] += 14 + gravedad * 4
            by_zone[zid]["drivers"].append(f"Incidente activo G{int(gravedad) if gravedad else '-'}")

    for review in revisiones:
        zid = review.get("zona_id")
        if zid in by_zone:
            by_zone[zid]["score"] += 10
            by_zone[zid]["drivers"].append("Evento en revisión")

    for recurso in recursos:
        zid = recurso.get("fk_zona_base_id") or recurso.get("zona_id")
        if zid not in by_zone:
            continue
        estado = str(recurso.get("estado") or "").lower()
        if "ocup" in estado or "tránsito" in estado or "transito" in estado:
            by_zone[zid]["score"] += 5
            by_zone[zid]["drivers"].append("Recurso ocupado")
        elif "fuera" in estado or "mantenimiento" in estado:
            by_zone[zid]["score"] += 7
            by_zone[zid]["drivers"].append("Capacidad reducida")
        elif "disponible" in estado:
            by_zone[zid]["score"] -= 2

    penalty_pressure = min(len(penalizaciones), 20) * 1.5
    for zone in by_zone.values():
        zone["score"] = max(0, min(100, round(zone["score"], 1)))
        zone["level"] = _level(zone["score"])
        zone["drivers"] = zone["drivers"][:5]

    if not by_zone:
        global_score = 0
    else:
        global_score = sum(z["score"] for z in by_zone.values()) / len(by_zone) + penalty_pressure
    global_score = max(0, min(100, round(global_score, 1)))

    hot_zones = sorted(by_zone.values(), key=lambda z: z["score"], reverse=True)[:4]
    return {
        "global": global_score,
        "level": _level(global_score),
        "byZone": {str(k): v for k, v in by_zone.items()},
        "hotZones": hot_zones,
        "drivers": {
            "incidentes": len(incidentes),
            "revisiones": len(revisiones),
            "penalizaciones_recientes": len(penalizaciones),
        },
    }
