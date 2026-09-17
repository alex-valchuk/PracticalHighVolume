# ADR-014: Transactional Outbox pattern for integration events

## Status
Accepted

## Context
When a command modifies an aggregate and emits an integration event, two
different systems must be updated:

1. **The database** вЂ” the aggregate's new state.
2. **The message broker** вЂ” the event for other modules.

These two updates cannot be made atomically. The classic "write, then
publish" pattern has two failure modes:

- **Commit succeeds, publish fails.** The aggregate is persisted, but no
  other module ever learns about it. Silent inconsistency.
- **Publish succeeds, commit fails.** The event is broadcast, but the
  aggregate state is not in the database. Consumers act on data that does
  not exist.

Neither failure is acceptable for something like `BookingConfirmed` вЂ” the
notification worker, analytics, and downstream billing all depend on it.

## Decision

Adopt the **transactional Outbox pattern** for every integration event.

### How it works

1. The command handler modifies the aggregate and adds the event to the
   `outbox` table вЂ” **in the same transaction**.
2. `SaveChanges` commits both the aggregate change and the outbox row
   atomically.
3. A background publisher (provided by MassTransit) reads unprocessed
   outbox rows, publishes them to RabbitMQ, and marks them as sent.
4. If the process crashes after commit but before publish, the outbox row
   is still there; the publisher resumes on restart.

### Implementation

- MassTransit's `AddEntityFrameworkOutbox<TContext>` configures the outbox
  per `DbContext`.
- `modelBuilder.AddOutboxStateEntity()` and
  `AddOutboxMessageEntity()` register the tables in each module's schema:
  `flight_catalog.outbox_*` and `booking.outbox_*`.
- Every `IPublishEndpoint.Publish(...)` call in a handler that is inside
  a `SaveChanges` scope automatically routes through the outbox.
- Outbox tables are per-module: when a module becomes a service, it takes
  its outbox with it.

### Ordering and idempotency

The outbox guarantees **at-least-once delivery**, not exactly-once. If the
publisher crashes after publishing but before marking the row as sent, the
same event is published twice on restart. Consumers must be idempotent
(see SPEC-006 section 6.3).

## Consequences

Positive:
- **No more dual-write.** The event is guaranteed to be published if and
  only if the aggregate change is committed.
- **Recoverable.** Crashed publishers pick up where they left off.
- **Inspectable.** Outbox tables show exactly what was published and when.
- **Portable.** When the module moves to its own database, the outbox
  moves with it вЂ” no changes to the pattern.

Negative:
- **Extra table and background publisher.** Small operational overhead.
- **Slightly higher latency before consumers see the event** (publisher
  polls every few seconds by default; configurable).
- **Outbox cleanup required.** Successful rows must eventually be deleted
  or archived to prevent unbounded growth. MassTransit handles this via
  configurable retention.

## Alternatives considered

- **Publish directly from the handler after SaveChanges.**
  Rejected: dual-write. Loses events on failure or emits events for
  changes that never committed.

- **Two-phase commit (distributed transaction) across DB and broker.**
  Rejected: RabbitMQ does not support 2PC with Postgres in any practical
  way, and 2PC is a poor fit for a system designed for eventual
  consistency.

- **Event sourcing.** Rejected: overkill for our domain, and it changes
  how aggregates are stored. We use events for integration, not for state.

- **In-memory queue with persistence on crash.** Not durable; loses
  events. Rejected.

## Configuration notes

- **Retention.** MassTransit cleans up delivered outbox rows after a
  configurable window. Defaults are acceptable for development.
- **Publisher cadence.** `UseBusOutbox` publishes on the next bus tick
  (fast). Standalone outbox publishers can be configured with a longer
  interval for throughput.
- **What is NOT in the outbox.** In-process domain events that never
  become integration events do not go through the outbox. They stay
  entirely in memory, as before.

## References
- ADR-013 Event-driven integration
- SPEC-006 Event-driven architecture
- Microservices.io: Transactional Outbox