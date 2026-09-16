# PowerShell 5.1 compatible

function Write-File {
    param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)] [string] $Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $full = Join-Path (Get-Location).Path $Path
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path)
}

$root = (Get-Location).Path

Write-Host ""
Write-Host "=== Fix 4.2: correct PrimeNG 22 selectors ==="
Write-Host ""

# 1. app.component.ts - <p-confirmDialog> -> <p-confirmdialog>
Write-Host "=== 1. app.component.ts ==="

$appCompPath = Join-Path $root "frontend\src\app\app.component.ts"
$content = [System.IO.File]::ReadAllText($appCompPath)
$content = $content -replace '<p-confirmDialog>', '<p-confirmdialog>'
$content = $content -replace '</p-confirmDialog>', '</p-confirmdialog>'
[System.IO.File]::WriteAllText($appCompPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + updated app.component.ts: p-confirmdialog"

# 2. airports.page.ts - <p-sortIcon> -> <p-sort-icon>
Write-Host ""
Write-Host "=== 2. airports.page.ts ==="

$airportsPath = Join-Path $root "frontend\src\app\features\airports\airports.page.ts"
$content = [System.IO.File]::ReadAllText($airportsPath)
$content = $content -replace '<p-sortIcon ', '<p-sort-icon '
$content = $content -replace '</p-sortIcon>', '</p-sort-icon>'
[System.IO.File]::WriteAllText($airportsPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + updated airports.page.ts: p-sort-icon"

# 3. Verify
Write-Host ""
Write-Host "=== 3. Verify ==="

$check1 = [System.IO.File]::ReadAllText($appCompPath)
if ($check1 -match '<p-confirmdialog>') {
    Write-Host "  OK app.component.ts uses <p-confirmdialog>" -ForegroundColor Green
} else {
    Write-Host "  FAIL: <p-confirmdialog> not found" -ForegroundColor Red
}

$check2 = [System.IO.File]::ReadAllText($airportsPath)
if ($check2 -match '<p-sort-icon ') {
    Write-Host "  OK airports.page.ts uses <p-sort-icon>" -ForegroundColor Green
} else {
    Write-Host "  FAIL: <p-sort-icon> not found" -ForegroundColor Red
}

# 4. Build
Write-Host ""
Write-Host "=== 4. Build frontend ==="

Push-Location (Join-Path $root "frontend")
try {
    cmd /c "npm run build 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "FRONTEND BUILD FAILED - see errors above" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + frontend build ok" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Restart frontend:" -ForegroundColor Yellow
Write-Host "  cd frontend; npm start"
Write-Host ""
Write-Host "Open http://localhost:4200" -ForegroundColor Yellow
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(frontend): phase 4.2 - Airports and Flights pages"'
Write-Host "  git push"
Write-Host ""