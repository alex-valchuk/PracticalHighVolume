# Stop the local development environment (docker-compose).

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

Write-Host ""
Write-Host "Stopping local infrastructure..." -ForegroundColor Yellow

cmd /c "docker compose down 2>&1" | Out-Null

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host "Data volumes are preserved. Run scripts\dev-local.ps1 to start again."
Write-Host ""