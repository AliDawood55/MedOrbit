#!/usr/bin/env bash
# Deploy/redeploy the MedOrbit staging stack on the Azure VM.
# Run from the project root on the VM: ./scripts/deploy-staging.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f .env.staging ]; then
  echo "Error: .env.staging not found. Copy .env.staging.example to .env.staging and fill it in first." >&2
  exit 1
fi

echo "==> Pulling latest code (if this is a git checkout)"
git pull --ff-only || echo "   (not a fast-forward pull, or not a git repo — skipping)"

if ! grep -q '^MEDORBIT_PUBLIC_HOST=.' .env.staging; then
  echo "Error: MEDORBIT_PUBLIC_HOST must be set to a DNS hostname before TLS deployment." >&2
  exit 1
fi

echo "==> Building and starting the TLS staging stack"
docker compose -f docker-compose.staging.yml --env-file .env.staging --profile tls up -d --build

echo "==> Waiting for backend, AI, Kafka, workers, and HTTPS health checks"
for i in $(seq 1 24); do
  BACKEND_OK=false
  AI_OK=false
  WORKERS_OK=true
  curl -fsS http://localhost:3001/api/health > /dev/null 2>&1 && BACKEND_OK=true
  docker compose -f docker-compose.staging.yml --env-file .env.staging exec -T ai-service python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/health', timeout=3)" > /dev/null 2>&1 && AI_OK=true
  for worker in outbox-worker event-consumer recommendation-consumer; do
    docker compose -f docker-compose.staging.yml --env-file .env.staging ps --status running --services "$worker" | grep -qx "$worker" || WORKERS_OK=false
  done

  if [ "$BACKEND_OK" = true ] && [ "$AI_OK" = true ] && [ "$WORKERS_OK" = true ]; then
    curl -fsS "https://$(grep '^MEDORBIT_PUBLIC_HOST=' .env.staging | cut -d= -f2)/api/health" > /dev/null
    echo "==> backend and ai-service are healthy; HTTPS proxy is reachable"
    docker compose -f docker-compose.staging.yml ps
    exit 0
  fi
  sleep 5
done

echo "Error: backend and/or ai-service did not become healthy in time." >&2
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs --tail=50
exit 1
