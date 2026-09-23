# SPEC-005: Redis Caching and Performance

| Field      | Value                                        |
| ---------- | -------------------------------------------- |
| Spec ID    | SPEC-005                                     |
| Status     | Accepted (5.2.2 cancelled)              |
| Phase      | 5                                            |
| Created    | 2026-09-16                                   |
| Depends on | SPEC-004 (Angular SPA)                       |
| Blocks     | SPEC-006 (Event-driven / RabbitMQ)           |

---

## 1. Context

### 1.1 Current state

- Two bounded contexts in place: FlightCatalog and Bookings.
- Read side uses Dapper against Postgres.
- Write side uses EF Core with per-schema migrations.
- Booking confirmation saga works with compensations.
- No caching layer; every read hits Postgres.
- No protection against concurrent writes on the same aggregate.

### 1.2 Goal

Introduce Redis as the shared caching and coordination layer:

1. Cache hot reference data (airports) with predictable invalidation.
2. Cache expensive read models (flight details) used during sagas.
3. Protect concurrent booking mutations with distributed locks.
4. Measure the impact on p95 latency and produce a before/after baseline.

### 1.3 Why this matters

- Redis is one of the most common components in distributed .NET systems.
- Cache invalidation is a classic interview topic; we implement it deliberately.
- Distributed locks show how to enforce invariants across processes.
- Performance numbers give concrete material for architecture interviews.
- This is the first step that lets modules **scale independently** — a
  prerequisite for extracting them into services in Phase 8.

---

## 2. Requirements

### 2.1 Functional

| ID    | Requirement                                                                    |
| ----- | ------------------------------------------------------------------------------ |
| FR-01 | Airports are served from cache on subsequent reads within TTL.                 |
| FR-02 | Cache is invalidated after a successful airport sync.                          |
| FR-03 | Flight details returned to the saga are cached with a short TTL.               |
| FR-04 | Adding a ticket is protected against concurrent duplicates on the same flight. |
| FR-05 | Cache is namespaced per module (no key collisions between modules).            |
| FR-06 | Cache failures do not break the application (degrade to source of truth).      |

### 2.2 Non-functional

| ID     | Requirement                                                                   |
| ------ | ----------------------------------------------------------------------------- |
| NFR-01 | Adding Redis must not change the public API surface.                          |
| NFR-02 | All cache and lock interactions go through interfaces in BuildingBlocks.      |
| NFR-03 | Both FlightCatalog and Bookings use the same cache abstraction.               |
| NFR-04 | p95 latency of `GET /flight-catalog/airports` improves measurably vs baseline. |
| NFR-05 | Distributed lock acquisition has a bounded timeout (no deadlocks).            |

---

## 3. Architecture Decisions

### AD-1: Cache-aside, not write-through

Reads go through the cache; on miss, the source is queried and the result is
written to the cache with a TTL. Writes update the database only, then
invalidate the relevant cache entries.

**Reason:** simplest correct model; no risk of serving stale data after a
write, and no need to keep cache writes transactionally consistent with the
database.

### AD-2: Two invalidation mechanisms

- **TTL-based**: every cache entry has a bounded lifetime.
- **Event-based**: domain events invalidate affected keys explicitly.

**Reason:** TTL is a safety net; explicit invalidation gives freshness where
it matters. Both are used, neither alone.

### AD-3: Per-module key prefix

Key format: `<module>:<entity>:<id>` (e.g. `flight-catalog:airport:SVO`).

**Reason:** one shared Redis instance across bounded contexts. Prefixes
prevent collisions and make cache-warming and eviction policies per-module
possible.

### AD-4: Distributed lock via Redis (SET NX PX)

A single lock primitive implemented on top of `SET key value NX PX ttl`.
Released via a Lua script that checks the owner token before deleting.

**Reason:** standard, well-understood algorithm (Redlock's single-node
variant). Multi-node Redlock is not used: a single Redis instance is
sufficient for our scope.

