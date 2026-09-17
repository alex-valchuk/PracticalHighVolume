# ADR-011: Distributed lock via Redis SET NX PX

## Status
Accepted

## Context
Some command handlers mutate a booking aggregate based on its current state:
`AddTicketCommandHandler` reads the booking, checks for duplicates, and appends
a ticket. Two requests arriving at the same time can both pass the duplicate
check before either persists, producing two identical passengers on the same
flight.

In a single-process deployment a `lock` statement would suffice. But the
modules are designed for extraction into services, and even today multiple
instances of the API could run behind a load balancer. The lock must be
process-agnostic.

## Decision

Use a **single-node Redis distributed lock** built on `SET key value NX PX ttl`.

### Key properties

1. **Atomic acquisition** вЂ” `SET ... NX PX` is a single Redis command: no
   race between "check exists" and "set".

2. **Owner token** вЂ” every acquisition writes a fresh `Guid`. This prevents
   a process from deleting a lock it no longer owns (e.g. after its TTL
   expired and someone else acquired it).

3. **Owner-safe release via Lua** вЂ” releasing is a single atomic script:
   compare the stored token to our token; delete only if they match.
   Without this, we could delete someone else's lock.

4. **TTL as a safety net** вЂ” the lock auto-expires. A crashed process does
   not leave a permanent lock. TTL is short (10 s) because the protected
   section is short (one aggregate mutation).

5. **Lock granularity = aggregate** вЂ” key `bookings:booking:{id}:write`.
   Locks one booking, not the whole bookings table.

6. **No Redlock.** Single-node is enough for the current deployment.
   Multi-node Redlock has a debated safety model and is not justified by
   our failure modes.

### Where the lock is used

`AddTicketCommandHandler` only. Rationale:

- `ConfirmBookingCommandHandler` is idempotent вЂ” repeated calls are safe.
- `CancelBookingCommandHandler` is idempotent вЂ” repeated calls are safe.
- `CreateBookingCommandHandler` creates a fresh aggregate вЂ” no shared state.
- `AddTicketCommandHandler` mutates shared state based on a prior read.

### Where the lock is NOT used

Any read path. Read paths either go through the cache (which has its own
consistency model) or are unaffected by concurrent writes.

## Consequences

Positive:
- Duplicate-passenger race is impossible as long as Redis is up.
- The lock is process-agnostic вЂ” works with N API instances.
- The lock is not on the read path, so it does not add latency to searches.

Negative:
- Adds Redis as a required dependency for a correctness guarantee on this
  one path. If Redis is down, `AddTicket` returns `concurrent_modification`
  even though no concurrent request exists. That is acceptable: it fails
  safe (no double-write), and the caller can retry.
- 10-second TTL is a hard upper bound on the operation. Anything slower
  than 10 s risks a race after the lock expires.

## Alternatives considered

- **In-process lock (`lock` / `SemaphoreSlim`)** вЂ” rejected: does not
  protect across processes; blocks the extraction to services.

- **Pessimistic DB lock (`SELECT ... FOR UPDATE`)** вЂ” works, but ties the
  invariant to a specific database and makes the aggregate depend on the
  persistence layer. Also less portable when the module becomes a service
  with its own data store.

- **Optimistic concurrency (row version / `xmin`)** вЂ” viable, but requires
  re-reading and retrying on conflict. More code, more reasoning about
  loops; the lock produces a single clean failure with a clear code.

- **Redlock (multi-node)** вЂ” overkill for a single Redis instance.

## References
- SPEC-005 (Redis caching and performance)
- ADR-010 (Redis cache-aside)
- Redis docs: SET with NX and PX