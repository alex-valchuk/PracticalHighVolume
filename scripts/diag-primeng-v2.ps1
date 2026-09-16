# PowerShell 5.1 compatible

$root = (Get-Location).Path
$nm = Join-Path $root "frontend\node_modules\primeng"

Write-Host ""
Write-Host "=== PrimeNG v2 structure ==="
Write-Host ("Path: " + $nm)
Write-Host ""

if (-not (Test-Path -LiteralPath $nm)) {
    Write-Host "primeng not found" -ForegroundColor Red
    exit 1
}

Write-Host "--- Top-level folders ---"
Get-ChildItem -Path $nm -Directory | ForEach-Object { Write-Host ("  [DIR] " + $_.Name) }

Write-Host ""
Write-Host "--- Top-level files ---"
Get-ChildItem -Path $nm -File | ForEach-Object { Write-Host ("  " + $_.Name) }

Write-Host ""
Write-Host "--- primeng/package.json (exports/version) ---"
$pkgJsonPath = Join-Path $nm "package.json"
if (Test-Path -LiteralPath $pkgJsonPath) {
    $pkg = [System.IO.File]::ReadAllText($pkgJsonPath) | ConvertFrom-Json
    Write-Host ("  name    : " + $pkg.name)
    Write-Host ("  version : " + $pkg.version)
    Write-Host ("  main    : " + $pkg.main)
    Write-Host ("  module  : " + $pkg.module)
    Write-Host ("  types   : " + $pkg.types)
    if ($pkg.exports) {
        Write-Host "  exports (first keys):"
        $pkg.exports.PSObject.Properties | Select-Object -First 20 | ForEach-Object {
            Write-Host ("    " + $_.Name)
        }
    }
} else {
    Write-Host "  primeng/package.json not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- Search for p-confirmDialog selector ---"
$allDts = Get-ChildItem -Path $nm -Recurse -Filter "*.d.ts" -ErrorAction SilentlyContinue
Write-Host ("  scanning " + $allDts.Count + " .d.ts files")

$confirmHits = $allDts | Select-String -Pattern "p-confirmDialog" -List -ErrorAction SilentlyContinue
if ($confirmHits) {
    foreach ($h in $confirmHits | Select-Object -First 5) {
        Write-Host ("  HIT: " + $h.Path.Replace($nm, "primeng"))
        Write-Host ("       " + $h.Line.Trim())
    }
} else {
    Write-Host "  no matches for p-confirmDialog" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- Search for p-sortIcon selector ---"
$sortHits = $allDts | Select-String -Pattern "p-sortIcon" -List -ErrorAction SilentlyContinue
if ($sortHits) {
    foreach ($h in $sortHits | Select-Object -First 5) {
        Write-Host ("  HIT: " + $h.Path.Replace($nm, "primeng"))
        Write-Host ("       " + $h.Line.Trim())
    }
} else {
    Write-Host "  no matches for p-sortIcon" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- Search for ConfirmDialogModule / SortIconModule classes ---"
$moduleHits = $allDts | Select-String -Pattern "class ConfirmDialog|class SortIcon" -List -ErrorAction SilentlyContinue
if ($moduleHits) {
    foreach ($h in $moduleHits | Select-Object -First 10) {
        Write-Host ("  HIT: " + $h.Path.Replace($nm, "primeng"))
        Write-Host ("       " + $h.Line.Trim())
    }
} else {
    Write-Host "  no matches for ConfirmDialog/SortIcon classes" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- What is exported from 'primeng/table' ---"
$tblPkg = Join-Path $nm "table\package.json"
if (Test-Path -LiteralPath $tblPkg) {
    $tblPkgContent = [System.IO.File]::ReadAllText($tblPkg) | ConvertFrom-Json
    Write-Host ("  primeng/table version: " + $tblPkgContent.version)
    Write-Host ("  types: " + $tblPkgContent.types)
    if ($tblPkgContent.exports) {
        Write-Host "  exports:"
        $tblPkgContent.exports.PSObject.Properties | ForEach-Object { Write-Host ("    " + $_.Name) }
    }
} else {
    Write-Host "  primeng/table/package.json NOT FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- Sub-package folders under primeng/lib (if exists) ---"
$libDir = Join-Path $nm "lib"
if (Test-Path -LiteralPath $libDir) {
    Write-Host ("  " + $libDir.Replace($nm, "primeng"))
    Get-ChildItem -Path $libDir -Directory | Select-Object -First 50 | ForEach-Object {
        Write-Host ("    " + $_.Name)
    }
} else {
    Write-Host "  primeng/lib not found"
}

Write-Host ""
Write-Host "--- What is exported from 'primeng/confirmdialog' ---"
$cdPkg = Join-Path $nm "confirmdialog\package.json"
if (Test-Path -LiteralPath $cdPkg) {
    $cdPkgContent = [System.IO.File]::ReadAllText($cdPkg) | ConvertFrom-Json
    Write-Host ("  primeng/confirmdialog version: " + $cdPkgContent.version)
    Write-Host ("  types: " + $cdPkgContent.types)
} else {
    Write-Host "  primeng/confirmdialog/package.json NOT FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== PASTE ENTIRE OUTPUT BACK ===" -ForegroundColor Cyan
Write-Host ""