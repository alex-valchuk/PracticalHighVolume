#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-Info  { param($m) Write-Host $m -ForegroundColor Cyan }
function Write-Ok    { param($m) Write-Host ("  OK   " + $m) -ForegroundColor Green }
function Write-Skip  { param($m) Write-Host ("  skip " + $m) -ForegroundColor DarkGray }
function Write-Warn2 { param($m) Write-Host ("  WARN " + $m) -ForegroundColor Yellow }

Write-Host ""
Write-Info "=== Phase 1 cleanup ==="
Write-Host ("Working directory: " + (Get-Location).Path)
Write-Host ""

$root = (Get-Location).Path

# ---------------------------------------------------------------------------
# 1. Remove template Program.cs / launchSettings.json from module projects
# ---------------------------------------------------------------------------
Write-Info "=== 1. Removing template files from module projects ==="

$moduleProjects = @(
    "src/Modules/FlightCatalog/FlightCatalog.Api",
    "src/Modules/FlightCatalog/FlightCatalog.Application",
    "src/Modules/FlightCatalog/FlightCatalog.Domain",
    "src/Modules/FlightCatalog/FlightCatalog.Infrastructure"
)

foreach ($proj in $moduleProjects) {
    $programPath = Join-Path $root ($proj + "/Program.cs")
    if (Test-Path -LiteralPath $programPath) {
        Remove-Item -LiteralPath $programPath -Force
        Write-Ok ("deleted " + $proj + "/Program.cs")
    } else {
        Write-Skip ($proj + "/Program.cs (not present)")
    }

    $launchPath = Join-Path $root ($proj + "/Properties/launchSettings.json")
    if (Test-Path -LiteralPath $launchPath) {
        Remove-Item -LiteralPath $launchPath -Force
        Write-Ok ("deleted " + $proj + "/Properties/launchSettings.json")
    } else {
        Write-Skip ($proj + "/Properties/launchSettings.json (not present)")
    }
}

# ---------------------------------------------------------------------------
# 2. Remove template Controller / WeatherForecast leftovers from module projects
# ---------------------------------------------------------------------------
Write-Info ""
Write-Info "=== 2. Removing template controllers/weather stuff from modules ==="

$possibleTemplates = @(
    "src/Modules/FlightCatalog/FlightCatalog.Api/Controllers/WeatherForecastController.cs",
    "src/Modules/FlightCatalog/FlightCatalog.Api/WeatherForecast.cs",
    "src/Modules/FlightCatalog/FlightCatalog.Application/Class1.cs",
    "src/Modules/FlightCatalog/FlightCatalog.Domain/Class1.cs",
    "src/Modules/FlightCatalog/FlightCatalog.Infrastructure/Class1.cs"
)

foreach ($f in $possibleTemplates) {
    $full = Join-Path $root $f
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Force
        Write-Ok ("deleted " + $f)
    }
}

# Try to remove empty Controllers folders
$controllersDirs = @(
    "src/Modules/FlightCatalog/FlightCatalog.Api/Controllers"
)
foreach ($d in $controllersDirs) {
    $full = Join-Path $root $d
    if (Test-Path -LiteralPath $full) {
        $files = Get-ChildItem -LiteralPath $full -Recurse -File
        if ($files.Count -eq 0) {
            Remove-Item -LiteralPath $full -Recurse -Force
            Write-Ok ("deleted empty " + $d)
        } else {
            Write-Skip ($d + " (not empty, leaving)")
        }
    }
}

# ---------------------------------------------------------------------------
# 3. Rewrite FlightCatalog.Api.csproj as a library
# ---------------------------------------------------------------------------
Write-Info ""
Write-Info "=== 3. Rewriting FlightCatalog.Api.csproj ==="

$apiCsprojPath = Join-Path $root "src/Modules/FlightCatalog/FlightCatalog.Api/FlightCatalog.Api.csproj"
$apiCsprojContent = @'
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <RootNamespace>FlightCatalog.Api</RootNamespace>
  </PropertyGroup>
  <ItemGroup>
    <FrameworkReference Include="Microsoft.AspNetCore.App" />
  </ItemGroup>
  <ItemGroup>
    <ProjectReference Include="..\FlightCatalog.Application\FlightCatalog.Application.csproj" />
  </ItemGroup>
</Project>
'@
[System.IO.File]::WriteAllText($apiCsprojPath, $apiCsprojContent, [System.Text.UTF8Encoding]::new($false))
Write-Ok "FlightCatalog.Api.csproj rewritten (Microsoft.NET.Sdk library)"

