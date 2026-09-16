# PowerShell 5.1 compatible

$root = (Get-Location).Path
$typesDir = Join-Path $root "frontend\node_modules\primeng\types"

Write-Host ""
Write-Host "=== PrimeNG 22 InputNumber / ToggleSwitch diagnostics ==="
Write-Host ""

# --- Check inputnumber .d.ts ---
$inPath = Join-Path $typesDir "primeng-inputnumber.d.ts"
if (Test-Path -LiteralPath $inPath) {
    Write-Host "--- primeng/inputnumber ---"
    $content = [System.IO.File]::ReadAllText($inPath)
    $selectors = [regex]::Matches($content, '"(p-[^"]+)"')
    foreach ($m in $selectors) { Write-Host ("  selector fragment: " + $m.Groups[1].Value) }

    $exports = [regex]::Matches($content, "export\s+\{[^}]+\}")
    foreach ($m in $exports) {
        $line = $m.Value -replace "\s+", " "
        Write-Host ("  " + $line)
    }
    # First few lines for context
    Write-Host "  (first 10 lines)"
    $lines = [System.IO.File]::ReadAllLines($inPath)
    for ($i = 0; $i -lt [Math]::Min(10, $lines.Length); $i++) {
        Write-Host ("    " + $lines[$i])
    }
} else {
    Write-Host "primeng-inputnumber.d.ts NOT FOUND" -ForegroundColor Yellow
}

# --- Grep for InputNumber selector across .d.ts ---
Write-Host ""
Write-Host "--- Search for InputNumber selector ---"
$allDts = Get-ChildItem -Path $typesDir -Filter "*.d.ts" -ErrorAction SilentlyContinue
$hits = $allDts | Select-String -Pattern "p-inputnumber|p-inputNumber" -List -ErrorAction SilentlyContinue
if ($hits) {
    foreach ($h in $hits | Select-Object -First 5) {
        Write-Host ("  HIT: " + $h.Path)
        Write-Host ("       " + $h.Line.Trim())
    }
} else {
    Write-Host "  no matches" -ForegroundColor Yellow
}

# --- Check toggleswitch ---
Write-Host ""
Write-Host "--- primeng/toggleswitch ---"
$tsPath = Join-Path $typesDir "primeng-toggleswitch.d.ts"
if (Test-Path -LiteralPath $tsPath) {
    $content = [System.IO.File]::ReadAllText($tsPath)
    $selectors = [regex]::Matches($content, '"(p-[^"]+)"')
    foreach ($m in $selectors) { Write-Host ("  selector fragment: " + $m.Groups[1].Value) }
    $exports = [regex]::Matches($content, "export\s+\{[^}]+\}")
    foreach ($m in $exports) {
        $line = $m.Value -replace "\s+", " "
        Write-Host ("  " + $line)
    }
} else {
    Write-Host "  primeng-toggleswitch.d.ts NOT FOUND" -ForegroundColor Yellow
}

# --- Full InputNumber .d.ts content (small enough) ---
Write-Host ""
Write-Host "--- Full primeng-inputnumber.d.ts ---"
if (Test-Path -LiteralPath $inPath) {
    $lines = [System.IO.File]::ReadAllLines($inPath)
    Write-Host ("  total lines: " + $lines.Length)
    foreach ($line in $lines) {
        Write-Host ("  " + $line)
    }
}

Write-Host ""
Write-Host "=== PASTE OUTPUT BACK ===" -ForegroundColor Cyan
Write-Host ""