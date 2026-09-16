# PowerShell 5.1 compatible

$root = (Get-Location).Path
$nm = Join-Path $root "frontend\node_modules\primeng"

Write-Host ""
Write-Host "=== PrimeNG selectors diagnostics ==="
Write-Host ("primeng in " + $nm)
Write-Host ""

function Find-SelectorsIn {
    param([string]$File, [string]$Label)
    if (-not (Test-Path -LiteralPath $File)) {
        Write-Host ("  " + $Label + " : FILE NOT FOUND") -ForegroundColor Yellow
        Write-Host ("    " + $File)
        return
    }
    Write-Host ("  " + $Label)
    $content = [System.IO.File]::ReadAllText($File)
    # Find all selector: 'xxx' occurrences
    $matches = [regex]::Matches($content, "selector:\s*'([^']+)'")
    if ($matches.Count -eq 0) {
        Write-Host "    no selectors found"
    } else {
        foreach ($m in $matches) {
            Write-Host ("    selector: '" + $m.Groups[1].Value + "'")
        }
    }
    # Find all exported class names
    $exports = [regex]::Matches($content, "export\s+declare\s+class\s+(\w+)")
    if ($exports.Count -gt 0) {
        foreach ($e in $exports) {
            Write-Host ("    export class: " + $e.Groups[1].Value)
        }
    }
}

# --- ConfirmDialog ---
Write-Host "--- confirmdialog ---"
$cdDir = Join-Path $nm "confirmdialog"
if (Test-Path -LiteralPath $cdDir) {
    Get-ChildItem -Path $cdDir -Recurse -Filter "*.d.ts" | ForEach-Object {
        Write-Host ("  file: " + $_.FullName.Replace($nm, "primeng"))
        Find-SelectorsIn $_.FullName "    ->"
    }
} else {
    Write-Host "  confirmdialog folder NOT FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- table (for sortIcon) ---"
$tDir = Join-Path $nm "table"
if (Test-Path -LiteralPath $tDir) {
    Get-ChildItem -Path $tDir -Recurse -Filter "*.d.ts" | ForEach-Object {
        $name = $_.Name
        if ($name -match "sorticon|sort" -or $name -match "index") {
            Write-Host ("  file: " + $_.FullName.Replace($nm, "primeng"))
            Find-SelectorsIn $_.FullName "    ->"
        }
    }
    # Also list all d.ts filenames
    Write-Host ""
    Write-Host "  all .d.ts files in table:"
    Get-ChildItem -Path $tDir -Recurse -Filter "*.d.ts" | ForEach-Object {
        Write-Host ("    " + $_.FullName.Replace($nm, "primeng"))
    }
} else {
    Write-Host "  table folder NOT FOUND" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "--- top-level exports in primeng (index.d.ts) ---"
$indexDts = Join-Path $nm "index.d.ts"
if (Test-Path -LiteralPath $indexDts) {
    $lines = [System.IO.File]::ReadAllLines($indexDts)
    foreach ($line in $lines) {
        if ($line -match "confirmdialog|table|sorticon") {
            Write-Host ("  " + $line)
        }
    }
} else {
    Write-Host "  primeng/index.d.ts not found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== PASTE THIS OUTPUT BACK ===" -ForegroundColor Cyan
Write-Host ""