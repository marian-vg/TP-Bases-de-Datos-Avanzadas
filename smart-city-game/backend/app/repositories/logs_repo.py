from ..db import get_pool


def get_recent_logs_sync(since_id: int = 0, limit: int = 50, trigger: str = None) -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            params = []
            where = []
            if since_id > 0:
                where.append("id_log > %s")
                params.append(since_id)
            if trigger:
                where.append("trigger_disparador = %s")
                params.append(trigger)
            where_clause = " AND ".join(where) if where else "TRUE"
            cur.execute(
                f"""SELECT id_log, timestamp, tablaafectada, idtablaafectada,
                           operacion, trigger_disparador, detalle
                    FROM Log
                    WHERE {where_clause}
                    ORDER BY id_log DESC
                    LIMIT %s;""",
                (*params, limit),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]


def get_historial_triggers_sync(limit: int = 50) -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM vHistorialTriggers ORDER BY timestamp DESC LIMIT %s;",
                (limit,),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]
