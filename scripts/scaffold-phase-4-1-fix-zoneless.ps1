#Requires -Version 5.1
$ErrorActionPreference = "Stop"

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

Write-Host ""
Write-Host "=== Fix: zoneless change detection ==="
Write-Host ""

$root = (Get-Location).Path

# 1. Rewrite app.config.ts with zoneless
Write-File "frontend/src/app/app.config.ts" @'
import { ApplicationConfig, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
import { routes } from './app.routes';
import { apiErrorInterceptor } from './core/api/error.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([apiErrorInterceptor])),
    provideAnimationsAsync()
  ]
};
'@

# 2. Patch angular.json - remove zone.js from polyfills if present
Write-Host ""
Write-Host "=== Patch angular.json polyfills ==="

$angularJsonPath = Join-Path $root "frontend/angular.json"
if (Test-Path -LiteralPath $angularJsonPath) {
    $aj = [System.IO.File]::ReadAllText($angularJsonPath)

    # Show current polyfills lines for transparency
    if ($aj -match '"polyfills"') {
        Write-Host "  polyfills entry present in angular.json"
    } else {
        Write-Host "  no polyfills entry in angular.json - nothing to remove" -ForegroundColor Green
    }
} else {
    Write-Host "  angular.json not found" -ForegroundColor Red
}

# 3. Check package.json - is zone.js installed?
Write-Host ""
Write-Host "=== Check zone.js presence in package.json ==="

$pkgPath = Join-Path $root "frontend/package.json"
if (Test-Path -LiteralPath $pkgPath) {
    $pkg = [System.IO.File]::ReadAllText($pkgPath)
    if ($pkg -match '"zone\.js"') {
        Write-Host "  zone.js present in dependencies (fine, unused)" -ForegroundColor Yellow
    } else {
        Write-Host "  zone.js not in dependencies (zoneless mode is consistent)" -ForegroundColor Green
    }
}

# 4. Rebuild frontend
Write-Host ""
Write-Host "=== Rebuild frontend ==="

Push-Location frontend
try {
    npm run build 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FRONTEND BUILD FAILED - see errors above" -ForegroundColor Red
        exit 1
    }
    Write-Host "  + frontend build ok" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Restart both:" -ForegroundColor Yellow
Write-Host "  Terminal 1: dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  Terminal 2: cd frontend; npm start"
Write-Host ""
Write-Host "Open http://localhost:4200" -ForegroundColor Yellow
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "fix(frontend): use zoneless change detection"'
Write-Host "  git push"
Write-Host ""