# Azure VM Staging Deployment

Staging deployment guide for MedOrbit: one Ubuntu Azure VM running the existing
Docker Compose stack over plain HTTP/public IP, so web and mobile can be
tested from any network. **This is staging, not production** — see
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
| 80 | HTTP via nginx reverse proxy | Only if/when you add one (not part of this initial staging setup) |
| 8080 | Frontend (direct) | Any (staging only) |
| 3001 | Backend API (temporary direct testing) | Any (staging only) |
| 8001 | AI service (temporary direct testing) | Any (staging only) |
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

Use the VM's actual public IP (from the Azure portal) for `CORS_ORIGIN`,
`FRONTEND_URL`, and `BACKEND_PUBLIC_URL`. Generate a fresh `JWT_SECRET` (e.g.
`openssl rand -base64 48`) and a fresh DB password — **do not reuse your
local dev `.env` secrets.**

`.env.staging` is gitignored; it never leaves the VM unless you copy it
yourself.

### Restore the database

Staging doesn't auto-seed the database (same as local dev — see
[`DOCKER.md`](../DOCKER.md)). After `docker compose up` has started postgres
once:

```bash
docker cp medorbit_backup.backup medorbit-postgres-staging:/tmp/medorbit_backup.backup
docker compose -f docker-compose.staging.yml exec postgres \
  pg_restore -U <DB_USER> -d <DB_NAME> --clean --if-exists /tmp/medorbit_backup.backup
```

## 6. Start the stack

```bash
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d --build
```

Or use the helper script (does the same, plus health polling):

```bash
./scripts/deploy-staging.sh
```

## 7. Verify

Locally on the VM:

```bash
docker compose -f docker-compose.staging.yml ps
curl http://localhost:3001/api/health
curl http://localhost:8001/health
```

From your own machine, against the VM's public IP:

```bash
curl http://<VM_PUBLIC_IP>:3001/api/health
curl http://<VM_PUBLIC_IP>:8001/health
```

## 8. Mobile staging — run

Android's `network_security_config.xml` and iOS's App Transport Security
both block plaintext HTTP to arbitrary hosts by default. A temporary,
clearly-labeled staging exception has been added to both — **you must
uncomment it and fill in the VM's real IP locally** before this will work on
a device (the real IP is never committed):

- Android: edit `mobile/android/app/src/main/res/xml/network_security_config.xml`,
  uncomment the `STAGING (temporary)` domain block, replace the placeholder
  with your VM's IP.
- iOS: edit `mobile/ios/Runner/Info.plist`, uncomment the
  `STAGING (temporary)` `NSAppTransportSecurity` block, replace the
  placeholder with your VM's IP.

Then:

```bash
flutter run -d RFCY806MHLV \
  --dart-define=MEDORBIT_API_URL=http://<VM_PUBLIC_IP>:3001/api \
  --dart-define=MEDORBIT_AI_URL=http://<VM_PUBLIC_IP>:8001
```

**Revert both edits** (re-comment, or `git checkout` the files) before
committing or building a release — do not ship the cleartext exception.

## 9. Mobile staging — release build

```bash
flutter build apk --release \
  --dart-define=MEDORBIT_API_URL=http://<VM_PUBLIC_IP>:3001/api \
  --dart-define=MEDORBIT_AI_URL=http://<VM_PUBLIC_IP>:8001
```

Same caveat: the Android network security exception must be uncommented
locally for this build to reach the VM, and reverted afterward.

## 10. Web verification from another device

Open `http://<VM_PUBLIC_IP>:8080` in a browser on a different network (e.g.
your phone on cellular data). The frontend self-derives its API/AI origin
from the browser's URL (`window.location.hostname`), so no frontend config
changes are needed — it will call `http://<VM_PUBLIC_IP>:3001` and `:8001`
automatically.

## 11. Cost safety

- Use the smallest VM size that works (see [section 1](#1-recommended-vm)).
- **Stop the VM** (`az vm deallocate` or via the Azure portal) when not
  actively testing — you are not billed for compute while deallocated.
- Monitor spend in the Azure Cost Management dashboard, especially if using
  student credit with a hard cap.

## Security limitations

This setup is **staging only**, not production-ready:

- Traffic is plain HTTP — credentials and data are not encrypted in transit.
- Backend/AI service ports are directly exposed rather than behind a reverse
  proxy.
- The Android/iOS cleartext exceptions are a deliberate, temporary hole in
  otherwise-correct security config — revert them outside of active staging
  testing.
- ai-service's CORS is wide open (`allow_origins=["*"]`, pre-existing, not
  changed by this staging setup) and has no authentication layer.
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

- Add a domain name and HTTPS (Let's Encrypt via an nginx/Caddy reverse
  proxy), then drop the direct 3001/8001 exposure in favor of proxied paths.
- Remove the mobile cleartext exceptions once HTTPS is in place.
- Add authentication and a scoped CORS allowlist to ai-service.
- Decide whether/how to run Ollama on staging (or point staging at a shared
  Ollama instance) if AI-chat features need to be tested end-to-end.
- Consider a container registry (ACR/GHCR) instead of building on the VM,
  once a CI/CD deploy pipeline is introduced.
- Automate DB backups (see `scripts/backup-db.sh`) on a schedule.
