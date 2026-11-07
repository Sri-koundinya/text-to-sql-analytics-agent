from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+psycopg://analytics_reader:analytics_reader@localhost:5432/retail_analytics"
    openai_api_key: str | None = None
    openai_model: str = "gpt-5.2"
    max_result_rows: int = Field(default=200, ge=1, le=10_000)
    query_timeout_ms: int = Field(default=8000, ge=100, le=60_000)
    max_sql_retries: int = Field(default=2, ge=0, le=5)
    cors_origins: str = ""
    rate_limit_per_minute: int = Field(default=20, ge=1, le=600)
    log_level: str = "INFO"
    debug: bool = False

    @property
    def allowed_origins(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
