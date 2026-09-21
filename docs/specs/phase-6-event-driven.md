# SPEC-006: Event-Driven Architecture

| Field      | Value                                        |
| ---------- | -------------------------------------------- |
| Spec ID    | SPEC-006                                     |
| Status     | Accepted                 s                    |
| Phase      | 6                                            |
| Created    | 2026-09-17                                   |
| Depends on | SPEC-005 (Redis + distributed lock)          |
| Blocks     | SPEC-007 (Observability)                     |

---

## 1. Context

### 1.1 Current state

- Two bounded contexts: FlightCatalog and Bookings.
- Cross-module synchronous calls go through `IFlightCatalogClient` via MediatR.
- Domain events (`BookingCreated`, `BookingConfirmed`, `FlightScheduled`, etc.)
  exist but are not published anywhere.
- Module behaviors are registered globally in MediatR (a known defect — see
  Phase 4 notes).
- No message broker, no async processing.

### 1.2 Goal

Introduce **event-driven integration between bounded contexts** so that:

1. Modules can react to each other's domain events **without synchronous calls**.
2. Cross-module integration uses an explicit, documented contract instead of
   the current ACL-only pattern.
3. Long-running work (notifications, analytics) leaves the request path.
4. The system is ready for extraction into services — the message broker is
   the last thing that needs to change when we cut.

### 1.3 Why this matters

- It removes the **last synchronous coupling** between modules: today,
  `AddTicketCommandHandler` calls FlightCatalog and blocks; after Phase 6 it
  reacts to events.
- It enables workers (Notification, Analytics) that don't exist today and
  shouldn't live in the API process.
- It fixes the MediatR behavior collision problem: domain events go to the
  broker, behaviors stay in their module.

---

## 2. Requirements

### 2.1 Functional

| ID    | Requirement                                                                       |
| ----- | --------------------------------------------------------------------------------- |
| FR-01 | Domain events from Bookings (`BookingCreated`, `BookingConfirmed`, `BookingCancelled`) are published to the broker. |
| FR-02 | Domain events from FlightCatalog (`FlightScheduled`, `FlightDelayed`, `FlightCancelled`) are published to the broker. |
| FR-03 | The `NotificationWorker` reacts to `BookingConfirmed` by logging a simulated email. |
| FR-04 | The `AnalyticsWorker` reacts to every event by appending an audit record.            |
| FR-05 | Publishing is guaranteed: if the broker is down, events are persisted and published when it recovers. |
| FR-06 | Consumers are idempotent: receiving the same message twice does not duplicate side effects. |
| FR-07 | Poison messages do not block the queue — they go to a dead-letter queue after N retries. |
| FR-08 | The API remains functional when the broker is down (writes succeed; events queue up). |

### 2.2 Non-functional

| ID     | Requirement                                                                    |
| ------ | ------------------------------------------------------------------------------ |
| NFR-01 | Adding a broker must not change the public API surface.                        |
| NFR-02 | Integration event contracts live in a dedicated BuildingBlocks project.        |
| NFR-03 | MediatR pipeline behaviors no longer leak across modules.                      |
| NFR-04 | Every event carries a correlation ID for tracing end-to-end.                   |
| NFR-05 | RabbitMQ Management UI is available for local debugging.                       |

---

## 3. Architecture Decisions

### AD-1: RabbitMQ + MassTransit

**Chosen:** RabbitMQ as the broker, MassTransit as the .NET abstraction.

**Reason:**
- MassTransit gives us Outbox, retries, DLQ, saga support, and consumer
  registration out of the box. Rolling it by hand would take weeks.
- RabbitMQ is the most common broker in .NET shops. Kafka would be the
  right choice for stream processing at scale; our workload is transactional,
  not streaming.
- RabbitMQ Management UI is invaluable for demonstrating the system in an
  interview ("look, these queues exist, this message went here").

### AD-2: Domain events are not integration events

Two distinct types:

- **Domain events** (`BookingConfirmed`) — internal to a module, raised by
  aggregates, handled in-process. Stay as-is.
- **Integration events** (`BookingConfirmedIntegrationEvent`) — public
  contract, published to the broker. Live in a dedicated contracts project.

**Reason:** the domain event says "something happened in my world". The
integration event says "the outside world needs to know this". Mixing them
couples the domain to the broker.

### AD-3: Outbox pattern (required, not optional)

When `BookingConfirmed` fires inside a transaction, the integration event
is written to an `outbox` table **in the same transaction**. A background
publisher picks it up and pushes to RabbitMQ. If the API crashes between
DB commit and broker publish, the event is not lost.

**Reason:** dual-write (write DB, then publish) is a known anti-pattern.
Outbox is the standard fix. MassTransit supports it via
`UseEntityFrameworkOutbox`.

### AD-4: Idempotent consumers via a `consumed_messages` table

