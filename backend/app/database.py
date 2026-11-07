from functools import lru_cache

from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine

from .config import get_settings


@lru_cache
def get_engine() -> Engine:
    settings = get_settings()
    database_url = settings.database_url
    # Managed providers commonly expose postgres:// or postgresql:// URLs.
    # SQLAlchemy needs the installed Psycopg 3 driver to be explicit.
    if database_url.startswith("postgres://"):
        database_url = "postgresql+psycopg://" + database_url.removeprefix("postgres://")
    elif database_url.startswith("postgresql://"):
        database_url = "postgresql+psycopg://" + database_url.removeprefix("postgresql://")
    return create_engine(
        database_url,
        pool_pre_ping=True,
        pool_size=5,
        max_overflow=5,
        pool_recycle=1800,
    )


def get_schema_details(engine: Engine) -> tuple[str, frozenset[str]]:
    query = text("""
        SELECT c.table_name, c.column_name, c.data_type, c.is_nullable
        FROM information_schema.columns c
        WHERE c.table_schema = 'public'
        ORDER BY c.table_name, c.ordinal_position
    """)
    tables: dict[str, list[str]] = {}
    with engine.connect() as conn:
        for row in conn.execute(query).mappings():
            tables.setdefault(row["table_name"], []).append(
                f"{row['column_name']} {row['data_type']}"
            )
    return (
        "\n".join(f"{name}({', '.join(columns)})" for name, columns in tables.items()),
        frozenset(tables),
    )


def get_schema_context(engine: Engine) -> str:
    """Compatibility helper for the schema inspection endpoint."""
    return get_schema_details(engine)[0]


def execute_readonly(engine: Engine, sql: str, timeout_ms: int) -> tuple[list[str], list[dict]]:
    # A transaction set to READ ONLY protects against changes even if validation is bypassed.
    with engine.connect() as conn:
        conn.execute(text("SET TRANSACTION READ ONLY"))
        conn.execute(text(f"SET LOCAL statement_timeout = {int(timeout_ms)}"))
        result = conn.execute(text(sql))
        columns = list(result.keys())
        rows = [dict(row) for row in result.mappings().all()]
    return columns, rows
