# AGENTS.md — Flights Platform (repo guide for coding agents)

This file is for agentic coding tools working in this repository. Keep instructions short, accurate, and aligned with the current codebase.

## Project summary
- Domain: airline booking showcase evolving from a modular monolith to microservices.
- Backend: .NET 10 (ASP.NET Core Minimal API), modular monolith (`src/Modules/*`, `src/Hosts/FlightsPlatform.Api`).
- Frontend: Angular 22 SPA in `frontend/` (standalone, zoneless).
- Data: PostgreSQL 16 (local via Docker Compose). External demo schema `bookings.*` is read-only via ACL + polling sync.
- Docs: `README.md`, `docs/` (ADRs in `docs/adr/`, specs in `docs/specs/`, env guides in `docs/environments.md`, `docs/quickstart.md`).

## Key paths
- Solution: `FlightsPlatform.slnx`
- Backend host: `src/Hosts/FlightsPlatform.Api`
- Modules: `src/Modules/FlightCatalog/*`, `src/Modules/Bookings/*`
- Building blocks: `src/BuildingBlocks/*`
- Tests: `tests/FlightCatalog.UnitTests`, `tests/Bookings.UnitTests`, `tests/FlightsPlatform.IntegrationTests`
- Frontend: `frontend/`
- Local infra: `docker-compose.yml`
- CI: `.github/workflows/ci.yml`, `.github/workflows/helm-lint.yml`

## Environment and commands (current, cross-platform preferred)
Do not introduce or document PowerShell-centric workflows in new docs. Prefer shell commands that work in CI/Linux and are easy to translate.

### Prerequisites
- .NET 10 SDK
- Node.js 22.22.3+ or 24.x + npm
- Docker Desktop

### Infrastructure (PostgreSQL, RabbitMQ, observability stack as defined in compose)
```bash
docker compose up -d
```
Stop:
```bash
docker compose down
```

### Backend (API)
Run API (HTTPS profile):
```bash
dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https
```
- Scalar/OpenAPI: `https://localhost:50943/scalar/v1`
- Health: `https://localhost:50943/health`

Migrations are applied automatically on startup (per module).

### Frontend (Angular)
```bash
cd frontend
npm install
npm start
```
- SPA: `http://localhost:4200`
- Dev proxy forwards `/api/*` to backend per `frontend/proxy.conf.js` / env-driven target. See `frontend/README.md`.

### Tests (backend)
All tests:
```bash
dotnet test
```
Single test project:
```bash
dotnet test tests/FlightCatalog.UnitTests
dotnet test tests/Bookings.UnitTests
dotnet test tests/FlightsPlatform.IntegrationTests
```
Run a single test (example patterns):
```bash
dotnet test tests/FlightCatalog.UnitTests --filter "FullyQualifiedName~SomeTestName"
dotnet test tests/FlightCatalog.UnitTests --filter "Name~SomeTestName"
```
CI note: integration tests run separately in CI (`FlightsPlatform.IntegrationTests`); unit filter excludes integration by name in the backend-unit job.

### Frontend checks
```bash
cd frontend
npm run build
npm test
```

## Architecture rules (must follow)
- Modular monolith boundaries: each module has `Domain / Application / Infrastructure / Api`.
- Dependencies point inward: Domain has no dependency on EF Core/ASP.NET/Infrastructure.
- No cross-module Domain references. Cross-module calls go through interfaces in the caller’s `Application` layer, implemented in that caller’s `Infrastructure`.
- CQRS: reads via Dapper, writes via EF Core (per existing patterns).
- Keep domain pure; integrate external `bookings.*` only via ACL/polling patterns already in place.
- Prefer minimal API endpoint mapping patterns used in `*.Api` modules and composition in the host.

## Change discipline
- Before large structural changes, consult ADRs in `docs/adr/` and follow them.
- If introducing a significant architectural decision, add/update an ADR under `docs/adr/` before coding.
- Keep changes consistent with existing naming, folder layout, and style.
- Do not add PowerShell scripts or PowerShell-first instructions. If you touch docs that mention PowerShell, replace with cross-platform alternatives (bash/fallback notes only when unavoidable).

## Repo hygiene notes (agentic dev)
- `AGENTS.md`, `.opencode/` (rules/instructions/skills/tasks) are part of the repo scaffolding for agent workflows.
- Do not introduce new PowerShell (`.ps1`) scripts. Existing convenience scripts under `scripts/*.ps1` may remain; document them clearly when relevant.
- Prefer cross-platform commands in docs (bash-friendly) while acknowledging Windows helper scripts where they exist.

## Useful references
- `README.md` (full overview, walkthrough, roadmap)
- `docs/environments.md`, `docs/quickstart.md`
- `frontend/README.md`
- `.github/workflows/ci.yml`