Every consumer, before processing a message, inserts the `MessageId` into
a `consumed_messages` table with a unique constraint. If insertion fails
(duplicate), the message is skipped. Exactly-once *processing* is achieved
over at-least-once *delivery*.

**Reason:** RabbitMQ guarantees at-least-once. Our consumers must not
double-process.

### AD-5: DLQ per endpoint

Each receive endpoint gets:
- `UseMessageRetry` — immediate retries.
- `UseDelayedRedelivery` — spaced-out retries.
- A dedicated `_error` queue for poison messages.

**Reason:** default behavior silently drops failed messages. We want them
visible and recoverable.

### AD-6: Separate worker host process

Workers (`NotificationWorker`, `AnalyticsWorker`) run as a **separate .NET
process**, not inside the API.

**Reason:** this is the first real step toward services. It shows
independent deployability and lets us scale workers without touching the API.

### AD-7: Fix MediatR behavior collision

Behaviors (`LoggingBehavior`, `ValidationBehavior`) are registered **once
in the host**, with filters per module, not globally in each module's
`AddMediatR`.

**Reason:** today, `Bookings.Application.Behaviors.LoggingBehavior` runs for
FlightCatalog's queries. This is a bug and must be fixed before the broker
arrives — otherwise every integration event would be double-logged.

### AD-8: Correlation ID propagation

Every command creates a correlation ID (or inherits one from the HTTP
request). The ID flows through:
- the aggregate,
- the outbox row,
- the MassTransit message header,
- the consumer's log scope.

**Reason:** without correlation IDs, event-driven systems are debug
nightmares. This is the cheapest investment with the biggest payoff.

---

## 4. Integration Event Contracts

New BuildingBlocks project: **`FlightsPlatform.Contracts`**.

```
FlightsPlatform.Contracts/
  FlightCatalog/
    FlightScheduledIntegrationEvent.cs
    FlightDelayedIntegrationEvent.cs
    FlightCancelledIntegrationEvent.cs
  Bookings/
    BookingCreatedIntegrationEvent.cs
    BookingConfirmedIntegrationEvent.cs
    BookingCancelledIntegrationEvent.cs
    BookingExpiredIntegrationEvent.cs
  Common/
    IntegrationEventBase.cs   (EventId, OccurredAt, CorrelationId)
```

**Rule:** contracts are POCOs with primitive types only. No domain types,
no EF entities, no `Money` value object. If a field can change without
breaking consumers, it does not belong in the contract.

---

## 5. Publisher Side

### 5.1 Outbox table per module

Each module's schema gets an `outbox` table:

```
flight_catalog.outbox
booking.outbox
```

MassTransit's EF Core Outbox creates and manages these.

### 5.2 Publishing flow

1. Command handler runs, modifies aggregate, `SaveChanges`.
2. Domain events are raised on the aggregate.
3. A MediatR notification handler (registered once, in Infrastructure)
   translates domain events into integration events.
4. Integration events are written to the outbox **in the same transaction**.
5. MassTransit's outbox publisher reads the table and publishes to RabbitMQ.

### 5.3 What's NOT published

Only events with cross-module meaning. For example:

- ✅ `BookingConfirmed` — Notification worker cares.
- ✅ `FlightCancelled` — Bookings module cares (to invalidate tickets).
- ❌ `TicketAdded` — internal to Bookings, nobody outside cares yet.

Start small. Add events as consumers appear.

---

## 6. Consumer Side

### 6.1 NotificationWorker (new project)

`src/Workers/FlightsPlatform.NotificationWorker/`

- Consumes `BookingConfirmedIntegrationEvent`.
- Logs a simulated email: `"[EMAIL] Booking {Ref} confirmed for {Passenger}"`.
- Idempotent via `consumed_messages`.

### 6.2 AnalyticsWorker (new project)

`src/Workers/FlightsPlatform.AnalyticsWorker/`

- Consumes **all** integration events (wildcard).
- Appends a record to a `booking.audit_log` table (JSON payload).
- Optionally also to MongoDB — deferred to Phase 7.

### 6.3 Idempotency table

Each worker schema gets:

```sql
CREATE TABLE consumed_messages (
    message_id uuid PRIMARY KEY,
    consumed_at timestamptz NOT NULL DEFAULT now()
);
```

Consumer wraps message handling in a transaction:
1. Insert `message_id`.
2. If PK conflict → skip.
3. Otherwise process + commit.

---

## 7. Infrastructure

### 7.1 Docker Compose

Add RabbitMQ:

```yaml
rabbitmq:
  image: rabbitmq:3.13-management-alpine
  container_name: flights-rabbitmq
  ports:
    - "5672:5672"     # AMQP
    - "15672:15672"   # Management UI
  environment:
    RABBITMQ_DEFAULT_USER: flights
    RABBITMQ_DEFAULT_PASS: flights_dev_password
  volumes:
    - rabbitmqdata:/var/lib/rabbitmq
  healthcheck:
    test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
    interval: 10s
    timeout: 5s
    retries: 5
```

