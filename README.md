# MedOrbit

A smart healthcare platform for Nablus, Palestine — graduation project, An-Najah National University.

## Main features

- Patient/doctor accounts with Google Sign-In, appointment scheduling, and messaging
- Clinic/facility discovery on a Nablus map (Leaflet + PostGIS)
- Medical records and prescriptions (patient-visible, doctor-authored)
- AI virtual doctor: symptom triage, RAG-backed medical Q&A, drug-checker, and OCR report summarization, powered by a local LLM (Ollama)
- Notifications and event-driven recommendations via Kafka

## Architecture

| Service | Tech | Port |
|---|---|---|
| `frontend` | Vanilla HTML/CSS/JS, nginx (no build step, no framework) | 8080 |
| `backend` | Node.js / Express API | 3001 |
| `ai-service` | Python / FastAPI (NLU, RAG, LLM chat, OCR) | 8001 |
| `postgres` | PostgreSQL 18 + PostGIS | 5433 (host) / 5432 (Docker-internal) |
| `kafka` | Apache Kafka (outbox events, recommendations) | internal only |
| `outbox-worker` / `event-consumer` / `recommendation-consumer` | Node.js background workers | — |

Ollama (the LLM) is **not containerized** — it runs on the host machine and is reached via `host.docker.internal`. See [DOCKER.md](DOCKER.md) for full networking details.

## Repository structure

```
backend/        Express API, database repositories, migrations (backend/scripts/migrate.js)
frontend/       Static HTML/CSS/JS, served by nginx in Docker or python http.server locally
ai-service/     FastAPI app: NLU pipeline, RAG, virtual doctor, OCR
mobile/         Flutter app (see mobile/DEVELOPMENT_NETWORKING.md)
db/             Canonical, ordered SQL migrations (run via `npm run db:migrate`)
docs/           Setup, staging deployment, and feature-specific docs
cypress/        End-to-end tests
scripts/        Maintenance/dev scripts
```

## Prerequisites

- Docker Desktop
- Ollama running on the host machine with the model this project uses (`qwen2:7b` by default — see `OLLAMA_MODEL` in `.env.example`). Needed for AI chat/summarization features; the rest of the app works without it.

## Run with Docker

```bash
cp .env.example .env   # fill in real values
docker compose up --build
```

This starts `postgres`, `kafka`, `backend` (+ workers), `ai-service`, and `frontend`.

Apply database migrations (once postgres is healthy):

```bash
npm run db:migrate
```

Then open http://localhost:8080.

Full details (health checks, Ollama networking, GPU overlay, troubleshooting) are in [DOCKER.md](DOCKER.md).

For deploying this stack to an Azure VM as a staging environment, see [docs/AZURE_STAGING_DEPLOYMENT.md](docs/AZURE_STAGING_DEPLOYMENT.md) and [docs/STAGING_CHECKLIST.md](docs/STAGING_CHECKLIST.md) (uses `docker-compose.staging.yml` + `.env.staging`, created from `.env.staging.example`).

## Run without Docker (alternative)

```bash
npm run setup   # installs Node deps + creates a Python venv + installs requirements.txt
npm run dev     # runs ai-service, backend, and frontend together
```

Needs, on the host:
- A local PostgreSQL + PostGIS instance, migrated with `npm run db:migrate`
- Python 3.12 (not 3.13+ — asyncpg/pydantic have no prebuilt wheels there)
- Ollama running (`npm run dev:ollama`, or however you already run it)

## Database

- Database: `medorbit`, schema: `medorbit`
- Host access (dev tools, pgAdmin, psql): `127.0.0.1:5433`
- Docker-internal access (backend/ai-service containers): `postgres:5432`
- Migrations live in [db/](db/) as ordered, numbered SQL files, applied via `backend/scripts/migrate.js` (`npm run db:migrate`, `npm run db:migrate:status`, `npm run db:migrate:dry-run`)
- Seed data: `npm run db:seed`

## Environment setup

All configuration is a single root `.env` file, read by the backend, ai-service, and `docker-compose.yml`. Copy `.env.example` to `.env` and fill in real values (DB credentials, JWT secret, Google client ID, email SMTP, etc.) — see the comments in `.env.example` for what each variable does and how host vs. Docker values differ.

## Development workflow

- `npm run dev` — run ai-service, backend, and frontend concurrently on the host
- `npm run db:migrate` / `db:migrate:status` / `db:migrate:dry-run` — apply/inspect migrations
- Docker Compose profiles: `--profile tools` (migrations), `--profile test` (test database + backend-test container)

## Testing / CI

- `docker compose --profile test up -d --build --wait backend-test` then `npm run test:auth:docker`, `npm run test:s1a:docker`, etc. run backend integration tests against a disposable test database (see `package.json` scripts)
- `npm run test:admin-notifications-ui`, `test:user-content-ui`, `test:doctor-scheduling-ui` — targeted frontend UI tests (Node)
- Cypress (`cypress.config.js`) covers end-to-end browser flows
- GitHub Actions (`.github/workflows/ci.yml`) builds and runs the Docker Compose stack on a GPU-less runner — `docker-compose.gpu.yml` is a separate opt-in overlay for CUDA-accelerated Whisper, kept out of the base compose file specifically so CI stays GPU-free

## Operational notes

- `docker-compose.gpu.yml` — optional GPU overlay for `ai-service` (Whisper on CUDA); apply with `-f docker-compose.yml -f docker-compose.gpu.yml`
- `docker-compose.staging.yml` — standalone Azure VM staging stack, not an overlay; postgres publishes no host port there
- Known backend gaps hit while building the current frontend (missing endpoints, a data-isolation constraint on shared doctor notes) are tracked in [BACKEND_NEEDED.md](BACKEND_NEEDED.md) and referenced directly from code comments — check it before assuming an endpoint or feature gap is unintentional.

## Team

- Ali Dawood
- Omar Abumazen
- Supervisor: Dr. Bashar Tahayna
