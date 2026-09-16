#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$bi = "src/Modules/Bookings/Bookings.Infrastructure"
$csproj = "$bi/Bookings.Infrastructure.csproj"
$migDir = "$bi/Persistence/Migrations"

$env:BOOKING_CONNECTION = "Host=127.0.0.1;Port=5433;Database=flights_demo;Username=flights;Password=flights_dev_password"

Write-Host ""
Write-Host "=== Booking saga migration ==="
Write-Host ""

# 1. Check if migration already exists
$existing = Get-ChildItem -Path $migDir -Filter "*AddBookingSagaTables*" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Migration AddBookingSagaTables already exists" -ForegroundColor Yellow
} else {
    Write-Host "Generating migration AddBookingSagaTables..."
    dotnet ef migrations add AddBookingSagaTables `
        --project $csproj `
        --startup-project $csproj `
        --context BookingDbContext `
        --output-dir "Persistence/Migrations"
    if ($LASTEXITCODE -ne 0) { Write-Host "GENERATION FAILED" -ForegroundColor Red; exit 1 }
    Write-Host "  + generated"
}

# 2. Apply
Write-Host ""
Write-Host "Applying migration to flights_demo..."
dotnet ef database update `
    --project $csproj `
    --startup-project $csproj `
    --context BookingDbContext
if ($LASTEXITCODE -ne 0) { Write-Host "APPLY FAILED" -ForegroundColor Red; exit 1 }

# 3. Verify
Write-Host ""
Write-Host "=== Tables in booking schema ==="
docker exec flights-postgres psql -U flights -d flights_demo -c "SELECT table_name FROM information_schema.tables WHERE table_schema='booking' ORDER BY 1;"

Write-Host "=== Migration history ==="
docker exec flights-postgres psql -U flights -d flights_demo -c 'SELECT "MigrationId" FROM booking."__EFMigrationsHistory" ORDER BY 1;'

Write-Host ""
Write-Host "DONE." -ForegroundColor Green
Write-Host ""
Write-Host "Now run:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host ""