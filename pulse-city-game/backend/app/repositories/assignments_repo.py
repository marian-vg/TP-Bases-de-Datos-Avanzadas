from datetime import datetime

from ..db import get_pool


def get_assignments_sync(limit: int = 100) -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM vHistorialAsignaciones ORDER BY timestamp_asignacion DESC LIMIT %s;",
                (limit,),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]


def set_arrival_sync(assignment_id: int, sim_now: datetime) -> bool:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE Asignacion
                   SET timestamp_llegada = %s
                   WHERE id_asignacion = %s
                     AND timestamp_llegada IS NULL;""",
                (sim_now, assignment_id),
            )
            return cur.rowcount > 0


def set_failure_sync(assignment_id: int) -> bool:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE Asignacion
                   SET estado_exito = FALSE
                   WHERE id_asignacion = %s
                     AND estado_exito IS DISTINCT FROM FALSE;""",
                (assignment_id,),
            )
            return cur.rowcount > 0


def set_finish_sync(assignment_id: int, sim_now: datetime) -> bool:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """UPDATE Asignacion
                   SET estado_exito = TRUE, timestamp_finalizacion = %s
                   WHERE id_asignacion = %s
                     AND timestamp_finalizacion IS NULL;""",
                (sim_now, assignment_id),
            )
            return cur.rowcount > 0


def get_open_assignments_without_arrival_sync() -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT a.id_asignacion, a.fk_recurso_id, a.fk_incidente_id,
                          a.timestamp_asignacion,
                          r.fk_zona_base_id as zona_origen,
                          i.fk_zona_id as zona_destino,
                          r.fk_estado_recurso_id
                   FROM Asignacion a
                   JOIN Recurso r ON a.fk_recurso_id = r.id_recurso
                   JOIN Incidente i ON a.fk_incidente_id = i.id_incidente
                   WHERE a.timestamp_llegada IS NULL
                     AND a.estado_exito IS NULL;""",
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]


def get_arrived_assignments_not_finished_sync() -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """SELECT a.id_asignacion, a.fk_recurso_id, a.fk_incidente_id,
                          a.timestamp_asignacion, a.timestamp_llegada
                   FROM Asignacion a
                   WHERE a.timestamp_llegada IS NOT NULL
                     AND a.timestamp_finalizacion IS NULL
                     AND a.estado_exito IS NULL;""",
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]
