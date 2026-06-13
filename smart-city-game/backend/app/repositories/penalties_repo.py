from ..db import get_pool


def get_recent_penalties_sync(limit: int = 50) -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT p.id_penalizacion, p.fk_recurso_id, p.fk_tipo_penalizacion_id,
                          tp.nombre as tipo_penalizacion, p.fecha, p.hora, p.puntaje, p.motivo
                   FROM Penalizacion p
                   JOIN TipoPenalizacion tp ON p.fk_tipo_penalizacion_id = tp.id_tipo_penalizacion
                   ORDER BY p.fecha DESC, p.hora DESC
                   LIMIT %s;""",
                (limit,),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]
