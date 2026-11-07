import re

from sqlglot import exp, parse


class SQLSafetyError(ValueError):
    """Raised for statements outside the application read-only policy."""


FORBIDDEN_KEYWORDS = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|COPY|CALL|DO|"
    r"VACUUM|ANALYZE|SET|SHOW|RESET|BEGIN|COMMIT|ROLLBACK|LOCK|EXECUTE|PREPARE)\b",
    re.IGNORECASE,
)
FORBIDDEN_FUNCTIONS = {"pg_sleep", "dblink_connect", "dblink_exec", "lo_import", "lo_export"}
FORBIDDEN_EXPRESSIONS = (exp.Into, exp.Lock)


def clean_llm_sql(value: str) -> str:
    value = value.strip()
    value = re.sub(r"^```(?:sql)?\s*|\s*```$", "", value, flags=re.IGNORECASE)
    return value.strip().rstrip(";").strip()


def validate_and_limit(sql: str, max_rows: int, allowed_tables: frozenset[str]) -> str:
    sql = clean_llm_sql(sql)
    if not sql:
        raise SQLSafetyError("No SQL was generated.")
    if "--" in sql or "/*" in sql or "*/" in sql:
        raise SQLSafetyError("SQL comments are not permitted.")
    if FORBIDDEN_KEYWORDS.search(sql):
        raise SQLSafetyError("Only read-only SELECT queries are permitted.")

    try:
        statements = parse(sql, read="postgres")
    except Exception as exc:
        raise SQLSafetyError(f"SQL could not be parsed: {exc}") from exc

    if len(statements) != 1 or not isinstance(statements[0], (exp.Select, exp.Union, exp.Intersect, exp.Except)):
        raise SQLSafetyError("Exactly one SELECT or CTE SELECT statement is required.")

    statement = statements[0]
    cte_names = {cte.alias_or_name for cte in statement.find_all(exp.CTE)}
    if any(isinstance(node, FORBIDDEN_EXPRESSIONS) for node in statement.walk()):
        raise SQLSafetyError("SELECT INTO and row-locking clauses are not permitted.")
    for table in statement.find_all(exp.Table):
        if table.name not in allowed_tables and table.name not in cte_names:
            raise SQLSafetyError(f"Table '{table.name}' is not available to this analytics agent.")
    for function in statement.find_all(exp.Anonymous):
        if function.name.lower() in FORBIDDEN_FUNCTIONS:
            raise SQLSafetyError(f"Function '{function.name}' is not permitted.")

    if max_rows < 1 or max_rows > 10_000:
        raise SQLSafetyError("Invalid server row limit configuration.")

    # The outer LIMIT cannot be removed by an LLM-provided inner query.
    return f"SELECT * FROM ({sql}) AS guarded_result LIMIT {max_rows}"
