$root = (Get-Location).Path
$readmePath = Join-Path $root "README.md"

$content = @'
# Flights Platform

[![CI](https://github.com/alex-valchuk/PracticalHighVolume/actions/workflows/ci.yml/badge.svg)](https://github.com/alex-valchuk/PracticalHighVolume/actions/workflows/ci.yml)
[![.NET](https://img.shields.io/badge/.NET-10-512BD4?logo=dotnet&logoColor=white)](https://dotnet.microsoft.com/)
[![Angular](https://img.shields.io/badge/Angular-22-DD0031?logo=angular&logoColor=white)](https://angular.dev/)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-4169E1?logo=postgresql&logoColor=white)](https://www.postgresql.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

> A **modular monolith** demonstrating Clean Architecture, CQRS, DDD,
> saga orchestration with compensations, and a modern Angular SPA —
> built on top of a real Postgres demo database with millions of rows.

---

## Table of Contents

- [About](#about)
- [Highlights](#highlights)
- [Architecture](#architecture)
  - [System overview](#system-overview)
  - [Backend: modular monolith](#backend-modular-monolith)
  - [Frontend: Angular SPA](#frontend-angular-spa)
  - [Target architecture (roadmap)](#target-architecture-roadmap)
- [Screenshots](#screenshots)
- [Tech stack](#tech-stack)
- [Getting started](#getting-started)
- [End-to-end walkthrough](#end-to-end-walkthrough)
- [Project structure](#project-structure)
- [Architecture Decision Records](#architecture-decision-records)
- [Roadmap](#roadmap)
- [License](#license)

---

## About

Flights Platform is a personal deep-dive into the patterns that separate
a senior engineer from an architect. It shows, in runnable code, how to:

- Keep a domain pure while integrating with a legacy database.
- Split a system into bounded contexts that can be extracted into services.
- Coordinate a multi-step business process across modules with a **saga**,
  including **compensating transactions** when things fail.
- Expose the whole thing to a modern frontend that makes the saga visible.

The domain is airline booking. The external data source is the
[Postgres Pro demo database](https://edu.postgrespro.ru/) — a real dataset
with airports, flights, and tickets. Everything is built, tested, and shipped
through CI.

---

## Highlights

- **Two bounded contexts** — `FlightCatalog` (schedule, airports, flights)
  and `Bookings` (bookings, tickets, saga).
- **Clean Architecture** per module: Domain / Application / Infrastructure / Api.
- **CQRS with split read/write** — Dapper for reads, EF Core for writes.
- **DDD** — aggregates, value objects, domain events, invariants enforced in code.
- **Anti-Corruption Layer** — integration with an external Postgres schema
  without polluting the domain.
- **Saga orchestration** — booking confirmation with compensations
  (reserve seat → charge payment → confirm; on failure: refund + release + expire).
- **Angular SPA** — standalone components, zoneless change detection,
  live saga visualization, and a demo toggle to trigger compensation.
- **EF Core Migrations** per module with isolated history tables.
- **CI on GitHub Actions** — parallel backend (build + test) and frontend (build) jobs.

---

## Architecture

### System overview

End-to-end picture: browser, host application, modules, and data stores.

```mermaid
flowchart TB
    subgraph Browser["Browser"]
        SPA["Angular 22 SPA<br/>standalone components, zoneless"]
    end

    subgraph Host["FlightsPlatform.Api — ASP.NET Core 10 host"]
        direction TB

        subgraph FC["FlightCatalog module"]
            FCapi["Api<br/>Minimal API endpoints"]
            FCapp["Application<br/>MediatR · CQRS"]
            FCdom["Domain<br/>aggregates · VOs · events"]
            FCinf["Infrastructure<br/>EF Core · Dapper"]
        end

        subgraph BK["Bookings module"]
            BKapi["Api<br/>Minimal API endpoints"]
            BKapp["Application<br/>MediatR · CQRS · saga"]
            BKdom["Domain<br/>aggregates · saga state"]
            BKinf["Infrastructure<br/>EF Core · Dapper"]
        end

        FCapp <-->|MediatR| BKapp
    end

    subgraph DB["PostgreSQL 16"]
        OwnFC[("flight_catalog<br/>our schema")]
        OwnBK[("booking<br/>our schema")]
        Ext[("demo.bookings.*<br/>external · read-only")]
    end

    SPA -->|"HTTP /api (dev proxy)"| Host
    FCinf --> OwnFC
    BKinf --> OwnBK
    FCinf -.->|"ACL + polling sync"| Ext