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

A modular monolith demonstrating Clean Architecture, CQRS, DDD,
and distributed-systems patterns on top of a real Postgres demo database.

## Architecture

### Bounded contexts
- **Flight Catalog** (implemented) - schedule, flights, aircraft, airports.
- **Booking** (planned) - reservations, tickets, passengers, cancellations.
- **Pricing** (planned) - fares, discounts, dynamic pricing.
- **Notification** (planned) - email, SMS, push, event-driven.

Modules communicate in-process via MediatR and (later) via RabbitMQ events.

### Layering
Each module has the same shape:

    Module/
      Module.Domain            (no external deps)
      Module.Application       (MediatR commands/queries, FluentValidation,
                                Dapper-based read abstractions)
      Module.Infrastructure    (EF Core + Dapper, repositories)
      Module.Api               (Minimal API endpoints exposed to the host)

The host (FlightsPlatform.Api) only wires modules together. It has no
business logic.

## Tech stack
- .NET 10, ASP.NET Core
- MediatR 12, FluentValidation 11
- EF Core 9 (write side) + Dapper 2.1 (read side)
- PostgreSQL 16 (demo bookings database)
- Scalar for OpenAPI UI

## Running locally

1. Start Postgres:

       docker compose up -d

2. Restore packages:

       dotnet restore

3. Run the API:

       dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https

4. Open Scalar UI:

       https://localhost:50943/scalar/v1

## Tests

    dotnet test

## Architecture Decision Records
See docs/adr/.