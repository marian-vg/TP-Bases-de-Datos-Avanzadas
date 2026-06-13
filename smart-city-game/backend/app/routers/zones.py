from fastapi import APIRouter
from ..db import get_pool

router = APIRouter(prefix="/api/v1", tags=["zones"])


@router.get("/zones")
async def get_zones():
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT z.id_zona, z.nombre, nr.nombre as nivel_riesgo,
                          z.fk_nivel_riesgo_id
                   FROM Zona z
                   JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
                   ORDER BY z.id_zona;"""
            )
            cols = [d.name for d in cur.description]
            zonas = [dict(zip(cols, r)) for r in cur]

            cur.execute("SELECT * FROM vZonasIncidentadas;")
            cols2 = [d.name for d in cur.description]
            incidentadas = [dict(zip(cols2, r)) for r in cur]

    return {"data": {"zonas": zonas, "incidentadas": incidentadas}}


@router.get("/sensors")
async def get_sensors():
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT s.id_sensor, s.fk_tipo_sensor_id, ts.nombre as tipo_sensor,
                          s.fk_zona_id, z.nombre as zona, s.nombre, s.marca, s.modelo,
                          s.fecha_instalado,
                          fn_confianza_sensor(s.id_sensor) as confianza
                   FROM Sensor s
                   JOIN TipoSensor ts ON s.fk_tipo_sensor_id = ts.id_tipo_sensor
                   JOIN Zona z ON s.fk_zona_id = z.id_zona
                   ORDER BY s.id_sensor;"""
            )
            cols = [d.name for d in cur.description]
            sensores = [dict(zip(cols, r)) for r in cur]

    return {"data": {"sensores": sensores}}
