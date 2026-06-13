from ..db import get_pool
from ..config import VIEW_ALLOWLIST


def get_view_sync(view_name: str, limit: int = 100) -> list[dict] | None:
    view_lower = view_name.lower()
    if view_lower not in VIEW_ALLOWLIST:
        return None

    pool = get_pool()
    with pool.connection() as conn:
        with conn.cursor() as cur:
            cur.execute(
                f'SELECT * FROM "{view_lower}" LIMIT %s;',
                (limit,),
            )
            cols = [d.name for d in cur.description]
            return [dict(zip(cols, r)) for r in cur]
