from ..db import get_pool


def get_all_resources_sync() -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
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
            return [dict(zip(cols, r)) for r in cur]


def get_disponibles_sync() -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM vRecursosDisponibles;")
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]


def get_ocupados_sync() -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM vRecursosOcupados;")
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]


def get_penalizados_sync() -> list[dict]:
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM vRecursosPenalizados;")
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]


def call_reactivar_recursos_sync():
    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute("CALL sp_ReactivarRecursos();")
