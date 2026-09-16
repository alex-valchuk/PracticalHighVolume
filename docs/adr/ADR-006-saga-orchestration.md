# ADR-006: Saga Orchestration for Booking Confirmation

## Status
Accepted

## Context
Confirming a booking spans three logical steps that touch different concerns:
1. Verifying each ticket's flight in FlightCatalog.
2. Reserving seats (in a future extraction: a separate inventory service).
3. Charging payment via an external gateway.

These steps cannot be wrapped in a single database transaction because:
- Payment gateway is an external system (no 2PC available).
- In the near future, FlightCatalog and Bookings will be separate services.

The platform must guarantee eventual consistency: either the booking is fully
confirmed, or no side effects remain.

## Decision
Use an **orchestration saga** implemented in `ConfirmBookingCommandHandler`.

Steps and compensations:

    Step 1: verify flights (read-only)           -> no compensation
    Step 2: reserve seats                        -> compensate: release seats
    Step 3: charge payment                       -> compensate: refund payment
    Step 4: mark booking Confirmed (local)       -> compensate: mark Expired

On any failure the handler runs compensations in reverse order, then marks the
booking as `Expired`. Compensations are idempotent - running them twice is safe.

Each step persists its result independently (separate `SaveChangesAsync`) so
that the compensation has something concrete to reverse and the audit trail
is complete.

The saga is currently **in-process** (MediatR). When the modules are extracted
into services, the same orchestration is expressed as a MassTransit state
machine with no changes to the domain.

## Consequences
Positive:
- No distributed transactions needed.
- Clear, debuggable, testable flow - all steps visible in one handler.
- Compensation logic is domain-adjacent and easy to unit test.
- Ports to MassTransit State Machine without domain changes.

Negative:
- Eventual consistency window: for a brief moment, seats may be reserved
  without a confirmed booking. Acceptable for our domain.
- Handler has more dependencies than a typical command handler.
- Compensations themselves can fail; we log and continue to avoid cascading.

## Alternatives considered
- **2PC (two-phase commit)** - rejected: payment gateway does not support it,
  and future services cannot participate.
- **Choreography (events between modules)** - rejected: the flow is linear and
  small; explicit orchestration is easier to reason about and test. When the
  flow grows or participants multiply, we may revisit.
- **Single local transaction with no compensations** - rejected: cannot span
  external systems.

## References
- SPEC-003.2 Section 7 (saga flow)
- ADR-005 (Bookings as a separate bounded context)