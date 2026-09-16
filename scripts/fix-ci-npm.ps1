$root = (Get-Location).Path
$frontendDir = Join-Path $root "frontend"

Write-Host ""
Write-Host "=== Fix: npm legacy-peer-deps via .npmrc ==="
Write-Host ""

# 1. Create .npmrc
$npmrcPath = Join-Path $frontendDir ".npmrc"
$npmrcContent = @'
legacy-peer-deps=true
'@
[System.IO.File]::WriteAllText($npmrcPath, $npmrcContent, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + frontend/.npmrc (legacy-peer-deps=true)" -ForegroundColor Green

# 2. Regenerate package-lock.json with legacy-peer-deps
Write-Host ""
Write-Host "=== Regenerating package-lock.json ==="
Write-Host ""

Push-Location $frontendDir
try {
    # Remove old lock and node_modules to regenerate cleanly
    if (Test-Path -LiteralPath "package-lock.json") {
        Remove-Item -LiteralPath "package-lock.json" -Force
        Write-Host "  - removed old package-lock.json"
    }

    Write-Host "  Running npm install (this may take a minute)..."
    cmd /c "npm install 2>&1"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  npm install FAILED" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + package-lock.json regenerated with legacy-peer-deps" -ForegroundColor Green

    Write-Host ""
    Write-Host "  Verifying npm ci works..."
    cmd /c "npm ci --dry-run 2>&1"

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  npm ci --dry-run FAILED - check output above" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + npm ci succeeds" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Files changed:" -ForegroundColor Yellow
Write-Host "  frontend/.npmrc          (new)"
Write-Host "  frontend/package-lock.json (regenerated)"
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  git add frontend/.npmrc frontend/package-lock.json"
Write-Host '  git commit -m "fix(frontend): add .npmrc with legacy-peer-deps for CI compatibility"'
Write-Host "  git push"
Write-Host ""
Write-Host "CI should pass now on the frontend job." -ForegroundColor Yellow
Write-Host ""