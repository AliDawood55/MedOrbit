#!/usr/bin/env bash
# Each suite makes deliberate rate-limit assertions. Restarting only the
# disposable test processes between suites keeps those assertions realistic
# while preventing one suite's in-memory limiter state from leaking to the
# next. PostgreSQL remains the same schema-only medorbit_test database.
set -Eeuo pipefail

run_suite() {
  local label="$1"
  shift

  echo ""
  echo "===== Backend integration suite: ${label} ====="
  docker compose --profile test rm -sf backend-test ai-service-test >/dev/null 2>&1 || true
  docker compose --profile test up -d --no-build --wait backend-test ai-service-test
  # The test database is a schema-only clone of local development data. Its
  # migration ledger can legitimately lag behind new version-controlled
  # migrations, so bring it to the image's schema before every suite.
  docker compose --profile test exec -T backend-test node scripts/migrate.js up
  docker compose --profile test exec -T backend-test "$@"
}

run_suite "auth baseline" npm run test:auth:baseline
run_suite "clinic applicant role boundary" node tests/clinic-applicant-role.test.js
run_suite "S1A auth hardening" npm run test:s1a
run_suite "S1B clinical authorization" npm run test:s1b
run_suite "S1C admin foundation" npm run test:s1c
run_suite "S2 doctor lifecycle" npm run test:s2
run_suite "S3 care relationships" npm run test:s3
run_suite "S4 social feed" npm run test:s4
run_suite "S5 direct messaging" npm run test:s5
run_suite "S7 event foundation" npm run test:s7
run_suite "S8 recommendations" npm run test:s8
run_suite "S8.5 ML readiness" npm run test:s8.5
run_suite "S8.6 signal activation" npm run test:s8.6
run_suite "admin rate and notifications" npm run test:admin-rate-notifications
run_suite "user content" npm run test:user-content
run_suite "profile communication" npm run test:profile-communication-ux
run_suite "doctor scheduling" npm run test:doctor-scheduling
run_suite "analytics" npm run test:analytics
run_suite "report safety" npm run test:report-safety
run_suite "global auth gate" npm run test:auth-gate
run_suite "billing entitlements" npm run test:billing
run_suite "billing checkout lifecycle" npm run test:billing:checkout
run_suite "saved places" node tests/saved-places.test.js
run_suite "CORS policy" node tests/cors.test.js
