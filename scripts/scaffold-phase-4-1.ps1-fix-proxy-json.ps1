#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$root = (Get-Location).Path
$angularJsonPath = Join-Path $root "frontend\angular.json"

Write-Host ""
Write-Host "=== Fix v2: enable proxyConfig in angular.json ==="
Write-Host ("Path: " + $angularJsonPath)
Write-Host ""

if (-not (Test-Path -LiteralPath $angularJsonPath)) {
    Write-Host "angular.json not found" -ForegroundColor Red
    exit 1
}

$raw = [System.IO.File]::ReadAllText($angularJsonPath)
$json = $raw | ConvertFrom-Json

# Force project names to be an array, regardless of how many projects exist
$projectNames = @($json.projects.PSObject.Properties | ForEach-Object { $_.Name })
Write-Host ("Projects found: " + ($projectNames -join ", "))

if ($projectNames.Count -eq 0) {
    Write-Host "no projects in angular.json" -ForegroundColor Red
    exit 1
}

$projectName = $projectNames[0]
Write-Host ("Using project: " + $projectName)
Write-Host ""

# Navigate through the object safely
$proj = $json.projects.$projectName
if ($null -eq $proj) {
    Write-Host ("project '" + $projectName + "' not accessible") -ForegroundColor Red
    exit 1
}

$architect = $proj.architect
if ($null -eq $architect) {
    Write-Host "architect block not found" -ForegroundColor Red
    exit 1
}

$serve = $architect.serve
if ($null -eq $serve) {
    Write-Host "architect.serve not found" -ForegroundColor Red
    Write-Host "Available architect targets:" -ForegroundColor Yellow
    $architect.PSObject.Properties | ForEach-Object { Write-Host ("  - " + $_.Name) }
    exit 1
}

Write-Host "architect.serve found"
Write-Host ("Current builder: " + $serve.builder)

# Ensure options object exists
if ($null -eq $serve.options) {
    $serve | Add-Member -MemberType NoteProperty -Name "options" -Value ([PSCustomObject]@{}) -Force
    Write-Host "  + created options block"
}

# Set (or overwrite) proxyConfig
if ($serve.options.PSObject.Properties.Name -contains "proxyConfig") {
    $serve.options.proxyConfig = "proxy.conf.json"
    Write-Host "  ~ updated proxyConfig"
} else {
    $serve.options | Add-Member -MemberType NoteProperty -Name "proxyConfig" -Value "proxy.conf.json" -Force
    Write-Host "  + added proxyConfig"
}

# Save
$out = $json | ConvertTo-Json -Depth 100
[System.IO.File]::WriteAllText($angularJsonPath, $out, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + saved angular.json"

# Verify
$check = [System.IO.File]::ReadAllText($angularJsonPath)
if ($check -match '"proxyConfig"\s*:\s*"proxy\.conf\.json"') {
    Write-Host ""
    Write-Host "  VERIFIED: proxyConfig is present" -ForegroundColor Green
} else {
    Write-Host "  verification FAILED" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Now:" -ForegroundColor Yellow
Write-Host "  1. Ctrl+C in the npm start terminal"
Write-Host "  2. cd frontend"
Write-Host "  3. npm start"
Write-Host ""
Write-Host "Then open:" -ForegroundColor Yellow
Write-Host "  http://localhost:4200/api/health"
Write-Host "Expected: { ""status"": ""ok"", ... }"
Write-Host ""