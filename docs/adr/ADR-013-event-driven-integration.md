# ADR-013: Event-driven integration between bounded contexts

## Status
Accepted

## Context
Until Phase 5, modules in this platform communicate in two ways:

1. **Synchronous** вЂ” `IFlightCatalogClient` (an interface in the caller's
   Application layer, implemented in the caller's Infrastructure using
   MediatR). Used by `AddTicketCommandHandler` and `ConfirmBookingCommandHandler`.
2. **Domain events** (`BookingConfirmed`, `FlightDelayed`) вЂ” raised inside
   aggregates, never published anywhere.

Both forms work in-process, but the synchronous path leaves the last
coupling between modules: every cross-module query is a blocking call, and
the caller must know the callee's query shape. When we extract modules into
services, that coupling becomes a distributed synchronous call with all its
problems (latency, partial failure, cascading timeouts).

## Decision

Introduce **event-driven integration** as the primary cross-module
communication mechanism.

### Key ideas

1. **Domain events stay internal.** They are raised by aggregates and
   consumed in-process by handlers that belong to the same module. The
   domain has no knowledge of the broker.

2. **Integration events are the public contract.** They live in a dedicated
   project `FlightsPlatform.Contracts`, use only primitive types, and are
   published to RabbitMQ via MassTransit.

3. **Publish via a transactional Outbox.** When a command saves an aggregate
   and emits an integration event, both writes go through the same database
   transaction (see ADR-014). The broker publish happens asynchronously
   afterwards.

4. **Consumers run as separate processes** (`NotificationWorker`,
   `AnalyticsWorker`) вЂ” see Phase 6.2. This is the first real move towards
   independently deployable services.

5. **Consumers are idempotent.** Every consumer records processed message
   IDs. At-least-once delivery from RabbitMQ becomes exactly-once processing.

## Consequences

Positive:
- **Modules stop calling each other synchronously.** The coupling becomes
  "who publishes what" instead of "who calls whom".
- **Extraction becomes cheaper.** When FlightCatalog becomes a service, the
  only change is the transport (RabbitMQ instead of in-process MediatR) вЂ”
  the domain and application code do not change.
- **New consumers can be added without touching publishers.** Analytics,
  notifications, audit, monitoring вЂ” all subscribe to existing events.
- **Backpressure is natural.** Slow consumers do not block producers; the
  broker buffers.

Negative:
- **Eventual consistency.** After confirming a booking, the notification
  worker sends an email asynchronously. In a UI, the flow "confirm в†’
  receive email" has a small delay.
- **New failure modes.** Poison messages, broker outages, DLQ handling вЂ”
  all need operational tooling (Part 6.2).
- **Two-layer events.** Domain events and integration events can drift if
  not carefully maintained. We accept this: domain events express internal
  state changes, integration events express public contracts. Some domain
  events may never become integration events.

## What is NOT in scope

- **Event sourcing.** We use events for integration, not for rebuilding
  state. Aggregates are stored as documents/rows, not as event streams.
- **Kafka.** RabbitMQ is sufficient for our throughput and feature set.
  Kafka shines for stream processing and long retention, which we don't
  need.
- **Debezium / CDC on the external source.** Out of scope; we still read
  external reference data via the ACL on a schedule.

## Alternatives considered

- **Keep synchronous-only integration.** Works today, but the extraction
  cost is high: every caller needs a client wrapper, retry logic, circuit
  breaker. Rejected as the long-term direction.

- **Choreography with in-process MediatR notifications.** Almost free to
  add, but breaks the moment modules become services. Rejected because it
  creates fake decoupling.

- **Event streaming via Kafka.** More powerful, but the operational
  complexity is not justified for a platform of this size.

## References
- ADR-001 Modular monolith
- ADR-005 Bookings as a separate bounded context
- ADR-014 Outbox pattern
- SPEC-006 Event-driven architecture