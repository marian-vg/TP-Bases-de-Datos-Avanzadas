from ..db import get_pool


def get_active_incidents_sync() -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM vIncidentesActivos ORDER BY fecha_hora_registro DESC LIMIT 100;")
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]


def get_incident_detail_sync(incident_id: int) -> dict | None:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT i.id_incidente, i.fk_evento_id, i.fk_tipo_incidente_id,
                          ti.nombre as tipo_incidente, i.fk_gravedad_id, g.nombre as gravedad,
                          i.fk_estado_incidente_id, ei.nombre as estado,
                          i.fk_zona_id, z.nombre as zona,
                          i.fecha_hora_registro, i.descripcion, i.prioridad
                   FROM Incidente i
                   JOIN TipoIncidente ti ON i.fk_tipo_incidente_id = ti.id_tipo_incidente
                   JOIN Gravedad g ON i.fk_gravedad_id = g.id_gravedad
                   JOIN EstadoIncidente ei ON i.fk_estado_incidente_id = ei.id_estado_incidente
                   JOIN Zona z ON i.fk_zona_id = z.id_zona
                   WHERE i.id_incidente = %s;""",
                (incident_id,),
            )
            row = cur.fetchone()
            if not row:
                return None
            cols = [d.name for d in cur.description]
            return dict(zip(cols, row))