### AD-5: Lock granularity is the aggregate

Lock key: `bookings:booking:{bookingId}:write`.

**Reason:** locks protect aggregate invariants; locking at the aggregate
level prevents concurrent mutations without over-locking unrelated data.

### AD-6: No cache on the write side

EF Core write path never goes through Redis.

**Reason:** change tracking and transactional consistency must remain in the
database.

---

## 4. Application Changes

No changes to domain models.

New cross-cutting abstractions in `FlightsPlatform.Application.Abstractions`:

```csharp
public interface ICacheService
{
    Task<T?> GetAsync<T>(string key, CancellationToken ct = default);
    Task SetAsync<T>(string key, T value, TimeSpan ttl, CancellationToken ct = default);
    Task RemoveAsync(string key, CancellationToken ct = default);
    Task RemoveByPrefixAsync(string prefix, CancellationToken ct = default);
}

public interface IDistributedLockService
{
    Task<IAsyncDisposable?> TryAcquireAsync(
        string key, TimeSpan ttl, CancellationToken ct = default);
}

public static class CacheKeys
{
    public const string AirportPrefix = "flight-catalog:airport:";
    public const string FlightPrefix   = "flight-catalog:flight:";

    public static string Airport(string code) => AirportPrefix + code;
    public static string Flight(Guid id)      => FlightPrefix + id;
    public static string BookingLock(Guid id) => "bookings:booking:" + id + ":write";
}
```

---

## 5. Contracts and Behaviors

### 5.1 Cache TTLs

- Airports: **15 minutes** (matches sync interval).
- Flight details: **2 minutes** (flights can be delayed / cancelled at any time).

### 5.2 Invalidation triggers

- `SyncAirportsCommand` completes → `RemoveByPrefixAsync("flight-catalog:airport:")`.
- `ScheduleFlightCommand` / `DelayFlightCommand` / `CancelFlightCommand`
  completes → remove flight cache entry by id.

Wildcard removal uses a Redis `SCAN` loop, executed in Infrastructure,
never a blocking `KEYS` call.

### 5.3 Lock usage in `AddTicketCommandHandler`

Before loading the booking, acquire:

```
bookings:booking:{bookingId}:write
```

If not acquired within timeout → return
`Result.Failure("Concurrent modification", "concurrent_modification")`.

### 5.4 Cache fallback

Any Redis failure (connection lost, timeout) is logged and treated as a cache
miss. The application continues to work against Postgres. Redis is **not** on
the critical path of correctness.

---

## 6. Infrastructure

### 6.1 New Docker Compose service

```yaml
redis:
  image: redis:7-alpine
  container_name: flights-redis
  ports:
    - "6379:6379"
  command: ["redis-server", "--appendonly", "yes"]
  volumes:
    - redisdata:/data
  restart: unless-stopped
```

Add `redisdata` volume.

### 6.2 Redis client

`StackExchange.Redis` — single package.

### 6.3 Implementation location

New project: **`FlightsPlatform.Infrastructure.Redis`** (a building block).
Contains:

- `RedisCacheService` — implements `ICacheService`.
- `RedisDistributedLockService` — implements `IDistributedLockService`.
- `RedisOptions` — connection string, instance name, default TTL.

### 6.4 Registration

`services.AddRedisInfrastructure(configuration)` in host.

### 6.5 Connection string

In `appsettings.json`:

```json
"ConnectionStrings": {
  "Redis": "localhost:6379"
}
```

---

## 7. Testing Strategy

### 7.1 Unit tests

- `CacheKeys` formatting (deterministic).
- `AddTicketCommandHandler` with mocked `IDistributedLockService`:
  - lock acquired → normal flow,
  - lock not acquired → returns `concurrent_modification`.

### 7.2 Integration tests

Integration tests with a real Redis (Testcontainers) are deferred to Phase 7
when observability is in place and we can observe both sides.

### 7.3 Baseline measurement

