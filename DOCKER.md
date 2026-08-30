# Running MedOrbit with Docker

This document covers the Docker Compose stack: what's containerized, what
isn't (and why), how to restore the database, and how to verify everything
is healthy.

## What's in the stack

| Service | Image / build | Published port | Notes |
|---|---|---|---|
| `postgres` | `postgis/postgis:18-3.6` | `127.0.0.1:5433` → 5432 | Named volume `medorbit_pgdata` (PG18 — must match the `medorbit_backup.backup` source version). Loopback-only; container-to-container traffic uses `postgres:5432` |
| `kafka` | `apache/kafka:3.9.0` | *none* | KRaft single node, named volume `medorbit_kafka_data`. Reachable only inside the Compose network |
| `backend` | `backend/Dockerfile` (Node 20) | 3001 | Express API |
| `outbox-worker` | `backend/Dockerfile` (Node 20) | *none* | Relays the transactional outbox to Kafka; health on internal 3002 |
| `event-consumer` | `backend/Dockerfile` (Node 20) | *none* | Consumes domain events; health on internal 3003 |
| `recommendation-consumer` | `backend/Dockerfile` (Node 20) | *none* | Builds recommendation profiles; health on internal 3004 |
| `ai-service` | `ai-service/Dockerfile` (Python 3.12) | 8001 | FastAPI + NLU/RAG/LLM pipeline |
| `frontend` | `frontend/Dockerfile` (nginx 1.27-alpine) | 8080 | Static files, no build step |

The backend and the three workers are **one image**, `medorbit-backend` — the same
Node application with different entrypoints. Compose names it explicitly so all
four services share a single build and a single tag rather than four identical
copies. The `test` and `tools` profiles likewise share `medorbit-backend-test`,
built from `backend/Dockerfile.test`.

Ollama is **not** in this list — see below.

## Build context

Every image builds from the **repository root** (the backend needs the root
`package.json`/`package-lock.json` for its npm workspace, and `ai-service` needs
the root `requirements.txt`). A single root `.dockerignore` decides what is sent
for all of them — there are deliberately no per-Dockerfile ignore files, because
BuildKit's `<dockerfile>.dockerignore` *replaces* the root file rather than
merging with it, and no build here needs a path another build must exclude.

BuildKit derives what to send from each Dockerfile's `COPY` instructions, and
every Dockerfile here copies a *subtree* (`backend/`, `frontend/`, `ai-service/`)
plus the two root manifests — none copies the repository root. That makes the
ignore rules fall into two groups:

**Rules that shrink a real transfer** (they sit under a copied subtree):

| Excluded | Size | Why |
|---|---|---|
| `ai-service/virtual_doctor/assets/tts_voices` | ~121 MB | Downloaded Piper voices — see *Downloaded model caches* below |
| `ai-service/virtual_doctor/generated` | ~7 MB | Generated PDF reports and the TTS wav cache — runtime output |
| `ai-service/{data,tests,benchmarks}` | ~3 MB | Dev/training tooling, never imported at runtime |
| `frontend/tests` | 128 KB | Needed by neither image, and nginx would otherwise serve them at `/tests/*` |

Measured effect on the `ai-service` build context: **134.59 MB → 824 kB**. The
backend and frontend contexts were already small (~1.75 MB and ~10 kB) and are
essentially unchanged.

**Rules that are defensive** (root-level, so nothing copies them today):
`mobile/` (~2.4 GB of Flutter app and build output), `backups/` (~114 MB of
database dumps), `.venv`, `node_modules`, `.git`, `.pytest_cache`. These do not
shrink today's builds. They are kept so that the tree BuildKit scans stays
bounded, and so a future `COPY . .` — or a fifth Dockerfile — cannot silently
pull gigabytes into an image. Don't remove them on the grounds that the numbers
above don't move.

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
- **`node:20-bullseye-slim`** plus `npm ci` for the backend is usually the
  fastest of the three builds. It is built once and reused by the backend and
  all three workers.
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

### Downloaded model caches

Two model caches are deliberately **not** baked into any image — they are large,
downloaded rather than tracked in git, and would otherwise be destroyed by every
rebuild:

| What | Where it persists | Size |
|---|---|---|
| Whisper (STT) weights | Named volume `medorbit_hf_cache` → `/root/.cache/huggingface` | ~1.5 GB for `medium` |
| Piper (TTS) voices | Bind mount `ai-service/virtual_doctor/assets/tts_voices/` | ~60 MB per voice (ar + en) |

Both download automatically on first use and are reused from then on. The Piper
voices use a bind mount rather than a named volume because that directory is
already the cache location `virtual_doctor/voice/tts.py` uses, so an existing
local download is picked up as-is and an ai-service run directly on the host
shares the same files. Neither directory needs backing up — a lost cache costs
one re-download, not data.

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
