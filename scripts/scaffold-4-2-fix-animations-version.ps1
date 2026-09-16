#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Fix: install @angular/animations at the exact project version ==="
Write-Host ""

$root = (Get-Location).Path
$pkgPath = Join-Path $root "frontend\package.json"

if (-not (Test-Path -LiteralPath $pkgPath)) {
    Write-Host "frontend/package.json not found" -ForegroundColor Red
    exit 1
}

$pkg = [System.IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json

# Read current @angular/core version
$coreVersion = $null
if ($pkg.dependencies -and $pkg.dependencies.'@angular/core') {
    $coreVersion = $pkg.dependencies.'@angular/core'
}
elseif ($pkg.devDependencies -and $pkg.devDependencies.'@angular/core') {
    $coreVersion = $pkg.devDependencies.'@angular/core'
}

if (-not $coreVersion) {
    Write-Host "Could not find @angular/core in package.json" -ForegroundColor Red
    exit 1
}

Write-Host ("Detected @angular/core version: " + $coreVersion)

# Normalize: strip ^ or ~ prefix so we pin exactly
$pinVersion = $coreVersion -replace '^[\^~]', ''
Write-Host ("Will install @angular/animations@" + $pinVersion)

Write-Host ""
Write-Host "=== Installing ==="

Push-Location frontend
try {
    npm install "@angular/animations@$pinVersion" --save --legacy-peer-deps 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "npm install failed. Trying without --legacy-peer-deps..." -ForegroundColor Yellow
        npm install "@angular/animations@$pinVersion" --save 2>&1 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Host ""
            Write-Host "Install failed. Show full error:" -ForegroundColor Red
            Write-Host "  cd frontend"
            Write-Host "  npm install @angular/animations --save --legacy-peer-deps --verbose"
            exit 1
        }
    }
    Write-Host "  + @angular/animations installed" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Verify in package.json:" -ForegroundColor Yellow
$verify = [System.IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json
if ($verify.dependencies.'@angular/animations') {
    Write-Host ("  @angular/animations = " + $verify.dependencies.'@angular/animations') -ForegroundColor Green
} else {
    Write-Host "  not found in dependencies - check manually" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== Now re-run the phase 4.2 script ===" -ForegroundColor Yellow
Write-Host "  .\scaffold-4-2.ps1"
Write-Host ""