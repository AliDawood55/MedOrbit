# MedOrbit

A smart healthcare platform for Nablus, Palestine - graduation project, An-Najah National University.

## Tech stack

- Frontend: vanilla HTML/CSS/JS (no build step, no framework)
- Backend: Node.js / Express API
- AI service: Python / FastAPI (NLU pipeline, RAG, LLM chat, OCR report summarization)
- Database: PostgreSQL + PostGIS
- LLM: Ollama (local, host-run - see below)
- Maps: Leaflet

## Prerequisites

- Docker Desktop
- Ollama running on the host machine, with the model this project uses (qwen2:7b by default - see .env.example's OLLAMA_MODEL). Needed for AI chat/summarization features; the rest of the app works without it.
- The database is not seeded automatically - the SQL migration folders (db/, database/) are not in the repo. You restore from a medorbit_backup.backup file (see below).

## Run with Docker

```bash
cp .env.example .env   # fill in real values
docker compose up --build
```

This starts postgres (PostGIS on PostgreSQL 18 - must match the backup file's version), backend, ai-service, and frontend.

Restore the database (once postgres is up):

```bash
docker cp medorbit_backup.backup medorbit-postgres:/tmp/medorbit_backup.backup
docker exec -it medorbit-postgres pg_restore -U postgres -d medorbit --clean --if-exists /tmp/medorbit_backup.backup
```

Verify the restore:

```bash
docker exec -it medorbit-postgres psql -U postgres -d medorbit -c "SELECT COUNT(*) FROM medorbit.clinics;"
# expect: 178
```

Then open http://localhost:8080.

Full details (health checks, Ollama networking, restore options, troubleshooting) are in [DOCKER.md](DOCKER.md).

## Run without Docker (alternative)

```bash
npm run setup   # installs Node deps + creates a Python venv + installs requirements.txt
npm run dev     # runs ai-service, backend, and frontend together
```

Needs, on the host:
- A local PostgreSQL + PostGIS instance (same schema as db/*.sql)
- Python 3.12 (not 3.13+ - asyncpg/pydantic have no prebuilt wheels there)
- Ollama running (npm run dev:ollama, or however you already run it)

## Services & ports

| Service | Port |
|---|---|
| Frontend | 8080 |
| Backend | 3001 |
| AI service | 8001 |
| PostgreSQL | 5432 |
| Ollama | 11434 |

## Team

- Ali Dawood 
- Omar Abumazen 
- Supervisor: Dr. Bashar Tahayna
