# Switch to the Kubernetes (kind) environment.
# - stops docker-compose
# - builds images
# - loads into kind
# - upgrades or installs the Helm release
# - waits for pods to become Ready
#
# Requirements:
# - kind, kubectl, helm, docker in PATH
# - kind cluster already created (see docs/environments.md, first-time setup)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$clusterName = "flights"
$namespace   = "flights-platform"
$releaseName = "flights"

function Invoke-Cmd {
    param(
        [Parameter(Mandatory=$true)] [string] $Command,
        [switch] $IgnoreErrors
    )
    $output = cmd /c "$Command 2>&1"
    $code = $LASTEXITCODE
    if ($code -ne 0 -and -not $IgnoreErrors) {
        Write-Host "   command failed: $Command" -ForegroundColor Red
        Write-Host "   output:" -ForegroundColor Red
        $output | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
        exit 1
    }
    return $output
}

Write-Host ""
Write-Host "=== Kubernetes environment ==="
Write-Host ""

# 1. stop docker-compose
Write-Host "1. Stopping local infrastructure..."
Invoke-Cmd "docker compose down" -IgnoreErrors | Out-Null
Write-Host "   done"

# 2. cluster exists?
Write-Host ""
Write-Host "2. Checking kind cluster..."
$clusters = Invoke-Cmd "kind get clusters"
if ($clusters -notcontains $clusterName) {
    Write-Host "   cluster '$clusterName' not found." -ForegroundColor Red
    Write-Host "   Create it first (see docs/environments.md, first-time setup)."
    exit 1
}
Write-Host "   done"
Invoke-Cmd "kubectl config use-context kind-$clusterName" -IgnoreErrors | Out-Null

# 3. build and load images
Write-Host ""
Write-Host "3. Building images..."

$images = @(
    @{ Name = "flights-api";                 Dockerfile = "src/Hosts/FlightsPlatform.Api/Dockerfile" },
    @{ Name = "flights-notification-worker"; Dockerfile = "src/Workers/FlightsPlatform.NotificationWorker/Dockerfile" },
    @{ Name = "flights-analytics-worker";    Dockerfile = "src/Workers/FlightsPlatform.AnalyticsWorker/Dockerfile" }
)

foreach ($img in $images) {
    Write-Host "   - $($img.Name)"

    # Build
    $buildOut = Invoke-Cmd "docker build -t $($img.Name):latest -f $($img.Dockerfile) ."
    # (exit != 0 handled inside Invoke-Cmd)

    # Load into kind. kind writes progress to stderr; treat any output
    # as informational and rely on exit code only.
    Write-Host "     loading into kind..."
    $loadOut = cmd /c "kind load docker-image $($img.Name):latest --name $clusterName 2>&1"
    $loadCode = $LASTEXITCODE

    if ($loadCode -ne 0) {
        Write-Host "     kind load returned exit code $loadCode" -ForegroundColor Yellow
        Write-Host "     output:"
        $loadOut | ForEach-Object { Write-Host "       $_" -ForegroundColor Yellow }

        # Even when kind reports a non-zero exit code (it prints progress to
        # stderr), the image may have loaded fine. Verify by querying the node.
        $inNode = cmd /c "docker exec $clusterName-control-plane crictl images -q docker.io/library/$($img.Name):latest 2>&1"
        if ($inNode) {
            Write-Host "     image is present in the node - continuing" -ForegroundColor Green
        } else {
            Write-Host "     image is NOT present in the node - aborting" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "     loaded"
    }
}

Write-Host "   done"

# 4. helm release
Write-Host ""
Write-Host "4. Deploying Helm release..."
$existingJson = cmd /c "helm list -n $namespace --filter $releaseName -o json 2>&1"
$isInstalled = $false
try {
    $parsed = $existingJson | ConvertFrom-Json -ErrorAction SilentlyContinue
    if ($parsed -and @($parsed).Count -gt 0) { $isInstalled = $true }
} catch {}

if ($isInstalled) {
    Invoke-Cmd "helm upgrade $releaseName ./chart -f ./chart/values-dev.yaml -n $namespace --wait --timeout 8m"
} else {
    Invoke-Cmd "helm install $releaseName ./chart -f ./chart/values-dev.yaml -n $namespace --wait --timeout 8m --create-namespace"
}
Write-Host "   done"

# 5. pods
Write-Host ""
Write-Host "5. Pods:"
$podsOut = cmd /c "kubectl get pods -n $namespace 2>&1"
$podsOut | ForEach-Object { Write-Host "   $_" }

Write-Host ""
Write-Host "=== Ready ===" -ForegroundColor Green
Write-Host ""
Write-Host "Next step:" -ForegroundColor Yellow
Write-Host "  cd frontend; npm run dev:k8s"
Write-Host ""
Write-Host "URLs:" -ForegroundColor Cyan
Write-Host "  SPA        http://localhost:4200"
Write-Host "  API        http://api.flights.local/scalar/v1"
Write-Host "  Jaeger     http://jaeger.flights.local"
Write-Host "  Prometheus http://prometheus.flights.local"
Write-Host "  Grafana    http://grafana.flights.local"
Write-Host "  RabbitMQ   http://rabbit.flights.local"
Write-Host ""