### 7.2 MassTransit packages

- `MassTransit.RabbitMQ`
- `MassTransit.EntityFrameworkCore` (Outbox)

### 7.3 Configuration

```json
"RabbitMq": {
  "Host": "localhost",
  "VirtualHost": "/",
  "Username": "flights",
  "Password": "flights_dev_password"
}
```

### 7.4 Endpoint conventions

MassTransit's default: queue name = message type name.
We override with explicit naming: `booking-confirmed`, `flight-cancelled`,
etc.

---

## 8. Testing Strategy

### 8.1 Unit tests

- Domain → integration event mapping (pure functions).
- Idempotency handler logic with mocked `consumed_messages` repository.
- Correlation ID propagation through the pipeline behavior.

### 8.2 Integration tests

MassTransit provides an in-memory test harness
(`MassTransit.Testing`). We use it to:

- Publish an event, assert a consumer received it exactly once.
- Publish the same event twice, assert the consumer processed it once.
- Publish a poison message, assert it landed in the error queue.

Deferred to a Phase 6.3 script if too large for 6.1/6.2.

### 8.3 Manual verification

RabbitMQ Management UI at http://localhost:15672 — after running the full
booking flow, all queues and messages visible.

---

## 9. Tasks

### 9.1 Script 6.1 — Foundation

- T-01 Add RabbitMQ to docker-compose.
- T-02 Create `FlightsPlatform.Contracts` project with event POCOs.
- T-03 Add MassTransit + RabbitMQ config to host.
- T-04 Add MassTransit EF Core Outbox to both modules.
- T-05 Migration: add `outbox` tables.
- T-06 Publisher: map domain events → integration events → outbox.
- T-07 Fix MediatR behavior registration (single registration in host).
- T-08 ADR-013: Event-driven integration between bounded contexts.
- T-09 ADR-014: Outbox pattern.

### 9.2 Script 6.2 — Consumers

- T-10 Create `NotificationWorker` project.
- T-11 Consume `BookingConfirmedIntegrationEvent`.
- T-12 Create `AnalyticsWorker` project.
- T-13 Consume all integration events (wildcard).
- T-14 Add `consumed_messages` table for both workers.
- T-15 Idempotency helper.
- T-16 Retry + DLQ configuration.
- T-17 Migration for worker schemas.

### 9.3 Script 6.3 — Integration tests

- T-18 MassTransit test harness setup.
- T-19 Test: event published → consumer receives exactly once.
- T-20 Test: duplicate event → idempotent consumer skips.
- T-21 Test: poison message → DLQ.
- T-22 Correlation ID flows through.
- T-23 Update README with the event-driven section.
- T-24 Update roadmap.

---

## 10. Out of Scope

- Kafka (RabbitMQ is enough for this scope).
- Debezium / CDC on the external `bookings` database.
- Event sourcing (we do events, not event sourcing).
- MassTransit sagas (our saga is still in-process; migration to state
  machine is Phase 8+).
- Full production RabbitMQ clustering.

---

## 11. Acceptance Criteria

- `docker compose up` starts Postgres, Redis, RabbitMQ.
- RabbitMQ Management UI reachable at http://localhost:15672.
- Full booking flow (create → add ticket → confirm) publishes
  `BookingConfirmedIntegrationEvent` — visible in RabbitMQ UI.
- `NotificationWorker` logs a simulated email for the confirmation.
- `AnalyticsWorker` writes an audit row.
- Killing RabbitMQ does not break the API: writes succeed, outbox fills,
  events publish on broker recovery.
- Duplicate message → processed once.
- Poison message → lands in `*-error` queue.
- All unit tests pass.
- ADR-013 and ADR-014 committed.
- README updated.

---

## 12. Open Questions

- **Q1:** Should we publish from the domain layer or from a separate
  notification handler?
  *Decision: from a MediatR notification handler in Infrastructure. Domain
  stays pure. Infrastructure maps domain event → integration event.*

- **Q2:** One outbox per module, or one shared outbox?
  *Decision: one per module. Matches extraction boundaries. When modules
  become services, each takes its own outbox with it.*

- **Q3:** Should `BookingExpired` be published too?
  *Decision: yes. It's the signal that compensation happened — very useful
  for analytics, notifications, and admin dashboards.*

- **Q4:** How do we version integration events?
  *Decision: initially not. When we need to, we introduce
  `BookingConfirmedIntegrationEventV2` and run both consumers in parallel.
  No JSON schema registry for this project.*

---

## 13. References

- ADR-001 Modular monolith
- ADR-005 Bookings as a separate bounded context
- ADR-006 Saga orchestration
- ADR-010 Redis cache-aside
- ADR-012 No historical migration
- SPEC-005 Redis and performance