# PowerShell 5.1 compatible

$root = (Get-Location).Path
$typesDir = Join-Path $root "frontend\node_modules\primeng\types"

Write-Host ""
Write-Host "=== PrimeNG 22 exports diagnostics ==="
Write-Host ""

function Show-Exports {
    param([string]$File, [string]$Label)
    if (-not (Test-Path -LiteralPath $File)) {
        Write-Host ("  " + $Label + " : FILE NOT FOUND") -ForegroundColor Yellow
        return
    }
    Write-Host ("--- " + $Label + " ---")
    $lines = [System.IO.File]::ReadAllLines($File)
    # Show export statements only
    $inExport = $false
    foreach ($line in $lines) {
        if ($line -match "^export\s") {
            Write-Host ("  " + $line.Trim())
        }
        # For multi-line exports like "export { A, B, C };"
        if ($line -match "^\s*[A-Z][a-zA-Z]+(\s+as\s+\w+)?,?\s*$" -and $inExport) {
            Write-Host ("      " + $line.Trim())
        }
        if ($line -match "^export\s*\{") { $inExport = $true }
        if ($inExport -and $line -match "\}") { $inExport = $false }
    }
    Write-Host ""
}

Show-Exports (Join-Path $typesDir "primeng-confirmdialog.d.ts") "primeng/confirmdialog"
Show-Exports (Join-Path $typesDir "primeng-table.d.ts") "primeng/table"
Show-Exports (Join-Path $typesDir "primeng-toast.d.ts") "primeng/toast"
Show-Exports (Join-Path $typesDir "primeng-dialog.d.ts") "primeng/dialog"
Show-Exports (Join-Path $typesDir "primeng-datepicker.d.ts") "primeng/datepicker"
Show-Exports (Join-Path $typesDir "primeng-textarea.d.ts") "primeng/textarea"
Show-Exports (Join-Path $typesDir "primeng-inputtext.d.ts") "primeng/inputtext"
Show-Exports (Join-Path $typesDir "primeng-button.d.ts") "primeng/button"
Show-Exports (Join-Path $typesDir "primeng-tag.d.ts") "primeng/tag"
Show-Exports (Join-Path $typesDir "primeng-api.d.ts") "primeng/api"

Write-Host "--- Full list of types files ---"
Get-ChildItem -Path $typesDir -File | Select-Object -First 60 | ForEach-Object {
    Write-Host ("  " + $_.Name)
}

Write-Host ""
Write-Host "=== PASTE ENTIRE OUTPUT BACK ===" -ForegroundColor Cyan
Write-Host ""