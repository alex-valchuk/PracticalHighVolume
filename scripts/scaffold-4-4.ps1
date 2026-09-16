$root = (Get-Location).Path

function Save-Utf8 {
    param([string]$Path, [string]$Content)
    $full = Join-Path $root $Path
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path) -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Phase 4.4: ADR-009, CI, README ==="
Write-Host ""

# ===========================================================================
# 1. ADR-009
# ===========================================================================
$adr = @'
# ADR-009: Angular SPA alongside .NET API

## Status
Accepted

## Context
The platform exposes two bounded contexts (FlightCatalog, Bookings) via REST.
Manual testing through Scalar covers single requests but is clumsy for the
multi-step booking saga (create -> add ticket -> confirm). We need a
user-facing UI to:
1. Exercise end-to-end flows.
2. Demonstrate saga compensations visually.
3. Show a complete frontend + backend integration for portfolio purposes.

## Decision
Build a standalone Angular SPA in `frontend/` at the repository root.

### Key choices

1. **Framework: Angular (latest stable, standalone APIs)**.
   TypeScript-first, DI, RxJS, and CLI match backend concepts.
   Opinionated structure reduces decision fatigue.

2. **UI library: PrimeNG + PrimeFlex**.
   Data tables, dialogs, toasts, date pickers - all ready.
   Focus stays on architecture, not CSS.

3. **No NgModules; standalone components**.
   Modern Angular path. `provideRouter`, `provideHttpClient`,
   `providePrimeNG` in `app.config.ts`.

4. **Zoneless change detection**.
   `provideZonelessChangeDetection()`. Signals drive UI updates.

5. **Dev proxy, not CORS**.
   `proxy.conf.json` maps `/api` to `https://localhost:50943`.
   CORS policy "frontend" is enabled on the backend only for Development.

6. **Feature folder per bounded context**.
   `features/airports`, `features/flights`, `features/bookings`,
   `features/dashboard`. Symmetric with backend modules.

7. **No NgRx / Akita (yet)**.
   Services with RxJS `BehaviorSubject` and Angular `signal` cover our needs.
   Global state library would be premature.

8. **API types are hand-written**.
   `core/api/models/*.ts` mirror the backend DTOs.
   OpenAPI code generation deferred.

9. **Admin endpoints for demo**.
   `/admin/payment/simulate-failure` toggles a runtime flag that makes the
   next confirm trigger saga compensation. Visible only in Development.

### Layout

    frontend/
      src/app/
        core/
          api/          <- ApiService, error interceptor, models
          services/     <- ThemeService, HealthService
          layout/       <- Shell, Sidebar, Header
        shared/         <- (reserved)
        features/
          dashboard/
          airports/
          flights/
          bookings/

## Consequences

Positive:
- End-to-end flows are demonstrable in a browser.
- Saga compensations visible to a human observer.
- Portfolio shows frontend + backend integration.

Negative:
- Two toolchains (dotnet + npm) in one repository.
- Two CI jobs (backend and frontend).
- Slightly more setup for a new contributor.

## Alternatives considered
- **React / Vue**: less aligned with enterprise .NET shops.
- **Server-side Razor Pages**: simpler, but loses the SPA demonstration.
- **Blazor WASM**: interesting, but the goal was to show we can work with
  a mainstream frontend stack, not just .NET everywhere.

## References
- SPEC-004 (Angular SPA spec)
- ADR-001 (Modular monolith)
- ADR-005 (Bookings as a separate bounded context)
- ADR-006 (Saga orchestration)
'@
Save-Utf8 "docs/adr/ADR-009-angular-spa.md" $adr

# ===========================================================================
# 2. CI workflow
# ===========================================================================
$ci = @'
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  DOTNET_VERSION: '10.0.x'
  NODE_VERSION: '20.x'
  DOTNET_NOLOGO: 'true'
  DOTNET_CLI_TELEMETRY_OPTOUT: 'true'
  DOTNET_SKIP_FIRST_TIME_EXPERIENCE: 'true'

