$root = (Get-Location).Path
$ciPath = Join-Path $root ".github\workflows\ci.yml"

if (-not (Test-Path -LiteralPath $ciPath)) {
    Write-Host ".github/workflows/ci.yml not found" -ForegroundColor Red
    exit 1
}

$content = [System.IO.File]::ReadAllText($ciPath)

# Replace NODE_VERSION 20.x -> 24.x
$updated = $content -replace "NODE_VERSION:\s*'20\.x'", "NODE_VERSION: '24.x'"

if ($updated -eq $content) {
    Write-Host "  NODE_VERSION not changed - check pattern" -ForegroundColor Yellow
} else {
    [System.IO.File]::WriteAllText($ciPath, $updated, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + updated NODE_VERSION to 24.x" -ForegroundColor Green
}

# Verify
$check = [System.IO.File]::ReadAllText($ciPath)
if ($check -match "NODE_VERSION:\s*'24\.x'") {
    Write-Host "  verified" -ForegroundColor Green
} else {
    Write-Host "  verification FAILED" -ForegroundColor Red
}

Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  git add .github/workflows/ci.yml"
Write-Host '  git commit -m "fix(ci): bump Node.js to 24.x for Angular 22"'
Write-Host "  git push"
Write-Host ""