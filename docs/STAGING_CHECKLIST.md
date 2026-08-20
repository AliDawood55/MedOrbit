# Staging Deployment Checklist

Quick-reference checklist for deploying MedOrbit to the Azure staging VM.
Full details: [`AZURE_STAGING_DEPLOYMENT.md`](AZURE_STAGING_DEPLOYMENT.md).

## Azure setup
- [ ] Ubuntu LTS VM created (Standard_B2s or B2ms, no GPU, 30GB+ disk)
- [ ] NSG rules: 22 (your IP), 8080, 3001, 8001 open; 5432 **not** opened
- [ ] VM public IP noted

## VM install
- [ ] `apt update && apt upgrade`
- [ ] Docker Engine + Compose plugin installed
- [ ] User added to `docker` group (optional)

## Project setup
- [ ] Repo cloned/uploaded to VM
- [ ] `cp .env.staging.example .env.staging`
- [ ] `.env.staging` filled in: `DB_PASSWORD`, `JWT_SECRET`, `CORS_ORIGIN`,
      `FRONTEND_URL`, `BACKEND_PUBLIC_URL`, `GOOGLE_CLIENT_ID`, `EMAIL_*`
      (all with real values, VM's real public IP, fresh secrets — not local
      dev's)
- [ ] `medorbit_backup.backup` copied to VM and restored into postgres

## Start & verify
- [ ] `docker compose -f docker-compose.staging.yml --env-file .env.staging up -d --build`
      (or `./scripts/deploy-staging.sh`)
- [ ] `docker compose -f docker-compose.staging.yml ps` — all healthy
- [ ] `curl http://localhost:3001/api/health` (on VM)
- [ ] `curl http://localhost:8001/health` (on VM)
- [ ] `curl http://<VM_PUBLIC_IP>:3001/api/health` (from your machine)
- [ ] `curl http://<VM_PUBLIC_IP>:8001/health` (from your machine)
- [ ] `http://<VM_PUBLIC_IP>:8080` loads in a browser on a different network

## Mobile (optional, temporary local edits — revert after testing)
- [ ] Android: uncommented staging domain in `network_security_config.xml`,
      filled in real IP
- [ ] iOS: uncommented staging `NSAppTransportSecurity` block in
      `Info.plist`, filled in real IP
- [ ] `flutter run` / `flutter build apk --release` with
      `--dart-define=MEDORBIT_API_URL=...` / `MEDORBIT_AI_URL=...`
- [ ] **Reverted both mobile edits** before committing anything

## Cost safety
- [ ] VM stopped/deallocated when not actively testing
- [ ] Azure Cost Management checked

## Known limitations (expected, not bugs)
- [ ] AI-chat features (virtual doctor, symptom/drug checker LLM reasoning)
      unavailable — Ollama not installed on staging
- [ ] Traffic is HTTP only, no TLS
- [ ] Backend/AI ports directly exposed, no reverse proxy yet
