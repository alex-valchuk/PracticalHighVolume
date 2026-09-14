# ADR-002: CQRS with Split Read/Write Repositories

## Status
Accepted

## Context
Flight Catalog workloads are asymmetric: reads dominate (search, lookup),
writes are rare (schedule, delay, cancel). EF Core is great for writes
(change tracking, invariants) but slow for complex read queries.

## Decision
We split repositories at the contract level:
- IFlightRepository (write) - used by command handlers, backed by EF Core.
- IFlightReadRepository (read) - used by query handlers, backed by Dapper.

Both currently point to the same Postgres database and the same table
flight_catalog.flights.

## Consequences
Positive:
- Read side is fast and predictable (raw SQL, DTOs, no change tracking).
- Write side keeps rich domain model and invariants.
- Later we can point the read side at a read-replica or Redis cache
  without touching the domain.

Negative:
- Two persistence technologies in one module.
- Risk of schema drift between EF Core model and raw SQL - mitigated by
  integration tests.

## When to revisit
When read load grows, we move the read side to a read-replica. If read
throughput becomes bottleneck, we add Redis caching on top of the read
repository.