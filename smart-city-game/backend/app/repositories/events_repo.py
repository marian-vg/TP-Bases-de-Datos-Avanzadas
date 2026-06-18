from datetime import datetime

from ..db import get_pool


def insert_evento_sync(sensor_id: int, tipo_evento_id: int, sim_date: datetime) -> int:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO Evento (fk_sensor_id, fk_tipo_evento_id, fecha_evento, hora_evento)
                   VALUES (%s, %s, %s, %s)
                   RETURNING id_evento;""",
                (sensor_id, tipo_evento_id, sim_date.date(), sim_date.time()),
            )
            row = cur.fetchone()
            return row[0]


def call_simular_eventos_sync(sensor_id: int, tipo_evento_id: int) -> int | None:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("CALL sp_SimularEventos(%s, %s);", (sensor_id, tipo_evento_id))
            cur.execute(
                """SELECT id_evento
                   FROM Evento
                   WHERE fk_sensor_id = %s
                     AND fk_tipo_evento_id = %s
                   ORDER BY id_evento DESC
                   LIMIT 1;""",
                (sensor_id, tipo_evento_id),
            )
            row = cur.fetchone()
            return row[0] if row else None


def get_promocion_mapeo_sync(tipo_evento_id: int) -> dict | None:
    """Deriva tipo_incidente/gravedad desde la BD (TipoEventoTipoIncidente),
    misma fuente de verdad que usa el trigger de promocion (fn_evento_promocion).
    Replica su regla: solo promueve si existe exactamente un mapeo."""
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT fk_tipo_incidente_id, fk_gravedad_id
                   FROM TipoEventoTipoIncidente
                   WHERE fk_tipo_evento_id = %s;""",
                (tipo_evento_id,),
            )
            rows = cur.fetchall()
            if len(rows) != 1:
                return None
            return {"tipo_incidente_id": rows[0][0], "gravedad_id": rows[0][1]}




def get_accidente_fallback_mapeo_sync() -> dict:
    """Fallback exclusivo del juego: si un evento llega a revisión del operador
    pero la BD no tiene un mapeo único, no modelamos falsos positivos. El
    operador lo acredita como Accidente de tránsito con gravedad Alta."""
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT
                       (SELECT id_tipo_incidente FROM TipoIncidente WHERE nombre ILIKE 'Accidente%' ORDER BY id_tipo_incidente LIMIT 1),
                       (SELECT id_gravedad FROM Gravedad WHERE nombre ILIKE 'Alta' ORDER BY id_gravedad LIMIT 1);"""
            )
            row = cur.fetchone()
            return {
                "tipo_incidente_id": row[0] if row and row[0] is not None else 1,
                "gravedad_id": row[1] if row and row[1] is not None else 3,
                "fallback": True,
            }


def find_incidente_by_evento_sync(evento_id: int) -> dict | None:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id_incidente FROM Incidente WHERE fk_evento_id = %s;",
                (evento_id,),
            )
            row = cur.fetchone()
            if not row:
                return None
            return {"id_incidente": row[0]}


def get_recent_events_sync(limit: int = 50) -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT e.id_evento, e.fecha_evento, e.hora_evento,
                          te.nombre AS tipo_evento,
                          s.id_sensor, s.nombre AS sensor,
                          z.id_zona, z.nombre AS zona,
                          fn_confianza_sensor(s.id_sensor) AS confianza,
                          i.id_incidente
                   FROM Evento e
                   JOIN TipoEvento te ON e.fk_tipo_evento_id = te.id_tipo_evento
                   JOIN Sensor s ON e.fk_sensor_id = s.id_sensor
                   JOIN Zona z ON s.fk_zona_id = z.id_zona
                   LEFT JOIN Incidente i ON i.fk_evento_id = e.id_evento
                   ORDER BY e.id_evento DESC
                   LIMIT %s;""",
                (limit,),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, row)) for row in cur]


def insert_incidente_sync(
    evento_id: int,
    tipo_incidente_id: int,
    gravedad_id: int,
    zona_id: int,
    sim_now: datetime,
    descripcion: str,
) -> int:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """INSERT INTO Incidente (
                       fk_evento_id, fk_tipo_incidente_id, fk_gravedad_id,
                       fk_estado_incidente_id, fk_zona_id,
                       fecha_hora_registro, descripcion, prioridad
                   ) VALUES (
                       %s, %s, %s,
                       (SELECT id_estado_incidente FROM EstadoIncidente WHERE nombre = 'Pendiente'),
                       %s, %s, %s, 0
                   )
                   RETURNING id_incidente;""",
                (evento_id, tipo_incidente_id, gravedad_id, zona_id, sim_now, descripcion),
            )
            row = cur.fetchone()
            return row[0]
