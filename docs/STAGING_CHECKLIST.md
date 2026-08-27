# Staging Deployment Checklist

Quick-reference checklist for deploying MedOrbit to the Azure staging VM.
Full details: [`AZURE_STAGING_DEPLOYMENT.md`](AZURE_STAGING_DEPLOYMENT.md).

## Azure setup
- [ ] Ubuntu LTS VM created (Standard_B2s or B2ms, no GPU, 30GB+ disk)
- [ ] NSG rules: 22 (your IP), 80 and 443 open; 8080, 3001, 8001, Kafka,
      and 5432 **not** opened
- [ ] VM public IP noted

## VM install
- [ ] `apt update && apt upgrade`
- [ ] Docker Engine + Compose plugin installed
- [ ] User added to `docker` group (optional)

## Project setup
- [ ] Repo cloned/uploaded to VM
- [ ] `cp .env.staging.example .env.staging`
- [ ] `.env.staging` filled in: `DB_PASSWORD`, `JWT_SECRET`, `CORS_ORIGIN`,
      `FRONTEND_URL`, `BACKEND_PUBLIC_URL`, `MEDORBIT_PUBLIC_HOST`,
      `GOOGLE_CLIENT_ID`, `EMAIL_*` (all with fresh values; the public host is
      a real DNS name, not an IP)
- [ ] Fresh schema initialized with tracked baseline + migrations, or an
      intentional backup restore completed and followed by migrations
- [ ] Backup/restore verification completed with a disposable
      `*_restore_verify_*` database; PostGIS and the migration ledger survived
- [ ] `backend/uploads/` and `backend/storage/` are included in the VM backup
      schedule; PostgreSQL dumps do not include them

## Start & verify
- [ ] `docker compose -f docker-compose.staging.yml --env-file .env.staging up -d postgres`
- [ ] Fresh DB only: `docker compose -f docker-compose.staging.yml --env-file .env.staging --profile tools run --rm --no-deps db-bootstrap`
- [ ] `docker compose -f docker-compose.staging.yml --env-file .env.staging --profile tools run --rm --no-deps db-migrate up`
- [ ] `./scripts/deploy-staging.sh` (starts the TLS proxy, Kafka, and workers)
- [ ] Existing deployment only: runtime uploads/reports recovered from the old
      backend container before it is recreated, then stored under
      `backend/uploads/` and `backend/storage/`
- [ ] `docker compose -f docker-compose.staging.yml ps` — all healthy
- [ ] `curl http://localhost:3001/api/health` (on VM)
- [ ] AI health works through `docker compose ... exec ai-service` on the VM
- [ ] `https://<MEDORBIT_PUBLIC_HOST>/api/health` works from your machine
- [ ] `https://<MEDORBIT_PUBLIC_HOST>` loads in a browser on a different network
- [ ] Kafka and all three workers show healthy in `docker compose ... ps`

## Mobile
- [ ] Use only `https://<MEDORBIT_PUBLIC_HOST>/api` for `MEDORBIT_API_URL`
- [ ] Do not set `MEDORBIT_AI_URL` or add plaintext security exceptions

## Cost safety
- [ ] VM stopped/deallocated when not actively testing
- [ ] Azure Cost Management checked

## Known limitations (expected, not bugs)
- [ ] AI-chat features (virtual doctor, symptom/drug checker LLM reasoning)
      unavailable — Ollama not installed on staging
- [ ] Client release remains blocked until Ali repoints every direct AI call
      to the authenticated backend; AI is internal-only in this topology
