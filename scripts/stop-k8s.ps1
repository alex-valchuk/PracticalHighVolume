# Stop the Kubernetes environment.
# Removes the Helm release and asks whether to delete the kind cluster.

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$clusterName = "flights"
$namespace   = "flights-platform"
$releaseName = "flights"

Write-Host ""
Write-Host "Stopping Kubernetes environment..." -ForegroundColor Yellow
Write-Host ""

# 1. helm uninstall
$existingJson = cmd /c "helm list -n $namespace --filter $releaseName -o json 2>&1"
$isInstalled = $false
try {
    $existing = $existingJson | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($existing -and $existing.Count -gt 0) { $isInstalled = $true }
} catch {}

if ($isInstalled) {
    Write-Host "1. Removing Helm release..."
    cmd /c "helm uninstall $releaseName -n $namespace 2>&1" | Out-Null
    Write-Host "   done"
} else {
    Write-Host "1. No Helm release found."
}

# 2. ask about cluster deletion
Write-Host ""
$answer = Read-Host "2. Delete the kind cluster too? (y/N)"
if ($answer -eq "y") {
    Write-Host "   Deleting cluster '$clusterName'..."
    cmd /c "kind delete cluster --name $clusterName 2>&1" | Out-Null
    Write-Host "   done"
} else {
    Write-Host "   Cluster kept. Start it again with scripts\dev-k8s.ps1"
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host ""