Manual measurement of `GET /flight-catalog/airports/SVO` p95:

- **before** caching (must be recorded **before** running script 5.1),
- **after** caching.

Record in `docs/perf/phase-5-baseline.md`.

---

## 8. Tasks

### 8.1 Script 5.1 — Cache

- T-01 Add Redis service to `docker-compose.yml`.
- T-02 Create `FlightsPlatform.Infrastructure.Redis` project.
- T-03 Implement `RedisCacheService`.
- T-04 Register Redis in host DI; add `Redis` connection string.
- T-05 Cache airports in the airport read path (decorator over `IAirportReadRepository`).
- T-06 Invalidate airport cache after successful sync.
- T-07 Unit tests for `CacheKeys`.
- T-08 ADR-010: cache-aside + invalidation strategy.
- T-09 Baseline performance notes before and after.

### 8.2 Script 5.2 — Locks + tuning

- T-10 Implement `RedisDistributedLockService`.
- T-11 Use the lock in `AddTicketCommandHandler`.
- T-12 `EXPLAIN ANALYZE` review on three hottest queries.
- T-13 Add missing indexes; document results in `docs/perf/phase-5-explain.md`.
- T-14 Unit tests for lock-not-acquired path.
- T-15 ADR-011: distributed lock strategy.
- T-16 Update README with performance numbers.

---

## 9. Out of Scope

- Multi-node Redlock.
- Distributed cache for write models.
- Cache warming / prefetch.
- Redis pub/sub.
- Full Testcontainers integration tests (Phase 7).
- Metrics export to Prometheus / Grafana (Phase 7).

---

## 10. Acceptance Criteria

- `docker compose up` starts Redis alongside Postgres.
- `GET /flight-catalog/airports/{code}` returns in <5 ms on a cache hit.
- After `POST /flight-catalog/airports/sync`, subsequent reads reflect new data.
- Two concurrent `POST /bookings/{id}/tickets` with the same passenger + flight
  cannot both succeed: one returns `201`, the other returns
  `400 concurrent_modification`.
- All unit tests pass; build has zero warnings and errors.
- ADR-010 and ADR-011 committed.
- `docs/perf/phase-5-baseline.md` contains before/after numbers.

---

## 11. Open Questions

- **Q1:** Should flight details be cached at the query layer or at the ACL
  layer inside Bookings?
  *Decision: at the ACL layer — Bookings owns its freshness contract;
  FlightCatalog does not need to know who reads from it.*

- **Q2:** Do we need a fallback when Redis is down, or should the app fail fast?
  *Decision: fallback to Postgres. Redis is not on the critical path of
  correctness.*

- **Q3:** Should the distributed lock live only on confirm, or also on add ticket?
  *Decision: add ticket. Confirm is already idempotent and safe under repeated
  invocation; add ticket can create duplicate passengers without a lock.*

---

## 12. References

- ADR-001 Modular monolith
- ADR-002 CQRS split
- ADR-005 Bookings as a separate bounded context
- ADR-006 Saga orchestration
- SPEC-004 Angular SPA
---

## 13. Cancellation note (5.2.2 вЂ” performance tuning)

Task 5.2.2 (EXPLAIN ANALYZE + index tuning) is **cancelled**.

**Reason:** The operational `flight_catalog.flights` table contains only
a handful of rows (flights are created by our own commands; we do not
migrate historical data вЂ” see ADR-012). Running `EXPLAIN ANALYZE` on a
table of two rows produces a `Seq Scan`, which is the *correct* plan for
that size. Adding indexes would be premature optimization with no measured
need.

The decision is captured in **ADR-012**: we do not migrate historical
data into the operational catalog. When the table grows through real
usage, we will measure and index based on observed need.

Phase 5 is considered complete with:
- 5.1 вЂ” Redis cache-aside for airports (done)
- 5.2.1 вЂ” Distributed lock for AddTicket (done)
- 5.2.2 вЂ” Cancelled by design