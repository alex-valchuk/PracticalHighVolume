# PowerShell 5.1 compatible - no "??" operator, no ternary

$root = (Get-Location).Path
$pkgPath = Join-Path $root "frontend\package.json"

Write-Host ""
Write-Host "=== Frontend diagnostics ==="
Write-Host ""

if (-not (Test-Path -LiteralPath $pkgPath)) {
    Write-Host "frontend/package.json not found" -ForegroundColor Red
    exit 1
}

function Get-Dep($deps, $name) {
    if ($null -eq $deps) { return "<missing>" }
    $prop = $deps.PSObject.Properties[$name]
    if ($null -eq $prop) { return "<missing>" }
    return [string]$prop.Value
}

$pkg = [System.IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json

Write-Host "Current versions in package.json:"
Write-Host ("  @angular/core        : " + (Get-Dep $pkg.dependencies '@angular/core'))
Write-Host ("  @angular/common      : " + (Get-Dep $pkg.dependencies '@angular/common'))
Write-Host ("  @angular/animations  : " + (Get-Dep $pkg.dependencies '@angular/animations'))
Write-Host ("  primeng              : " + (Get-Dep $pkg.dependencies 'primeng'))
Write-Host ("  @primeng/themes      : " + (Get-Dep $pkg.dependencies '@primeng/themes'))
Write-Host ("  primeicons           : " + (Get-Dep $pkg.dependencies 'primeicons'))
Write-Host ""

# --- Install @angular/animations if missing ---
$anim = Get-Dep $pkg.dependencies '@angular/animations'
if ($anim -eq "<missing>") {
    $coreVersion = Get-Dep $pkg.dependencies '@angular/core'
    $pinVersion = $coreVersion -replace '^[\^~]', ''

    Write-Host ("Installing @angular/animations@" + $pinVersion + " ...")
    Write-Host ""

    Push-Location (Join-Path $root "frontend")
    try {
        cmd /c "npm install @angular/animations@$pinVersion --save --legacy-peer-deps 2>&1"
        $code = $LASTEXITCODE
    } finally {
        Pop-Location
    }

    if ($code -ne 0) {
        Write-Host ""
        Write-Host ("npm install failed with exit code " + $code) -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "Install finished. Re-reading package.json..."
    $pkg = [System.IO.File]::ReadAllText($pkgPath) | ConvertFrom-Json
}

Write-Host ""
Write-Host "=== Final state (package.json) ==="
Write-Host ("  @angular/core        : " + (Get-Dep $pkg.dependencies '@angular/core'))
Write-Host ("  @angular/common      : " + (Get-Dep $pkg.dependencies '@angular/common'))
Write-Host ("  @angular/animations  : " + (Get-Dep $pkg.dependencies '@angular/animations'))
Write-Host ("  primeng              : " + (Get-Dep $pkg.dependencies 'primeng'))
Write-Host ("  @primeng/themes      : " + (Get-Dep $pkg.dependencies '@primeng/themes'))
Write-Host ("  primeicons           : " + (Get-Dep $pkg.dependencies 'primeicons'))

# --- Actual installed versions in node_modules ---
Write-Host ""
Write-Host "=== Actual installed (node_modules) ==="

function Show-Installed($rel, $label) {
    $p = Join-Path $root ("frontend\" + $rel)
    if (Test-Path -LiteralPath $p) {
        $v = ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json).version
        Write-Host ("  " + $label + " : " + $v)
    } else {
        Write-Host ("  " + $label + " : NOT INSTALLED") -ForegroundColor Yellow
    }
}

Show-Installed "node_modules\@angular\core\package.json"        "@angular/core"
Show-Installed "node_modules\@angular\common\package.json"      "@angular/common"
Show-Installed "node_modules\@angular\animations\package.json"  "@angular/animations"
Show-Installed "node_modules\primeng\package.json"              "primeng"
Show-Installed "node_modules\@primeng\themes\package.json"      "@primeng/themes"
Show-Installed "node_modules\primeicons\package.json"           "primeicons"

# --- Node & npm versions ---
Write-Host ""
Write-Host "=== Tooling ==="
Write-Host ("  node : " + (node --version))
Write-Host ("  npm  : " + (npm --version))

Write-Host ""
Write-Host "=== PASTE THIS OUTPUT BACK ===" -ForegroundColor Cyan
Write-Host ""