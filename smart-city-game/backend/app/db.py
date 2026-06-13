from psycopg_pool import ConnectionPool
from .config import DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, DB_POOL_MIN, DB_POOL_MAX

_pool = None


def get_pool() -> ConnectionPool:
    global _pool
    if _pool is None or getattr(_pool, "closed", False):
        _pool = ConnectionPool(
            conninfo=f"host={DB_HOST} port={DB_PORT} dbname={DB_NAME} user={DB_USER} password={DB_PASSWORD}",
            min_size=DB_POOL_MIN,
            max_size=DB_POOL_MAX,
        )
    return _pool


def check_db_health_sync() -> dict:
    try:
        pool = get_pool()
        with pool.connection() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT current_database(), version();")
                row = cur.fetchone()
                return {"database": row[0], "version": row[1]}
    except Exception as e:
        return {"error": str(e)}