# ---------------------------------------------------------------------------
# 4. Remove Aspire/ServiceDefaults leftovers
# ---------------------------------------------------------------------------
Write-Info ""
Write-Info "=== 4. Removing Aspire / ServiceDefaults leftovers ==="

# Delete ServiceDefaults project folder if exists
$serviceDefaultsDir = Join-Path $root "src/Hosts/ServiceDefaults"
if (Test-Path -LiteralPath $serviceDefaultsDir) {
    Remove-Item -LiteralPath $serviceDefaultsDir -Recurse -Force
    Write-Ok "deleted src/Hosts/ServiceDefaults"
} else {
    Write-Skip "ServiceDefaults folder (not present)"
}

# Find any csproj referencing ServiceDefaults and remove the reference
$allCsproj = Get-ChildItem -Path $root -Filter "*.csproj" -Recurse -File
foreach ($csproj in $allCsproj) {
    $content = [System.IO.File]::ReadAllText($csproj.FullName)
    $original = $content

    # Remove ProjectReference to ServiceDefaults
    $content = [regex]::Replace(
        $content,
        '\s*<ProjectReference[^>]*ServiceDefaults[^>]*/>',
        ''
    )

    # Remove common Aspire package references
    $aspirePatterns = @(
        'Microsoft\.Extensions\.ServiceDiscovery',
        'Microsoft\.Extensions\.Http\.Resilience',
        'Microsoft\.Extensions\.ServiceDiscovery\.Yarp',
        'Aspire\.',
        'Microsoft\.Extensions\.Diagnostics\.HealthChecks'
    )
    foreach ($pattern in $aspirePatterns) {
        $content = [regex]::Replace(
            $content,
            ('\s*<PackageReference[^>]*Include="' + $pattern + '[^"]*"[^>]*/>'),
            ''
        )
    }

    if ($content -ne $original) {
        [System.IO.File]::WriteAllText($csproj.FullName, $content, [System.Text.UTF8Encoding]::new($false))
        Write-Ok ("cleaned " + $csproj.FullName.Replace($root, "."))
    }
}

# ---------------------------------------------------------------------------
# 5. Clean .slnx / .sln references to removed projects
# ---------------------------------------------------------------------------
Write-Info ""
Write-Info "=== 5. Cleaning solution file references ==="

$slnx = Get-ChildItem -Path $root -Filter "*.slnx" -File | Select-Object -First 1
$sln = Get-ChildItem -Path $root -Filter "*.sln" -File | Select-Object -First 1

if ($slnx) {
    Write-Ok ("using solution: " + $slnx.Name + " (new format, VS will handle)")
    # .slnx is XML-ish; we let dotnet sln remove handle it
    # Try to remove ServiceDefaults project from solution if still referenced
    $projToRemove = Join-Path $root "src/Hosts/ServiceDefaults/ServiceDefaults.csproj"
    if (-not (Test-Path -LiteralPath $projToRemove)) {
        # attempt to remove by name pattern
        try {
            dotnet sln $slnx.FullName remove "src/Hosts/ServiceDefaults/ServiceDefaults.csproj" 2>$null | Out-Null
            Write-Ok "attempted to remove ServiceDefaults from .slnx"
        } catch {
            Write-Skip "could not auto-remove ServiceDefaults from .slnx (already gone or not referenced)"
        }
    }
} elseif ($sln) {
    Write-Ok ("using solution: " + $sln.Name)
    try {
        dotnet sln $sln.FullName remove "src/Hosts/ServiceDefaults/ServiceDefaults.csproj" 2>$null | Out-Null
        Write-Ok "attempted to remove ServiceDefaults from .sln"
    } catch {
        Write-Skip "could not auto-remove ServiceDefaults from .sln"
    }
} else {
    Write-Warn2 "no .sln/.slnx found in root"
}

# ---------------------------------------------------------------------------
# 6. Clean bin/obj and rebuild
# ---------------------------------------------------------------------------
Write-Info ""
Write-Info "=== 6. Cleaning bin/obj ==="

$binObjDirs = Get-ChildItem -Path $root -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue
foreach ($dir in $binObjDirs) {
    try {
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Skip ("could not delete " + $dir.FullName)
    }
}
Write-Ok ("removed " + $binObjDirs.Count + " bin/obj directories")

Write-Info ""
Write-Info "=== 7. dotnet restore + build ==="
dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "BUILD SUCCEEDED" -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Yellow
    Write-Host "  git status"
    Write-Host "  git add ."
    Write-Host '  git commit -m "Cleanup: FlightCatalog.Api as library, no Aspire"'
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "BUILD FAILED - see errors above" -ForegroundColor Red
    Write-Host "Send the first error lines back for diagnosis." -ForegroundColor Red
    exit 1
}