# ADR-003: Own Schema for Flight Catalog

## Status
Accepted

## Context
The Postgres instance already contains the demo bookings database with a
bookings schema (airports, flights, tickets, etc.). We need to decide whether
to map our domain onto that schema or create our own.

## Decision
We create our own schema: flight_catalog. Our aggregates live there.
The bookings schema is treated as an external data source, integrated via
an anti-corruption layer in a later phase.

## Consequences
Positive:
- Domain is not polluted by foreign naming, types, or invariants.
- We own our schema: can evolve it independently.
- Clear separation of "our data" vs "external data".

Negative:
- Some duplication: airports, aircraft models may exist in both schemas.
- Need a sync mechanism (later phase) to keep reference data fresh.

## When to revisit
If we ever migrate onto an existing corporate schema, this decision is
revisited. For the current scope, isolation wins.