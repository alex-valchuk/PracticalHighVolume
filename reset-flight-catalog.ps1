#Requires -Version 5.1
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "=== Reset FlightCatalog: regenerate migration, recreate schema ==="
Write-Host ""

$fcInfra = "src/Modules/FlightCatalog/FlightCatalog.Infrastructure"
$migDir  = "$fcInfra/Persistence/Migrations"
$csproj  = "$fcInfra/FlightCatalog.Infrastructure.csproj"

# 1. Delete old migrations
if (Test-Path -LiteralPath $migDir) {
    Remove-Item -LiteralPath $migDir -Recurse -Force
    Write-Host "  + deleted old FlightCatalog migrations"
}

# 2. Drop schema flight_catalog entirely
Write-Host ""
Write-Host "=== Drop schema flight_catalog ==="
docker exec flights-postgres psql -U flights -d flights_demo -c "DROP SCHEMA IF EXISTS flight_catalog CASCADE;"
if ($LASTEXITCODE -ne 0) { Write-Host "Failed to drop schema" -ForegroundColor Red; exit 1 }
Write-Host "  + dropped"

# 3. Drop the stale public.__EFMigrationsHistory if it exists
$hasPublicHistory = docker exec flights-postgres psql -U flights -d flights_demo -tAc "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='__EFMigrationsHistory';"
if ($null -ne $hasPublicHistory -and ($hasPublicHistory | Out-String).Trim() -eq "1") {
    docker exec flights-postgres psql -U flights -d flights_demo -c 'DROP TABLE public."__EFMigrationsHistory";'
    Write-Host "  + dropped stale public.__EFMigrationsHistory"
}

# 4. Clean + build
Write-Host ""
Write-Host "=== Clean + build ==="
Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host "BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + BUILD SUCCEEDED"

# 5. Generate new FlightCatalog migration
Write-Host ""
Write-Host "=== Generate FlightCatalog migration ==="
$env:FLIGHTS_CATALOG_CONNECTION = "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password"

dotnet ef migrations add InitialCreate `
    --project $csproj `
    --startup-project $csproj `
    --context FlightCatalogDbContext `
    --output-dir "Persistence/Migrations"

if ($LASTEXITCODE -ne 0) { Write-Host "MIGRATION GENERATION FAILED" -ForegroundColor Red; exit 1 }
Write-Host "  + generated"

# 6. Apply
Write-Host ""
Write-Host "=== Apply FlightCatalog migration ==="
dotnet ef database update `
    --project $csproj `
    --startup-project $csproj `
    --context FlightCatalogDbContext

if ($LASTEXITCODE -ne 0) { Write-Host "MIGRATION APPLY FAILED" -ForegroundColor Red; exit 1 }
Write-Host "  + applied"

# 7. Final state
Write-Host ""
Write-Host "=== Final state ==="
Write-Host ""
Write-Host "Schemas:"
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name IN ('public','flight_catalog','booking') ORDER BY 1;"

Write-Host "flight_catalog tables:"
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT table_name FROM information_schema.tables WHERE table_schema='flight_catalog' ORDER BY 1;"

Write-Host "flight_catalog history:"
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT ""MigrationId"" FROM flight_catalog.""__EFMigrationsHistory"" ORDER BY 1;"

Write-Host "booking history:"
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT ""MigrationId"" FROM booking.""__EFMigrationsHistory"" ORDER BY 1;"

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host ""
Write-Host "  On startup:"
Write-Host "   - FlightCatalog migrates into flight_catalog schema"
Write-Host "   - Bookings migrates into booking schema"
Write-Host "   - AirportSyncBackgroundService syncs airports from bookings.airports"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "fix(flight-catalog): regenerate migration with own history table"'
Write-Host "  git push"
Write-Host ""