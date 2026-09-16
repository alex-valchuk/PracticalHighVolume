#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Fix: add proxyConfig to frontend/angular.json ==="
Write-Host ""

$root = (Get-Location).Path
$angularJsonPath = Join-Path $root "frontend/angular.json"

if (-not (Test-Path -LiteralPath $angularJsonPath)) {
    Write-Host "  angular.json not found at $angularJsonPath" -ForegroundColor Red
    exit 1
}

Write-Host ("  path: " + $angularJsonPath)

$aj = [System.IO.File]::ReadAllText($angularJsonPath)

if ($aj -match '"proxyConfig"') {
    Write-Host "  proxyConfig already present - nothing to do" -ForegroundColor Green
} else {
    # Find "serve" -> "options" block and insert proxyConfig right after "{"
    $pattern = '("serve"\s*:\s*\{[^}]*?"options"\s*:\s*\{)'
    $replacement = '$1' + "`r`n              `"proxyConfig`": `"proxy.conf.json`","

    $newAj = [regex]::Replace($aj, $pattern, $replacement, [System.Text.RegularExpressions.RegexOptions]::Singleline)

    if ($newAj -eq $aj) {
        Write-Host "  pattern not matched - will add manually" -ForegroundColor Yellow
        Write-Host "  Open frontend/angular.json and add to architect.serve.options:" -ForegroundColor Yellow
        Write-Host '    "proxyConfig": "proxy.conf.json",' -ForegroundColor Yellow
        exit 1
    }

    [System.IO.File]::WriteAllText($angularJsonPath, $newAj, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + added proxyConfig to frontend/angular.json" -ForegroundColor Green
}

# Verify
$verify = [System.IO.File]::ReadAllText($angularJsonPath)
if ($verify -match '"proxyConfig"') {
    Write-Host "  verified: proxyConfig is present" -ForegroundColor Green
} else {
    Write-Host "  verification FAILED" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Now build frontend to check everything is fine:" -ForegroundColor Yellow
Write-Host "  cd frontend"
Write-Host "  npm run build"
Write-Host "  cd .."
Write-Host ""
Write-Host "Then run backend + frontend:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  cd frontend; npm start"
Write-Host ""