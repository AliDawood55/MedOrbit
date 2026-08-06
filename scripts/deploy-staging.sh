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

echo "==> Building and starting the staging stack"
docker compose -f docker-compose.staging.yml --env-file .env.staging up -d --build

echo "==> Waiting for backend and ai-service health checks"
for i in $(seq 1 24); do
  BACKEND_OK=false
  AI_OK=false
  curl -fsS http://localhost:3001/api/health > /dev/null 2>&1 && BACKEND_OK=true
  curl -fsS http://localhost:8001/health > /dev/null 2>&1 && AI_OK=true

  if [ "$BACKEND_OK" = true ] && [ "$AI_OK" = true ]; then
    echo "==> backend and ai-service are healthy"
    docker compose -f docker-compose.staging.yml ps
    exit 0
  fi
  sleep 5
done

echo "Error: backend and/or ai-service did not become healthy in time." >&2
docker compose -f docker-compose.staging.yml ps
docker compose -f docker-compose.staging.yml logs --tail=50
exit 1
