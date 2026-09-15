# ADR-004: Integration with external source via ACL and polling sync

## Status
Accepted

## Context
The platform must integrate with an external legacy database (Postgres `demo`
with schema `bookings`) that we do not own. We need reference data (airports)
from that system, but we must not couple our domain to its schema, naming,
or lifecycle. Cross-database joins are not possible in Postgres.

## Decision
1. Keep our own database (`flights_demo`) and schema (`flight_catalog`).
2. Integrate via an Anti-Corruption Layer (ACL):
   - `IBookingsSourceReader` lives in the Application layer (contract);
   - its implementation `BookingsSourceReader` lives in Infrastructure
     and is `internal`;
   - a separate connection string `BookingsSource` is used, read-only,
     with `ApplicationName=FlightsPlatform.Sync`.
3. Synchronize reference data (airports) via a background polling service
   (`AirportSyncBackgroundService`), with configurable interval and startup
   behavior.
4. The domain never references external column names or schemas.

## Consequences
Positive:
- Domain is isolated from the external system.
- Renaming a column in the source only requires changes in ACL.
- We can later swap the source (Kafka topic, REST API) without touching
  the domain.

Negative:
- Eventual consistency: our copy of airports may lag behind the source.
- Polling overhead (acceptable: reference data changes rarely).

## Alternatives considered
- **Direct cross-database join** - not possible in Postgres.
- **Postgres FDW (Foreign Data Wrapper)** - works, but adds infrastructure
  complexity and couples us to the source schema anyway.
- **CDC (Debezium + Kafka)** - correct for high-churn data; overkill for
  airports that change a few times a year. Planned for phase 5.