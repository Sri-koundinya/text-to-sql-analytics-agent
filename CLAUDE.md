# CLAUDE.md — Text-to-SQL Analytics Agent

## Purpose

Portfolio project for Forward Deployed Engineer roles. Every change should make the project more like a real customer deployment: measurable, deployable, safe, well documented.

## Stack

- `backend/`: FastAPI, SQLAlchemy 2, psycopg 3, sqlglot, OpenAI Responses API, pydantic-settings
- `frontend/`: Streamlit chat UI (talks to backend via `API_BASE_URL`)
- `db/`: PostgreSQL 16 schema (`init.sql`), read-only role, deterministic seed data (`seed_large.sql`)
- `docker-compose.yml` runs db + backend + frontend

## Commands

- Run everything: `docker compose up --build`
- Backend tests: `cd backend && pytest`

## Rules

- Never weaken the SQL safety layers (sqlglot validation, table allow-list, outer LIMIT, READ ONLY transaction, statement_timeout, analytics_reader role). New features must keep all five. Add a test for any guard change.
- The app always connects as `analytics_reader`, never as the admin user.
- Never commit secrets; config goes through `.env` (see `.env.example`).
- Seed data must stay deterministic (`setseed`) so evaluation results are reproducible.
- Keep README.md updated when features land (roadmap checkboxes, quickstart, results).

## Roadmap

1. [x] Repo hygiene, docker-compose, realistic seed data, README
2. [ ] Evaluation suite: ~50 question/gold-SQL pairs, execution-accuracy scoring, latency and retry stats, JSON + markdown report
3. [ ] Upload CSV/Excel data, clean it, load it, query it
4. [ ] Configurable business glossary (e.g. revenue = completed orders only)
5. [ ] Cloud deployment with authentication and query/feedback logging
6. [ ] Real-user pilot and case study
