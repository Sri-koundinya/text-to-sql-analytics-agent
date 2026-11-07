import json
import logging
import re
from dataclasses import dataclass
from decimal import Decimal
from typing import Any

from openai import OpenAI
from sqlalchemy.engine import Engine

from .config import Settings
from .database import execute_readonly, get_schema_details
from .sql_guard import SQLSafetyError, clean_llm_sql, validate_and_limit


SYSTEM_PROMPT = """You generate PostgreSQL analytics queries. Return strict JSON only:
{"sql":"single SELECT query", "explanation":"one concise plain-English sentence"}.
Use only tables and columns in the supplied schema. Never modify data. Never use comments,
multiple statements, or SELECT *. Prefer completed orders for revenue metrics. Dates are PostgreSQL dates."""
logger = logging.getLogger(__name__)


@dataclass
class AgentResult:
    sql: str
    explanation: str
    columns: list[str]
    rows: list[dict[str, Any]]
    attempts: int


class SQLAgent:
    def __init__(self, engine: Engine, settings: Settings):
        self.engine = engine
        self.settings = settings
        self.client = OpenAI(api_key=settings.openai_api_key) if settings.openai_api_key else None

    def _generate(self, question: str, schema: str, error: str | None = None) -> tuple[str, str]:
        if not self.client:
            raise RuntimeError("OPENAI_API_KEY is not configured. Add it to .env before asking questions.")
        repair = f"\nPrevious query failed with: {error}\nCorrect it." if error else ""
        prompt = f"Schema:\n{schema}\n\nQuestion: {question}{repair}"
        response = self.client.responses.create(
            model=self.settings.openai_model,
            instructions=SYSTEM_PROMPT,
            input=prompt,
            text={"verbosity": "low"},
        )
        raw = response.output_text.strip()
        try:
            payload = json.loads(raw)
            return clean_llm_sql(str(payload["sql"])), str(payload.get("explanation", ""))
        except (json.JSONDecodeError, KeyError, TypeError):
            match = re.search(r"\{.*\}", raw, re.DOTALL)
            if match:
                payload = json.loads(match.group(0))
                return clean_llm_sql(str(payload["sql"])), str(payload.get("explanation", ""))
            raise ValueError("The model did not return the required JSON object.")

    def ask(self, question: str) -> AgentResult:
        schema, allowed_tables = get_schema_details(self.engine)
        last_error: str | None = None
        for attempt in range(1, self.settings.max_sql_retries + 2):
            sql, explanation = self._generate(question, schema, last_error)
            try:
                safe_sql = validate_and_limit(sql, self.settings.max_result_rows, allowed_tables)
                columns, rows = execute_readonly(self.engine, safe_sql, self.settings.query_timeout_ms)
                return AgentResult(sql=sql, explanation=explanation, columns=columns, rows=_json_safe(rows), attempts=attempt)
            except (SQLSafetyError, Exception) as exc:
                last_error = f"{type(exc).__name__}: {str(exc)[:500]}"
                logger.info("sql_attempt_failed attempt=%s error=%s", attempt, last_error)
        raise RuntimeError(f"Unable to produce a safe, runnable query after retries. Last error: {last_error}")


def _json_safe(value: Any) -> Any:
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, dict):
        return {key: _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    return value
