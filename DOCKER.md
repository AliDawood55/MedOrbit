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

## Database: two options, and which one to use

`db/` and `database/` (the raw SQL) are gitignored — per the existing
`.gitignore` comment, the project is distributed via a `pg_dump` custom-format
backup file, `medorbit_backup.backup`, kept locally rather than committed.
Because of that, this compose file **cannot** auto-seed the database on first
start; there's no SQL guaranteed to exist in a fresh clone.

Two ways to get data into the `postgres` container:

**(a) Restore from `medorbit_backup.backup` — recommended, use this one.**
Self-contained: works from a fresh clone plus just the one backup file,
independent of whether you happen to have the gitignored `db/`/`database/`
folders checked out locally. This matches how the project is already meant
to be distributed.

**(b) Point the compose stack at an existing local Postgres instead.**
Skip the `postgres` service, set `DB_HOST` to wherever that instance is
reachable from inside a container (e.g. `host.docker.internal` if it runs on
your host). Only worth it if you already have a fully-seeded Postgres running
and don't want a second copy of the data — but it re-introduces exactly the
container-to-host networking complexity that having `postgres` as a service
was meant to avoid, and two people on the same team can no longer assume "just
run `docker compose up`" gives them the same DB state. Not recommended as the
default.

**This project uses (a).** Steps, after `docker compose up` has started the
`postgres` service at least once:

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

`--clean --if-exists` makes this safe to re-run against an already-seeded
database (drops existing objects first instead of erroring on conflicts).

## First-time setup

```bash
# 1. Create your .env from the template and fill in real values
cp .env.example .env

# 2. Build and start everything
docker compose up --build
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
- The database will be **empty** on first start — see the restore steps
  above. Nothing in this stack seeds it for you.

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
