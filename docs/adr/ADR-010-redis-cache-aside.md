# ADR-010: Redis cache-aside with dual invalidation

## Status
Accepted

## Context
Reads dominate our workloads. Reference data (airports) changes rarely but is
read on every flight search. Flight details are read once per ticket addition
during the confirm saga. Serving these from Postgres on every call wastes
resources and adds latency.

We need a shared cache that:
- Can be used by both bounded contexts (FlightCatalog, Bookings).
- Does not couple the domain to any specific cache technology.
- Never breaks the application when Redis is unavailable.
- Keeps cached data fresh enough for our use cases.

## Decision

1. **Cache-aside** (not write-through, not write-behind).
   Reads go through the cache; misses fall back to the source and populate the
   cache. Writes update the database and then invalidate affected entries.

2. **Abstraction in `FlightsPlatform.Application.Abstractions`.**
   `ICacheService` is defined next to `Result<T>`; the implementation
   (`RedisCacheService`) lives in `FlightsPlatform.Infrastructure.Redis`.
   No module references Redis directly.

3. **Dual invalidation:**
   - **TTL** вЂ” every entry has a bounded lifetime (airports: 15 minutes;
     flights: 2 minutes).
   - **Explicit** вЂ” domain events remove affected keys. Airport sync triggers
     `RemoveByPrefixAsync("flight-catalog:airport:")`.

4. **Per-module key namespace.**
   Format: `<module>:<entity>:<id>`. Centralised in `CacheKeys` so the format
   is testable and consistent.

5. **Prefix removal uses SCAN, not KEYS.**
   `KEYS` blocks Redis; `SCAN` iterates in batches of 250.

6. **Redis is not on the critical path.**
   Any Redis failure is logged and treated as a cache miss. The application
   continues against Postgres.

7. **Only point reads are cached.**
   List reads (`GET /airports?page=...`) are not cached: they change with
   every sync, and cached pages would be stale for too long.

## Consequences

Positive:
- Reference data is served from memory on hits.
- Cache failures do not break correctness.
- Domain stays pure вЂ” no cache annotations, no `[Cacheable]` attributes.
- Modules share one cache instance without key collisions.

Negative:
- Eventual consistency window: up to 15 minutes for airports if explicit
  invalidation fails.
- Two moving parts to reason about (Postgres + Redis).
- An extra layer (decorator) around the read repository.

## Alternatives considered

- **`IDistributedCache` from Microsoft** вЂ” richer abstraction, but oriented
  towards key/value byte arrays; our typed `ICacheService` fits the codebase
  better and keeps module boundaries clean.

- **Write-through cache** вЂ” rejected: forces a cache write inside the
  transactional boundary, complicates failure handling, and risks storing
  data that was never committed.

- **Client-side in-memory cache** вЂ” rejected: each instance has its own
  copy; invalidation across instances is a distributed problem we do not
  want to solve yet.

- **No cache, optimize SQL** вЂ” that is part of Phase 5.2 (indexes and
  `EXPLAIN ANALYZE`). Both are needed.

## References
- SPEC-005
- ADR-002 (CQRS split)
- ADR-005 (Bookings bounded context)