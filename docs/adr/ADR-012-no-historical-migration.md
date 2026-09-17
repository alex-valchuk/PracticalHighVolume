# ADR-012: No historical data migration into the operational catalog

## Status
Accepted

## Context

The platform integrates with an external Postgres database
(`demo.bookings.*`) via an Anti-Corruption Layer. That database contains
real historical data from 2017: millions of flight rows, tickets, and
bookings. It is a training dataset published by Postgres Pro.

During the design of Phase 5 (performance tuning), the question came up
whether to sync this historical data into our own `flight_catalog.flights`
table. The motivation would have been to have a realistic data volume for
`EXPLAIN ANALYZE` and index tuning.

## Decision

**We do not migrate historical flights into the operational catalog.**

We only sync **reference data** (airports) from the external source. Flights
are created by our own commands (`ScheduleFlightCommand`) and by future
business flows. Historical data belongs to analytics, not to our operational
database.

## Rationale

1. **Operational database в‰  archive.**
   `flight_catalog.flights` holds flights that can be booked, delayed,
   cancelled, or queried by customers. Historical flights from 2017 cannot
   be booked, so they have no operational meaning.

2. **Zero business value.**
   No user asks "find me a flight SVO в†’ OVB in June 2017". If someone does,
   it is a reporting task, not a booking task.

3. **Different consistency models.**
   Historical flights are append-only and never change. Operational flights
   are mutable: status changes, delays, cancellations. Mixing append-only
   history with mutable operational state in one table complicates every
   write and query.

4. **Operational size matters.**
   An operational catalog should stay small and fast. Loading 2M historical
   rows to "have volume" slows every read for the sake of a benchmark that
   we can run elsewhere.

5. **It is ETL, not integration.**
   Historical data belongs in a data warehouse or an analytical store,
   loaded by an ETL / CDC pipeline. It is not the responsibility of the
   booking service.

## Consequences

Positive:
- Operational schema stays focused and small.
- No hidden coupling between our service and a legacy archive.
- No fake "realistic volume" that distorts index planning.
- Clear separation: operational store (ours) vs analytical store (not ours).

Negative:
- `EXPLAIN ANALYZE` on the operational catalog reflects its actual small
  size today. Index tuning based on this would be premature вЂ” and we
  explicitly avoid premature optimization.

## What we do instead

- **When we actually need volume for load testing**, we spin up an isolated
  test container with a seed script. It never mixes with production-like data.
- **When the operational table grows** through real usage, we measure
  query latency and add indexes based on **observed** need, not on guessed
  need.
- **When analytics needs historical data**, it reads directly from the
  external source through a dedicated pipeline, not through our operational
  catalog.

## Alternatives considered

- **Sync all historical flights into `flight_catalog.flights`.**
  Rejected: no business value, mixes consistency models, bloats the
  operational store.

- **Sync a rolling window (В±30 days) of historical flights.**
  Slightly better, but still creates a two-source problem: our own flights
  and foreign flights with different ownership. Rejected.

- **Create a separate schema `flight_catalog_archive` for historical data.**
  Better than mixing, but still a shared database with two very different
  workloads. Belongs to a data warehouse, not here. Rejected.

- **Do nothing (chosen).** Reference data (airports) is enough for the
  platform. Flights are owned by us. Analytics is somebody else's problem.

## References
- SPEC-005 (Redis caching and performance)
- ADR-004 (Integration via ACL and polling sync)
- ADR-003 (Own schema)