import pytest

from app.sql_guard import SQLSafetyError, validate_and_limit


def test_select_is_wrapped_with_hard_limit():
    query = validate_and_limit("SELECT customer_id FROM customers", 200, frozenset({"customers"}))
    assert query == "SELECT * FROM (SELECT customer_id FROM customers) AS guarded_result LIMIT 200"


@pytest.mark.parametrize(
    "query",
    [
        "DELETE FROM customers",
        "SELECT 1; DROP TABLE customers",
        "UPDATE orders SET status = 'completed'",
        "SHOW search_path",
        "SELECT * FROM orders -- sneaky comment",
    ],
)
def test_unsafe_sql_is_rejected(query):
    with pytest.raises(SQLSafetyError):
        validate_and_limit(query, 200, frozenset({"customers", "orders"}))


def test_cte_select_is_allowed():
    query = validate_and_limit("WITH x AS (SELECT 1 AS id) SELECT id FROM x", 10, frozenset())
    assert "LIMIT 10" in query


def test_non_allowlisted_table_is_rejected():
    with pytest.raises(SQLSafetyError, match="not available"):
        validate_and_limit("SELECT * FROM pg_catalog.pg_tables", 10, frozenset({"customers"}))


def test_dangerous_function_is_rejected():
    with pytest.raises(SQLSafetyError, match="not permitted"):
        validate_and_limit("SELECT pg_sleep(1)", 10, frozenset())