jobs:
  backend:
    name: Backend (build & test)
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup .NET
        uses: actions/setup-dotnet@v4
        with:
          dotnet-version: ${{ env.DOTNET_VERSION }}

      - name: Cache NuGet packages
        uses: actions/cache@v4
        with:
          path: ~/.nuget/packages
          key: ${{ runner.os }}-nuget-${{ hashFiles('**/*.csproj', '**/Directory.Build.props', '**/Directory.Packages.props') }}
          restore-keys: |
            ${{ runner.os }}-nuget-

      - name: Restore
        run: dotnet restore

      - name: Build
        run: dotnet build --no-restore --configuration Release

      - name: Test
        run: dotnet test --no-build --configuration Release --logger "trx;LogFileName=test-results.trx" --results-directory ./TestResults

      - name: Upload test results
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: backend-test-results
          path: ./TestResults
          retention-days: 7

  frontend:
    name: Frontend (build)
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: ${{ env.NODE_VERSION }}
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      - name: Install dependencies
        run: npm ci

      - name: Build
        run: npm run build -- --configuration production
'@
Save-Utf8 ".github/workflows/ci.yml" $ci

# ===========================================================================
# 3. README
# ===========================================================================
$readme = @'
# Flights Platform

[![CI](https://github.com/alex-valchuk/PracticalHighVolume/actions/workflows/ci.yml/badge.svg)](https://github.com/alex-valchuk/PracticalHighVolume/actions/workflows/ci.yml)

A **modular monolith** demonstrating Clean Architecture, CQRS, DDD, event-driven
saga orchestration, and a modern Angular SPA - on top of a real Postgres demo
database with millions of rows.

Built as a personal deep-dive into distributed-systems patterns for
architect-level engineering.

---

## What is inside

- **Two bounded contexts:** FlightCatalog (schedule, airports, flights) and
  Bookings (bookings, tickets, saga).
- **Clean Architecture** per module: Domain / Application / Infrastructure / Api.
- **CQRS** with separate read (Dapper) and write (EF Core) repositories.
- **DDD** - aggregates, value objects, domain events, invariants.
- **Integration with legacy data source** via Anti-Corruption Layer and
  background polling sync (Postgres, another schema).
- **Saga orchestration** for booking confirmation with compensations:
  reserve seats -> charge payment -> confirm; on failure, refund + release +
  expire.
- **Angular SPA** as the user-facing layer, with a live saga visualization
  and a demo toggle to trigger compensation.
- **EF Core Migrations** per module, isolated history tables.
- **FluentValidation**, **MediatR** pipeline behaviors, **Dapper** read models.
- **GitHub Actions CI** running backend build/tests and frontend build on
  every push and PR.

---

## Screenshots

> Coming soon: dashboard, airports, flights list, booking details with saga
> success, booking details with saga compensation. Will be added after the
> final UI polish.

---

## Architecture

    +-------------------------------------------+
    |       FlightsPlatform.Api (host)          |
    |  ASP.NET Core, Minimal API, Scalar UI,    |
    |  CORS (Development only), health, admin   |
    +-------------------------------------------+
                        |
          +-------------+-----------------+
          |                               |
    +-----v--------+              +-------v-------+
    | FlightCatalog|              |   Bookings    |
    |   module     |              |    module     |
    |              |              |               |
    | - Domain     |              | - Domain      |
    | - Application|   MediatR    | - Application |
    | - Infra      |<------------>| - Infra       |
    | - Api        |              | - Api         |
    +------+-------+              +-------+-------+
           |                              |
           |     flight_catalog schema    |     booking schema
           +---------------+--------------+
                           |
                    PostgreSQL (flights_demo)
                           |
                    PostgreSQL (demo, bookings.*)
                    <-- external source, read-only via ACL

    Frontend: Angular 22 SPA in `frontend/`, talks to the host via dev proxy.

---

## Tech stack

### Backend
- .NET 10, ASP.NET Core, Minimal API
- MediatR 12, FluentValidation 11
- EF Core 9 (write side), Dapper 2.1 (read side)
- PostgreSQL 16
- Scalar for OpenAPI UI
- xUnit, FluentAssertions, Moq

### Frontend
- Angular 22 (standalone components, zoneless)
- PrimeNG 22 + PrimeIcons
- TypeScript strict mode
- RxJS, signals
- Dev proxy for local development

### Infrastructure
- Docker Compose: PostgreSQL
- GitHub Actions: CI for backend and frontend

---

## Running locally

### Prerequisites

- .NET 10 SDK
- Node.js 20+ and npm
- Docker Desktop

### 1. Start PostgreSQL

    docker compose up -d

The database `flights_demo` contains our `flight_catalog` and `booking`
schemas. The external demo database `demo` (schema `bookings`) is loaded from
the Postgres Pro archive once.

### 2. Run the backend

    dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https

- API + Scalar UI: https://localhost:50943/scalar/v1
- Health: https://localhost:50943/health

### 3. Run the frontend

    cd frontend
    npm install
    npm start

- SPA: http://localhost:4200

The dev proxy maps `/api/*` to `https://localhost:50943/*` automatically.

### 4. Run tests

    dotnet test
    # or just the backend part
    dotnet test tests/FlightCatalog.UnitTests
    dotnet test tests/Bookings.UnitTests

---

## End-to-end walkthrough

1. **Airports** -> click **Sync from source**. Airports are imported from
   the external `bookings.airports` table via the Anti-Corruption Layer.
2. **Flights** -> **Create flight**. Copy the flight ID.
3. **Bookings** -> **Create booking**. Fill passenger.
4. **Booking details** -> **Add ticket**. Paste the flight ID.
5. **Confirm booking**. The saga runs:
   - verify flight, reserve seat, charge payment, confirm.
   - On success: status Confirmed, green saga panel.
6. **Demo compensation:** toggle "Demo: fail next payment" on the Bookings
   list, then create + confirm a new booking. The saga fails after charge,
   then compensates: refund + release seat + mark Expired. Red saga panel.

---

## Project structure

    src/
      BuildingBlocks/
        FlightsPlatform.SharedKernel/           Entity, ValueObject, AggregateRoot
        FlightsPlatform.Application.Abstractions/  Result<T>
      Modules/
        FlightCatalog/
          FlightCatalog.Domain/
          FlightCatalog.Application/
          FlightCatalog.Infrastructure/
          FlightCatalog.Api/
        Bookings/
          Bookings.Domain/
          Bookings.Application/
          Bookings.Infrastructure/
          Bookings.Api/
      Hosts/
        FlightsPlatform.Api/                    host, DI, endpoints, migrations

    tests/
      FlightCatalog.UnitTests/
      Bookings.UnitTests/

    frontend/
      src/app/
        core/                                   api, services, layout
        features/                               dashboard, airports, flights, bookings

    docs/
      adr/                                      Architecture Decision Records
      specs/                                    Spec-driven development docs

---

## Architecture Decision Records

- [ADR-001 Modular monolith](docs/adr/ADR-001-modular-monolith.md)
- [ADR-002 CQRS split](docs/adr/ADR-002-cqrs-split.md)
- [ADR-003 Own schema](docs/adr/ADR-003-own-schema.md)
- [ADR-004 Integration via ACL and polling sync](docs/adr/ADR-004-integration-acl-polling.md)
- [ADR-005 Bookings as a separate bounded context](docs/adr/ADR-005-bookings-bounded-context.md)
- [ADR-006 Saga orchestration](docs/adr/ADR-006-saga-orchestration.md)
- [ADR-009 Angular SPA alongside .NET API](docs/adr/ADR-009-angular-spa.md)

---

## Roadmap

- [x] Phase 1: Domain + Clean Architecture (FlightCatalog)
- [x] Phase 2: Integration with external source (bookings)
- [x] Phase 3: Bookings module + saga with compensations
- [x] Phase 4: Angular SPA
- [ ] Phase 5: Redis caching and performance
- [ ] Phase 6: Event-driven with RabbitMQ, Outbox
- [ ] Phase 7: Observability (OpenTelemetry, Prometheus, Grafana)
- [ ] Phase 8: Container + Kubernetes + .NET Aspire
- [ ] Phase 9: Final polish, demo scenarios

---

## License

MIT
'@
Save-Utf8 "README.md" $readme

# ===========================================================================
# 4. SPEC-004 status -> Accepted
# ===========================================================================
$specPath = Join-Path $root "docs/specs/phase-4-angular-spa.md"
if (Test-Path -LiteralPath $specPath) {
    $spec = [System.IO.File]::ReadAllText($specPath)
    $spec = $spec -replace '\| Status\s+\| Draft[^\|]*\|', '| Status          | Accepted                                 |'
    [System.IO.File]::WriteAllText($specPath, $spec, [System.Text.UTF8Encoding]::new($false))
    Write-Host "  + updated SPEC-004 status to Accepted" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Что сделано:" -ForegroundColor Yellow
Write-Host "  1. docs/adr/ADR-009-angular-spa.md"
Write-Host "  2. .github/workflows/ci.yml (backend + frontend jobs)"
Write-Host "  3. README.md (полная переработка)"
Write-Host "  4. SPEC-004 статус -> Accepted"
Write-Host ""
Write-Host "Next:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "docs: phase 4.4 - README, ADR-009, CI for frontend"'
Write-Host "  git push"
Write-Host ""
Write-Host "Then check GitHub Actions - both jobs should be green." -ForegroundColor Yellow
Write-Host ""