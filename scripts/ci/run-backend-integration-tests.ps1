# Windows equivalent of run-backend-integration-tests.sh.
# Docker Desktop is available through PowerShell even when WSL integration is
# disabled, so this keeps the same CI route-family gate runnable locally.
$ErrorActionPreference = 'Stop'

function Invoke-DockerCompose {
    param([string[]]$Arguments)

    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed with exit code $LASTEXITCODE"
    }
}

# Keep each suite isolated from in-memory rate-limit state, as in the Linux CI
# runner. PostgreSQL remains the shared disposable medorbit_test database.
function Invoke-BackendSuite {
    param([string]$Label, [string[]]$Command)

    Write-Host "`n===== Backend integration suite: $Label ====="
    # Docker Compose writes normal stop-progress messages to stderr. Invoke
    # this cleanup through cmd so PowerShell does not convert that successful
    # stderr output into a NativeCommandError under ErrorActionPreference=Stop.
    & cmd.exe /d /c 'docker compose --profile test rm -sf backend-test ai-service-test >NUL 2>&1'
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose test-container cleanup failed with exit code $LASTEXITCODE"
    }
    Invoke-DockerCompose @('--profile', 'test', 'up', '-d', '--no-build', '--wait', 'backend-test', 'ai-service-test')
    Invoke-DockerCompose (@('--profile', 'test', 'exec', '-T', 'backend-test') + $Command)
}

Invoke-BackendSuite 'auth baseline' @('npm', 'run', 'test:auth:baseline')
Invoke-BackendSuite 'S1A auth hardening' @('npm', 'run', 'test:s1a')
Invoke-BackendSuite 'S1B clinical authorization' @('npm', 'run', 'test:s1b')
Invoke-BackendSuite 'S1C admin foundation' @('npm', 'run', 'test:s1c')
Invoke-BackendSuite 'S2 doctor lifecycle' @('npm', 'run', 'test:s2')
Invoke-BackendSuite 'S3 care relationships' @('npm', 'run', 'test:s3')
Invoke-BackendSuite 'S4 social feed' @('npm', 'run', 'test:s4')
Invoke-BackendSuite 'S5 direct messaging' @('npm', 'run', 'test:s5')
Invoke-BackendSuite 'S7 event foundation' @('npm', 'run', 'test:s7')
Invoke-BackendSuite 'S8 recommendations' @('npm', 'run', 'test:s8')
Invoke-BackendSuite 'S8.5 ML readiness' @('npm', 'run', 'test:s8.5')
Invoke-BackendSuite 'S8.6 signal activation' @('npm', 'run', 'test:s8.6')
Invoke-BackendSuite 'admin rate and notifications' @('npm', 'run', 'test:admin-rate-notifications')
Invoke-BackendSuite 'user content' @('npm', 'run', 'test:user-content')
Invoke-BackendSuite 'profile communication' @('npm', 'run', 'test:profile-communication-ux')
Invoke-BackendSuite 'doctor scheduling' @('npm', 'run', 'test:doctor-scheduling')
Invoke-BackendSuite 'analytics' @('npm', 'run', 'test:analytics')
Invoke-BackendSuite 'report safety' @('npm', 'run', 'test:report-safety')
Invoke-BackendSuite 'global auth gate' @('npm', 'run', 'test:auth-gate')
Invoke-BackendSuite 'billing entitlements' @('npm', 'run', 'test:billing')
Invoke-BackendSuite 'billing checkout lifecycle' @('npm', 'run', 'test:billing:checkout')
Invoke-BackendSuite 'saved places' @('node', 'tests/saved-places.test.js')
Invoke-BackendSuite 'CORS policy' @('node', 'tests/cors.test.js')
