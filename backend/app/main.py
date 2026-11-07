import logging
import time
import uuid
from collections import defaultdict, deque
from functools import lru_cache
from threading import Lock

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy.exc import SQLAlchemyError

from .config import get_settings
from .database import get_engine, get_schema_context
from .sql_agent import SQLAgent

settings = get_settings()
logging.basicConfig(level=settings.log_level.upper(), format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger(__name__)
app = FastAPI(title="Text-to-SQL Analytics API", version="1.1.0")

if settings.allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.allowed_origins,
        allow_methods=["GET", "POST"],
        allow_headers=["Content-Type"],
    )


class InMemoryRateLimiter:
    def __init__(self, limit: int):
        self.limit = limit
        self.hits: dict[str, deque[float]] = defaultdict(deque)
        self.lock = Lock()

    def allow(self, key: str) -> bool:
        now = time.monotonic()
        with self.lock:
            window = self.hits[key]
            while window and now - window[0] >= 60:
                window.popleft()
            if len(window) >= self.limit:
                return False
            window.append(now)
            return True


rate_limiter = InMemoryRateLimiter(settings.rate_limit_per_minute)


class QuestionRequest(BaseModel):
    question: str = Field(min_length=3, max_length=1000, strip_whitespace=True)


class QuestionResponse(BaseModel):
    sql: str
    explanation: str
    columns: list[str]
    rows: list[dict]
    attempts: int


@lru_cache
def agent() -> SQLAgent:
    return SQLAgent(get_engine(), get_settings())


@app.get("/health")
def health() -> dict:
    try:
        with get_engine().connect() as conn:
            conn.exec_driver_sql("SELECT 1")
        return {"status": "ok", "database": "reachable", "model_configured": bool(settings.openai_api_key)}
    except SQLAlchemyError as exc:
        logger.warning("database_health_check_failed: %s", exc)
        raise HTTPException(status_code=503, detail="Database is unavailable") from exc


@app.get("/schema")
def schema() -> dict:
    return {"schema": get_schema_context(get_engine())}


@app.post("/query", response_model=QuestionResponse)
def query(request: QuestionRequest, http_request: Request) -> QuestionResponse:
    client_ip = http_request.client.host if http_request.client else "unknown"
    if not rate_limiter.allow(client_ip):
        raise HTTPException(status_code=429, detail="Rate limit exceeded. Please try again in one minute.")
    request_id = str(uuid.uuid4())
    try:
        result = agent().ask(request.question)
        logger.info("query_completed request_id=%s attempts=%s rows=%s", request_id, result.attempts, len(result.rows))
        return QuestionResponse(**result.__dict__)
    except Exception as exc:
        logger.exception("query_failed request_id=%s", request_id)
        detail = str(exc) if settings.debug else "Unable to produce a safe, runnable analytics query. Try rephrasing your question."
        raise HTTPException(status_code=400, detail=detail) from exc
