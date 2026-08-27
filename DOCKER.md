# Running MedOrbit with Docker

This document covers the Docker Compose stack: what's containerized, what
isn't (and why), how to restore the database, and how to verify everything
is healthy.

## What's in the stack

| Service | Image / build | Port | Notes |
|---|---|---|---|
| `postgres` | `postgis/postgis:18-3.6` | 5432 | Named volume `medorbit_pgdata` (PG18 — must match the `medorbit_backup.backup` source version) |
| `backend` | `backend/Dockerfile` (Node 18) | 3001 | Express API |
| `ai-service` | `ai-service/Dockerfile` (Python 3.12) | 8001 | FastAPI + NLU/RAG/LLM pipeline |
| `frontend` | `frontend/Dockerfile` (nginx) | 8080 | Static files, no build step |

Ollama is **not** in this list — see below.

## Ollama: intentionally not containerized

The model (`qwen2:7b`) is roughly 4GB. Baking it into a container image (or
even a compose-managed volume) means re-downloading/rebuilding it per
project/per machine for no benefit — it's a general-purpose local model, not
something specific to this stack.

Instead: run Ollama on the **host** machine as usual (`ollama serve`, or
however you already run it), and the `ai-service` container reaches it via
Docker Desktop's built-in `host.docker.internal` DNS name, which resolves to
the host machine from inside any container. This is wired up in
`docker-compose.yml`:

```yaml
environment:
  OLLAMA_URL: http://host.docker.internal:11434/api/generate
extra_hosts:
  - "host.docker.internal:host-gateway"   # makes this work on Linux too
```

`host.docker.internal` works out of the box on Docker Desktop for Windows/Mac
(what this project targets); the `extra_hosts` line is just a portability
safety net for Linux hosts, where that name isn't automatically defined.

**You must have Ollama running on your host before chat/summarization
features that call the LLM will work.** The stack will still start and the
health checks will still pass without it — only those specific features will
fail at request time until Ollama is up.

## Database bootstrap and optional data restore

The tracked baseline at `scripts/ci/base-schema.sql` creates the historical
schema required before numbered migration `001`; it creates no application
users or sample data. Bootstrap is explicit so `docker compose up` never
modifies an existing database merely because a container starts.

For a fresh empty database:

```bash
docker compose up -d postgres
npm run db:initialize
```

`npm run db:initialize` first runs the safe `db-bootstrap` service, then
applies migrations. Bootstrap skips a database that already has
`medorbit.users` and refuses a partial `medorbit` schema.

Restoring a `pg_dump` backup remains optional when you need historical data,
not when you only need a runnable schema. Restore it only into a database you
intend to replace. After `docker compose up` has started `postgres`:

```bash
# 1. Copy the backup file into the running container
docker cp medorbit_backup.backup medorbit-postgres:/tmp/medorbit_backup.backup

# 2. Restore it (creates all tables/data under the medorbit schema)
docker exec -it medorbit-postgres pg_restore \
  -U postgres -d medorbit --clean --if-exists \
  /tmp/medorbit_backup.backup

# 3. (optional) remove the copy from inside the container
docker exec medorbit-postgres rm /tmp/medorbit_backup.backup
```

`--clean --if-exists` drops existing objects. Use it only for an intentional
restore into a disposable or explicitly replaced database. After a restore,
run `npm run db:migrate` to apply migrations newer than the backup.

## First-time setup

```bash
# 1. Create your .env from the template and fill in real values
cp .env.example .env

# 2. Start PostgreSQL, initialize a fresh schema, then start the stack
docker compose up -d postgres
npm run db:initialize
docker compose up -d --build
```

### What to expect on first run

- **`postgis/postgis:18-3.6`** is a few hundred MB — first pull can take a
  couple of minutes on a normal connection.
- **`python:3.12-slim`** base is small, but `apt-get install tesseract-ocr
  tesseract-ocr-ara poppler-utils` plus `pip install -r requirements.txt`
  (fastapi, asyncpg, pillow, pdfplumber, etc.) adds a few minutes to the
  `ai-service` build the first time.
- **`node:18-bullseye-slim`** plus `npm ci` for the backend is usually the
  fastest of the three builds.
- **`nginx:1.27-alpine`** for the frontend is near-instant — it's just static
  files.
- Total first run: expect roughly 5–10 minutes depending on connection speed
  and whether layers are cached. Subsequent runs (`docker compose up`, no
  `--build`, no dependency changes) start in seconds.
- `backend` and `ai-service` will show `restarting` briefly if they start
  before `postgres` reports healthy — this is expected; `depends_on:
  condition: service_healthy` holds them back, but the first health check
  itself takes `start_period` seconds to run.
- The database has a complete **schema but no application data** after
  `npm run db:initialize`. Restore a backup only when historical data is
  required.

### Persistent clinical files

PostgreSQL backups do **not** contain uploaded files or generated PDFs. The
backend mounts both runtime directories from the project host:

| Host directory | Container directory | Contents |
|---|---|---|
| `backend/uploads/` | `/app/backend/uploads/` | Avatars and general uploads |
| `backend/storage/` | `/app/backend/storage/` | Medical-record attachments and generated reports |

Before first deploying this Compose change over an existing backend container,
copy any runtime files that may still be inside that old container. Its
previous mount targeted `/app/uploads`, while the application actually writes
under `/app/backend`.

```bash
# Run before recreating/removing the old backend container.
mkdir -p backend/runtime-recovery
docker cp medorbit-backend:/app/backend/uploads backend/runtime-recovery/uploads
docker cp medorbit-backend:/app/backend/storage backend/runtime-recovery/storage
```

Review and merge the recovered directories into `backend/uploads/` and
`backend/storage/` before recreating the backend. Treat both directories as
sensitive patient data: restrict host access and include them in operational
backup/restore procedures.

## Verifying everything is healthy

```bash
# Container status + health
docker compose ps

# Postgres: should show "healthy" once ready
docker exec medorbit-postgres pg_isready -U postgres -d medorbit

# Backend
curl http://localhost:3001/api/health

# ai-service
curl http://localhost:8001/health
# expect: {"status":"healthy","service":"medorbit-ai","version":"3.0.0"}

# Frontend
curl -I http://localhost:8080/public/index.html   # expect HTTP/1.1 200 OK

# Logs, if something looks wrong
docker compose logs -f backend
docker compose logs -f ai-service
```

Open `http://localhost:8080/` in a browser (redirects to
`/public/index.html`) to use the app.

## Stopping / cleaning up

```bash
docker compose down            # stop containers, keep the postgres volume (data survives)
docker compose down -v         # also delete the postgres volume (data loss — full reset)
```
