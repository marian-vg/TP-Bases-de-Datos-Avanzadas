from ..db import get_pool


def get_catalogs_sync() -> dict:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT id_tipo_evento, nombre FROM TipoEvento ORDER BY id_tipo_evento;")
            eventos = [{"id": r[0], "nombre": r[1]} for r in cur]

            cur.execute("SELECT id_tipo_sensor, nombre FROM TipoSensor ORDER BY id_tipo_sensor;")
            sensores = [{"id": r[0], "nombre": r[1]} for r in cur]

            cur.execute("SELECT id_tipo_incidente, nombre FROM TipoIncidente ORDER BY id_tipo_incidente;")
            incidentes = [{"id": r[0], "nombre": r[1]} for r in cur]

            cur.execute("SELECT id_gravedad, nombre FROM Gravedad ORDER BY id_gravedad;")
            gravedades = [{"id": r[0], "nombre": r[1]} for r in cur]

            cur.execute(
                "SELECT fk_tipo_evento_id, fk_tipo_incidente_id, fk_gravedad_id FROM TipoEventoTipoIncidente;"
            )
            event_to_incident = [
                {"tipo_evento_id": r[0], "tipo_incidente_id": r[1], "gravedad_id": r[2]}
                for r in cur
            ]

    return {
        "tipos_evento": eventos,
        "tipos_sensor": sensores,
        "tipos_incidente": incidentes,
        "gravedades": gravedades,
        "evento_to_incidente": event_to_incident,
    }


def resolve_ids_by_name_sync(
    tipo_evento_nombre: str,
    tipos_sensor_nombres: list[str],
) -> dict:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id_tipo_evento FROM TipoEvento WHERE nombre = %s;",
                (tipo_evento_nombre,),
            )
            row = cur.fetchone()
            tipo_evento_id = row[0] if row else None

            lugar = ", ".join("%s" for _ in tipos_sensor_nombres)
            cur.execute(
                f"SELECT id_tipo_sensor, nombre FROM TipoSensor WHERE nombre IN ({lugar});",
                tipos_sensor_nombres,
            )
            sensores = {r[1]: r[0] for r in cur}

            cur.execute(
                """SELECT tei.fk_tipo_incidente_id, tei.fk_gravedad_id, ti.nombre
                   FROM TipoEventoTipoIncidente tei
                   JOIN TipoIncidente ti ON tei.fk_tipo_incidente_id = ti.id_tipo_incidente
                   WHERE tei.fk_tipo_evento_id = %s;""",
                (tipo_evento_id,),
            )
            incidentes = [
                {"tipo_incidente_id": r[0], "gravedad_id": r[1], "nombre": r[2]}
                for r in cur
            ]

    return {
        "tipo_evento_id": tipo_evento_id,
        "tipos_sensor_ids": sensores,
        "incidentes": incidentes,
    }


def find_capable_sensor_sync(zona_id: int, tipos_sensor_ids: list[int]) -> dict | None:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            lugar = ", ".join("%s" for _ in tipos_sensor_ids)
            cur.execute(
                f"""SELECT s.id_sensor, s.fk_tipo_sensor_id, ts.nombre, s.fk_zona_id,
                           fn_confianza_sensor(s.id_sensor) as confianza
                    FROM Sensor s
                    JOIN TipoSensor ts ON s.fk_tipo_sensor_id = ts.id_tipo_sensor
                    WHERE s.fk_zona_id = %s AND s.fk_tipo_sensor_id IN ({lugar})
                    ORDER BY fn_confianza_sensor(s.id_sensor) DESC
                    LIMIT 1;""",
                (zona_id, *tipos_sensor_ids),
            )
            row = cur.fetchone()
            if not row:
                return None
            return {
                "id_sensor": row[0],
                "tipo_sensor_id": row[1],
                "tipo_sensor_nombre": row[2],
                "zona_id": row[3],
                "confianza": row[4],
            }
