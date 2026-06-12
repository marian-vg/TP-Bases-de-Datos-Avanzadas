from ..db import get_pool
from ..services import operator, physical_world


def get_full_state_sync(sim_now) -> dict:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT z.id_zona, z.nombre, nr.nombre as nivel_riesgo
                   FROM Zona z
                   JOIN NivelRiesgo nr ON z.fk_nivel_riesgo_id = nr.id_nivel_riesgo
                   ORDER BY z.id_zona;"""
            )
            cols = [d.name for d in cur.description]
            zonas = [dict(zip(cols, r)) for r in cur]

            cur.execute(
                """SELECT s.id_sensor, s.fk_tipo_sensor_id, ts.nombre as tipo_sensor,
                          s.fk_zona_id, z.nombre as zona, s.nombre, s.marca, s.modelo,
                          fn_confianza_sensor(s.id_sensor) as confianza
                   FROM Sensor s
                   JOIN TipoSensor ts ON s.fk_tipo_sensor_id = ts.id_tipo_sensor
                   JOIN Zona z ON s.fk_zona_id = z.id_zona
                   ORDER BY s.id_sensor;"""
            )
            cols = [d.name for d in cur.description]
            sensores = [dict(zip(cols, r)) for r in cur]

            cur.execute("SELECT * FROM vIncidentesActivos ORDER BY fecha_hora_registro DESC LIMIT 100;")
            cols = [d.name for d in cur.description]
            incidentes_activos = [dict(zip(cols, r)) for r in cur]

            cur.execute("SELECT * FROM vIncidentesCriticos LIMIT 50;")
            cols = [d.name for d in cur.description]
            incidentes_criticos = [dict(zip(cols, r)) for r in cur]

            cur.execute(
                """SELECT r.id_recurso, r.fk_tipo_recurso_id, tr.nombre as tipo_recurso,
                          r.fk_zona_base_id, z.nombre as zona,
                          r.fk_estado_recurso_id, er.nombre as estado,
                          r.puntaje
                   FROM Recurso r
                   JOIN TipoRecurso tr ON r.fk_tipo_recurso_id = tr.id_tipo_recurso
                   JOIN EstadoRecurso er ON r.fk_estado_recurso_id = er.id_estado_recurso
                   JOIN Zona z ON r.fk_zona_base_id = z.id_zona
                   ORDER BY r.id_recurso;"""
            )
            cols = [d.name for d in cur.description]
            recursos = [dict(zip(cols, r)) for r in cur]

            cur.execute("SELECT * FROM vRecursosDisponibles;")
            cols = [d.name for d in cur.description]
            disponibles = [dict(zip(cols, r)) for r in cur]

            cur.execute("SELECT * FROM vRecursosOcupados;")
            cols = [d.name for d in cur.description]
            ocupados = [dict(zip(cols, r)) for r in cur]

            cur.execute("SELECT * FROM vRecursosPenalizados;")
            cols = [d.name for d in cur.description]
            penalizados = [dict(zip(cols, r)) for r in cur]

            cur.execute(
                """SELECT a.id_asignacion, a.fk_recurso_id, a.fk_incidente_id,
                          a.timestamp_asignacion, a.timestamp_llegada,
                          a.timestamp_finalizacion, a.estado_exito,
                          r.fk_zona_base_id as zona_origen, i.fk_zona_id as zona_destino
                   FROM Asignacion a
                   JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
                   JOIN Incidente i ON a.fk_incidente_id = i.id_incidente
                   WHERE a.timestamp_finalizacion IS NULL
                   ORDER BY a.timestamp_asignacion DESC
                   LIMIT 100;"""
            )
            cols = [d.name for d in cur.description]
            asignaciones_activas = [dict(zip(cols, r)) for r in cur]

            cur.execute(
                """SELECT p.id_penalizacion, p.fk_recurso_id, p.fk_tipo_penalizacion_id,
                          tp.nombre as tipo_penalizacion, p.fecha, p.hora,
                          p.puntaje, p.motivo
                   FROM Penalizacion p
                   JOIN TipoPenalizacion tp ON p.fk_tipo_penalizacion_id = tp.id_tipo_penalizacion
                   ORDER BY p.fecha DESC, p.hora DESC
                   LIMIT 50;"""
            )
            cols = [d.name for d in cur.description]
            penalties = [dict(zip(cols, r)) for r in cur]

            cur.execute(
                """SELECT id_log, timestamp, tablaafectada, idtablaafectada,
                          operacion, trigger_disparador, detalle
                   FROM Log ORDER BY id_log DESC LIMIT 50;"""
            )
            cols = [d.name for d in cur.description]
            logs = [dict(zip(cols, r)) for r in cur]

    return {
        "simNow": sim_now.isoformat(),
        "dbStatus": "OK",
        "zonas": zonas,
        "sensores": sensores,
        "incidentesActivos": incidentes_activos,
        "incidentesCriticos": incidentes_criticos,
        "recursos": recursos,
        "recursosDisponibles": disponibles,
        "recursosOcupados": ocupados,
        "recursosPenalizados": penalizados,
        "asignacionesActivas": asignaciones_activas,
        "viajesActivos": physical_world.get_active_trips(),
        "eventosEnRevision": operator.get_pending_reviews(),
        "penalizaciones": penalties,
        "logsRecientes": logs,
    }
