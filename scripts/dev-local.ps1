# Start the local development environment.
# Brings up docker-compose infrastructure. The API is started manually
# from Visual Studio so the debugger is available.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host ""
Write-Host "=== Local environment ==="
Write-Host ""

if (-not (Test-Path -LiteralPath "docker-compose.yml")) {
    Write-Host "docker-compose.yml not found. Run from repository root." -ForegroundColor Red
    exit 1
}

Write-Host "1. Starting infrastructure..."
cmd /c "docker compose up -d 2>&1" | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "docker compose up failed." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "2. Waiting for services to become healthy (10 seconds)..."
Start-Sleep -Seconds 10

Write-Host ""
Write-Host "3. Container status:"
cmd /c "docker compose ps 2>&1" | ForEach-Object { Write-Host "   $_" }

Write-Host ""
Write-Host "=== Ready ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  - Visual Studio: open FlightsPlatform.slnx, press F5"
Write-Host "  - Terminal:      cd frontend; npm run dev:local"
Write-Host ""
Write-Host "URLs:" -ForegroundColor Cyan
Write-Host "  SPA        http://localhost:4200"
Write-Host "  API        https://localhost:50943/scalar/v1"
Write-Host "  Jaeger     http://localhost:16686"
Write-Host "  Prometheus http://localhost:9090"
Write-Host "  Grafana    http://localhost:3000"
Write-Host "  RabbitMQ   http://localhost:15672"
Write-Host ""