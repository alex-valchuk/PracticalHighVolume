# Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         API Gateway / BFF                           │
│                    (ASP.NET Core, Minimal API, YARP)                │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  Flight       │  │  Booking      │  │  Pricing      │
│  Catalog      │  │  Service      │  │  Service      │
│  Service      │  │               │  │               │
│  (CQRS, Redis)│  │ (CQRS, Saga)  │  │ (CQRS, Redis) │
└───────┬───────┘  └───────┬───────┘  └───────┬───────┘
        │                  │                  │
        │    ┌─────────────┼──────────────────┤
        │    │             │                  │
        ▼    ▼             ▼                  ▼
┌────────────────────────────────────────────────────────┐
│              RabbitMQ / MassTransit                     │
│         (Event Bus: BookingCreated, FlightDelayed,      │
│          PaymentProcessed, BookingCancelled)            │
└────────────────────────┬───────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  Notification │  │  Analytics    │  │  Payment      │
│  Worker       │  │  Worker       │  │  Simulator    │
│  (Background) │  │  (Background) │  │  (Background) │
└───────────────┘  └───────────────┘  └───────────────┘

        ┌────────────────────────────────────────────┐
        │         Infrastructure Layer                │
        │  PostgreSQL (demo) │ Redis │ RabbitMQ       │
        │  MongoDB (audit)   │ Docker│ Kubernetes     │
        │  OpenTelemetry     │ Grafana│ Prometheus    │
        └────────────────────────────────────────────┘
```

# Actors

| Solution      | Reason |
| ------------- | ------------- |
| CQRS                    | Read (flight search) and write (booking) operations have different workloads and data models     |
| MediatR                 | Separation of commands and queries; pipeline behaviors for logging/validation     |
| Clean Architecture      | Domain is independent of infrastructure; easy to test     |
| MassTransit + RabbitMQ  | Asynchronous processing: notifications, analytics, and payments do not block the API |
| Redis                   | Caching popular flights; distributed locking during booking  |
| MongoDB                 | Event audit log (append-only, unstructured payloads) |
| Docker + K8s            | Environment reproducibility; worker scaling  |
| OpenTelemetry + Grafana | Observability: traces, metrics, and logs  |


# SQL Database

1. Go to https://edu.postgrespro.ru/
2. Download demo-big.zip (or demo-medium.zip or demo-small.zip)
3. Run Powershell and go to the folder with downloaded file
4. Execute *docker cp .\postgres-demo-big.zip flights-postgres:/tmp/*
5. Ensure to get *Successfully copied (X)MB (transferred (X)MB) to flights-postgres:/tmp/*
6. Execute *docker exec -i flights-postgres bash -c "unzip -p /tmp/postgres-demo-big.zip | psql -U flights -d postgres"*
7. Ensure to get a long list of successfull database creation commands log


# Powershell
1. Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
2. .\scaffold-phase-1-part2.ps1

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