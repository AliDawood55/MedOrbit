# Azure VM Staging Deployment

Staging deployment guide for MedOrbit: one Ubuntu Azure VM running the Docker
Compose stack behind Caddy-managed HTTPS. Only ports 80 and 443 are public;
backend, AI, PostgreSQL, Kafka, and workers stay inside Docker or on VM
loopback. **This is staging, not production** — see
[Security limitations](#security-limitations) before pointing real users at it.

Related: [`docker-compose.staging.yml`](../docker-compose.staging.yml),
[`.env.staging.example`](../.env.staging.example),
[`STAGING_CHECKLIST.md`](STAGING_CHECKLIST.md), local dev setup in
[`DOCKER.md`](../DOCKER.md).

## 1. Recommended VM

- **Ubuntu 22.04 LTS** (or latest LTS available), no GPU.
- Size: **Standard_B2s** (2 vCPU / 4 GB RAM) is the minimum to try; if
  ai-service (Whisper STT, OCR via tesseract, PDF generation via WeasyPrint)
  feels slow or gets OOM-killed under `docker compose ps`, step up to
  **Standard_B2ms** (2 vCPU / 8 GB RAM). Ollama is intentionally not running
  on this VM (see [Ollama](#note-on-ollama) below), so you don't need the
  16 GB+ a full LLM setup would call for.
- Disk: 30 GB+ (Standard SSD is fine for staging).
- This sizing fits comfortably within typical Azure-for-Students credit.

## 2. Azure inbound ports (NSG rules)

| Port | Purpose | Source |
|---|---|---|
| 22 | SSH | Restrict to your IP if possible |
| 80 | HTTP-to-HTTPS redirect / certificate issuance | Any |
| 443 | Caddy TLS proxy (web, API, Socket.IO) | Any |
| 5432 | Postgres | **Never open** — `docker-compose.staging.yml` doesn't even publish this port to the host |

## 3. Install Docker on the VM

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Optional: run docker without sudo
sudo usermod -aG docker $USER
newgrp docker
```

## 4. Get the project onto the VM

```bash
git clone <your-repo-url> MedOrbit
cd MedOrbit
```

(Or `scp`/`rsync` the project directory up if you're not pushing this branch
to a remote yet.)

## 5. Create `.env.staging`

```bash
cp .env.staging.example .env.staging
nano .env.staging   # fill in DB_PASSWORD, JWT_SECRET, CORS_ORIGIN, FRONTEND_URL,
                     # BACKEND_PUBLIC_URL, EMAIL_*, GOOGLE_CLIENT_ID with real values
```

Create a DNS A/AAAA record for `MEDORBIT_PUBLIC_HOST` before deployment. Use
that exact HTTPS origin for `CORS_ORIGIN`, `FRONTEND_URL`, and
`BACKEND_PUBLIC_URL`. Generate a fresh `JWT_SECRET` (e.g.
`openssl rand -base64 48`) and a fresh DB password — **do not reuse your
local dev `.env` secrets.**

`.env.staging` is gitignored; it never leaves the VM unless you copy it
yourself.

### Initialize a fresh staging database

The tracked baseline creates the schema only; it does not create application
users or seed data. Start PostgreSQL, bootstrap the historical baseline, then
apply migrations:

```bash
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d postgres
docker compose -f docker-compose.staging.yml --env-file .env.staging --profile tools run --rm --no-deps db-bootstrap
docker compose -f docker-compose.staging.yml --env-file .env.staging --profile tools run --rm --no-deps db-migrate up
```

### Restore historical data (optional)

Restore a backup only when staging needs existing data. This replaces schema
objects and data in the selected database, so do it only after a backup and
only for an intentional replacement:

```bash
docker cp medorbit_backup.backup medorbit-postgres-staging:/tmp/medorbit_backup.backup
docker compose -f docker-compose.staging.yml exec postgres \
  pg_restore -U <DB_USER> -d <DB_NAME> --clean --if-exists /tmp/medorbit_backup.backup
```

Then apply any migrations newer than the backup:

```bash
docker compose -f docker-compose.staging.yml --env-file .env.staging --profile tools run --rm --no-deps db-migrate up
```

## 6. Start the stack

```bash
docker compose -f docker-compose.staging.yml --env-file .env.staging --profile tls up -d --build
```

Or use the helper script (does the same, plus health polling):

```bash
./scripts/deploy-staging.sh
```

### Backup and restore verification

Run a backup/restore verification before each staging release and after a
PostgreSQL or PostGIS upgrade. It creates a fresh custom-format backup,
restores it only into the explicitly named disposable database, and verifies
PostGIS, the migration ledger, core tables, and a data query. It refuses to
use the canonical `DB_NAME` as its restore target.

```bash
VERIFY_DB_NAME=medorbit_restore_verify_$(date +%Y%m%d) \
  ./scripts/verify-backup-restore.sh
```

The verified database is retained for inspection. When disk space matters,
remove it only after reviewing the successful output:

```bash
KEEP_RESTORE_DATABASE=false \
VERIFY_DB_NAME=medorbit_restore_verify_$(date +%Y%m%d) \
  ./scripts/verify-backup-restore.sh
```

Database backups do not contain `backend/uploads/` or `backend/storage/`.
Back up those runtime directories separately, with restricted permissions,
on the same schedule.

### Persistent uploads and reports

The staging Compose file persists `backend/uploads/` and `backend/storage/` on
the VM. These files are not part of PostgreSQL backups. Before the first
deployment of this storage change, recover any files from the old backend
container before it is recreated:

```bash
mkdir -p backend/runtime-recovery
docker cp medorbit-backend-staging:/app/backend/uploads backend/runtime-recovery/uploads
docker cp medorbit-backend-staging:/app/backend/storage backend/runtime-recovery/storage
```

Review and merge the recovered files into `backend/uploads/` and
`backend/storage/`. Restrict access to those host directories and include them
in the staging backup strategy.

## 7. Verify

Locally on the VM:

```bash
docker compose -f docker-compose.staging.yml ps
curl http://localhost:3001/api/health
docker compose -f docker-compose.staging.yml --env-file .env.staging exec -T ai-service \
  python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health', timeout=3)"
```

From your own machine, against the public DNS hostname:

```bash
curl https://<MEDORBIT_PUBLIC_HOST>/api/health
```

## 8. Mobile staging — run

Use only the HTTPS backend origin. Do not add plaintext Android/iOS network
exceptions and do not set `MEDORBIT_AI_URL`: the AI service is internal-only.

```bash
flutter run -d RFCY806MHLV \
  --dart-define=MEDORBIT_API_URL=https://<MEDORBIT_PUBLIC_HOST>/api
```

Ali must complete the remaining client-to-backend AI repoints before mobile AI
features can use this topology.

## 9. Mobile staging — release build

```bash
flutter build apk --release \
  --dart-define=MEDORBIT_API_URL=https://<MEDORBIT_PUBLIC_HOST>/api
```

No cleartext exception is needed for HTTPS.

## 10. Web verification from another device

Open `https://<MEDORBIT_PUBLIC_HOST>` in a browser on a different network.
The web client calls the backend through the same HTTPS origin at `/api`; do
not expose or configure port `3001` in the browser. The final client must
never derive or call an AI origin.

## 11. Cost safety

- Use the smallest VM size that works (see [section 1](#1-recommended-vm)).
- **Stop the VM** (`az vm deallocate` or via the Azure portal) when not
  actively testing — you are not billed for compute while deallocated.
- Monitor spend in the Azure Cost Management dashboard, especially if using
  student credit with a hard cap.

## Security limitations

This setup is **staging only**, not production-ready:

- TLS is terminated by Caddy; certificate issuance requires a real DNS name,
  inbound 80/443 access, and a reachable VM.
- Existing legacy web/mobile code still has direct AI paths. Do not expose it
  publicly after enabling this topology; Ali's backend-repoint work is a
  release dependency.
- The Android/iOS cleartext exceptions are a deliberate, temporary hole in
  otherwise-correct security config — revert them outside of active staging
  testing.
- AI CORS is closed and the AI service is reachable only from the Docker
  network.
- Use strong, unique secrets in `.env.staging` (never the local dev ones).
- Postgres is never exposed publicly — keep it that way.

## Note on Ollama

Ollama (the local LLM behind the Virtual Doctor, symptom checker, and drug
checker reasoning) is **not installed on the staging VM**. Those
AI-chat-dependent endpoints will fail or time out on staging. Core flows —
auth, clinics, doctors, appointments, notifications, profile, chatbot/map,
non-LLM parts of the API — are unaffected. Installing Ollama on staging is
listed under [remaining production hardening](#remaining-production-hardening).

## Remaining production hardening

- Complete the web/mobile backend AI proxy repoints before publicly releasing
  the TLS topology.
- Decide whether/how to run Ollama on staging (or point staging at a shared
  Ollama instance) if AI-chat features need to be tested end-to-end.
- Consider a container registry (ACR/GHCR) instead of building on the VM,
  once a CI/CD deploy pipeline is introduced.
- Automate DB backups (see `scripts/backup-db.sh`) on a schedule.
