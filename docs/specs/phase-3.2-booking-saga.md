# SPEC-003.2: Booking Confirmation Saga

| Field           | Value                                 |
|-----------------|---------------------------------------|
| Spec ID         | SPEC-003.2                            |
| Status          | Accepted                              |
| Phase           | 3.2                                   |
| Created         | 2026-09-15                            |
| Depends on      | SPEC-003.1 (Bookings module skeleton) |
| Blocks          | SPEC-003.3 (integration tests)        |

---

## 1. Context

### 1.1 Current state
- Module `Bookings` exists with Clean Architecture layers.
- `CreateBookingCommand` creates a draft booking (status `Pending`, `TotalAmount = 0`).
- No way to add tickets, confirm, or cancel a booking.
- Cross-module contract `IFlightCatalogClient` declared in 3.1 but not implemented.

### 1.2 Goal
Implement the full booking lifecycle on the write side:
1. Add tickets to a pending booking.
2. Confirm a booking - this is a **distributed transaction** between Bookings
   and FlightCatalog that must either succeed completely or roll back completely.
3. Cancel a pending booking.

### 1.3 Why this matters
- Demonstrates **orchestration saga** pattern with **compensating transactions**.
- Prepares for microservices extraction: the same logic ports to MassTransit
  state machine in Phase 5 without domain changes.
- Shows how to enforce cross-module consistency without 2PC.

---

## 2. Requirements

### 2.1 Functional

| ID      | Requirement                                                                     |
|---------|---------------------------------------------------------------------------------|
| FR-01   | User can add a ticket to a `Pending` booking.                                   |
| FR-02   | Adding a ticket validates that the flight exists in FlightCatalog.              |
| FR-03   | Adding a ticket rejects flights with status `Cancelled` or `Departed`.          |
| FR-04   | The same passenger cannot appear twice on the same flight.                      |
| FR-05   | `TotalAmount` is recalculated after each ticket addition.                       |
| FR-06   | User can confirm a `Pending` booking that has at least one ticket.              |
| FR-07   | Confirm reserves seats, charges payment, sets status `Confirmed`.               |
| FR-08   | If any confirm step fails, previously completed steps are compensated.          |
| FR-09   | After compensation, booking moves to `Expired`.                                 |
| FR-10   | Confirm on already `Confirmed` booking returns success (idempotent).            |
| FR-11   | Confirm on `Expired` or `Cancelled` booking returns error.                      |
| FR-12   | User can cancel a `Pending` booking with a reason.                              |
| FR-13   | Cancel releases any active seat reservations for that booking.                  |

### 2.2 Non-functional

| ID      | Requirement                                                                     |
|---------|---------------------------------------------------------------------------------|
| NFR-01  | All commands and queries flow through MediatR pipeline behaviors.               |
| NFR-02  | Domain exceptions map to HTTP 400 with `error: domain_error`.                   |
| NFR-03  | Saga steps and compensations emit distinct log entries for debugging.           |
| NFR-04  | Payment gateway is abstracted; a deterministic fake is used in tests.           |
| NFR-05  | Saga handler is deterministic given mocked dependencies.                        |

---

## 3. Architecture Decisions

### AD-1: Orchestration over Choreography
**Chosen:** orchestration (a single handler orchestrates the saga).
**Reason:** a 3-step transaction is easier to read, debug, and test as a single
flow. Choreography requires event coupling between modules and implicit flow.
Porting to MassTransit State Machine later preserves the same structure.

### AD-2: In-process saga (MediatR), not MassTransit yet
**Chosen:** in-process.
**Reason:** we have no message broker in the platform yet. Introducing
MassTransit now would add infrastructure without business value.
The saga logic will not change when moving to broker in Phase 5.

### AD-3: Cross-module call via IMediator, not direct App reference
`Bookings.Infrastructure` references `FlightCatalog.Application` and calls
`IMediator.Send(new GetFlightByIdQuery(id))`.
**Reason:** Infrastructure в†’ foreign Application is an acceptable dependency
direction. A separate `FlightCatalog.Contracts` project will be introduced in
Phase 5, at which point only the Contract project is referenced.

### AD-4: Persist payment and seat reservations
Payment records persist to `booking.payments`. Seat reservations persist to
`booking.seat_reservations`.
**Reason:** makes compensations idempotent and auditable, and enables
integration tests without external dependencies.

### AD-5: Payment gateway 20% failure by default, configurable
**Chosen:** fake gateway with configurable failure rate via `appsettings.json`.
**Reason:** demo needs visible compensation in action; tests need deterministic
outcomes (rate 0% or 100%).

---

## 4. Domain Model

### 4.1 Booking aggregate (extended)
New methods:

    void AddTicket(PassengerId passengerId, PassengerName passengerName,
                   Guid flightId, decimal amount)
        - throws if Status != Pending
        - throws if passenger already on same flight
        - throws if amount <= 0
        - appends Ticket, recalculates TotalAmount
        - raises TicketAdded

    void Confirm()
        - throws if Status != Pending
        - throws if no tickets
        - sets Status = Confirmed
        - raises BookingConfirmed

    void MarkExpired(string reason)
        - throws if Status != Pending
        - sets Status = Expired
        - raises BookingExpired

### 4.2 New domain events
- `TicketAdded(BookingId, TicketId, FlightId, Amount, Currency)`
- `BookingConfirmed(BookingId, BookingReference, TotalAmount, Currency)`
- `BookingExpired(BookingId, BookingReference, Reason)`
- `SeatReserved(BookingId, ReservationId, TicketId, FlightId)`
- `SeatReleased(BookingId, ReservationId)`
- `PaymentCharged(BookingId, PaymentId, Amount, Currency)`
- `PaymentRefunded(BookingId, PaymentId, Amount)`

Note: all events are in-process (`INotification`). Cross-module publication
via RabbitMQ is a Phase 5 concern.

---

## 5. Contracts

### 5.1 Commands

    AddTicketCommand(
        Guid BookingId,
        Guid FlightId,
        string PassengerId,
        string PassengerName,
        decimal Amount
    ) : IRequest<Result<Guid>>

    ConfirmBookingCommand(Guid BookingId) : IRequest<Result<ConfirmBookingResult>>

    CancelBookingCommand(Guid BookingId, string Reason) : IRequest<Result>

### 5.2 Cross-module contract (implemented in 3.2)

    public interface IFlightCatalogClient
    {
        Task<FlightSummary?> GetFlightAsync(Guid flightId, CancellationToken ct);
    }

    public sealed record FlightSummary(
        Guid Id,
        string FlightNumber,
        string DepartureAirport,
        string ArrivalAirport,
        DateTimeOffset ScheduledDeparture,
        DateTimeOffset ScheduledArrival,
        int Status);

### 5.3 Payment gateway

    public interface IPaymentGateway
    {
        Task<PaymentResult> ChargeAsync(
            Guid bookingId, decimal amount, string currency, CancellationToken ct);

        Task RefundAsync(Guid paymentId, CancellationToken ct);
    }

    public sealed record PaymentResult(
        bool Success,
        Guid? PaymentId,
        string? FailureReason);

### 5.4 Seat reservation service

    public interface ISeatReservationService
    {
        Task<Guid> ReserveAsync(
            Guid bookingId, Guid ticketId, Guid flightId, CancellationToken ct);

        Task ReleaseAsync(Guid reservationId, CancellationToken ct);

        Task ReleaseAllForBookingAsync(Guid bookingId, CancellationToken ct);
    }

### 5.5 Response DTOs

    ConfirmBookingResult(
        Guid BookingId,
        bool Confirmed,
        string? FailureReason);

---

## 6. Data Model

### 6.1 Table `booking.seat_reservations`

| Column        | Type           | Notes                        |
|---------------|----------------|------------------------------|
| id            | uuid PK        |                              |
| booking_id    | uuid FK        | -> booking.bookings(id)      |
| ticket_id     | uuid           |                              |
| flight_id     | uuid           | external ref to flight_catalog|
| status        | int            | 0=Active, 1=Released         |
| reserved_at   | timestamptz    |                              |
| released_at   | timestamptz?   | null if active               |

Index: `(booking_id, status)`.

### 6.2 Table `booking.payments`

| Column              | Type           | Notes                     |
|---------------------|----------------|---------------------------|
| id                  | uuid PK        |                           |
| booking_id          | uuid FK        |                           |
| amount              | numeric(18,2)  |                           |
| currency            | varchar(3)     |                           |
| status              | int            | 0=Charged,1=Refunded,2=Failed|
| external_reference  | varchar(64)?   | from gateway              |
| created_at          | timestamptz    |                           |
| refunded_at         | timestamptz?   |                           |

Index: `(booking_id)`.

### 6.3 New EF migration
`AddBookingSagaTables` - creates the two tables above.

---

## 7. Saga Flow: ConfirmBooking

    Step 0. Load booking. If null -> NotFound.
            If Confirmed -> return success (idempotent).
            If Expired or Cancelled -> return failure.

    Step 1. Verify booking has tickets. Otherwise -> failure (no compensation).

    Step 2. For each ticket:
        2.1. Call IFlightCatalogClient.GetFlightAsync.
        2.2. If flight null or inactive -> fail. Compensate steps 2.1..2.N.
        2.3. Call ISeatReservationService.ReserveAsync.
             On failure -> fail. Compensate steps 2.1..2.N.

    Step 3. Call IPaymentGateway.ChargeAsync.
            On failure -> fail. Compensate step 2 (release all seats).

    Step 4. booking.Confirm().
            Save. Publish BookingConfirmed.

    On any failure after step 2 begins:
        - Call ISeatReservationService.ReleaseAllForBookingAsync.
        - If payment was charged, call IPaymentGateway.RefundAsync.
        - booking.MarkExpired(reason).
        - Save. Publish BookingExpired.

---

## 8. Testing Strategy

### 8.1 Unit tests (deterministic, no DB)
- `AddTicketCommandHandler`
  - happy path
  - booking not found
  - booking not Pending
  - flight not found
  - flight cancelled
  - duplicate passenger on same flight

- `ConfirmBookingCommandHandler`
  - happy path (all mocks succeed)
  - idempotent when already Confirmed
  - failure when no tickets
  - payment failure triggers seat release + MarkExpired
  - seat reservation failure triggers release + MarkExpired
  - compensating actions are called exactly the expected number of times

- `FakePaymentGateway`
  - success rate 100 -> always success
  - success rate 0 -> always failure

### 8.2 Integration tests (deferred to Phase 5)
Not in this spec. Will use Testcontainers later.

---

## 9. Tasks

### 9.1 Script 3.2.1 (scope of first generation)
- T-01 Extend `Booking` aggregate: `AddTicket`, `Confirm`, `MarkExpired`.
- T-02 Add domain events: `TicketAdded`, `BookingConfirmed`, `BookingExpired`.
- T-03 Add `IFlightCatalogClient` implementation in `Bookings.Infrastructure`.
- T-04 Add project reference `Bookings.Infrastructure -> FlightCatalog.Application`.
- T-05 Add `AddTicketCommand` + handler + validator.
- T-06 Add endpoint `POST /bookings/{id}/tickets`.
- T-07 Unit tests for `AddTicket`.
- T-08 Unit tests for extended aggregate.

### 9.2 Script 3.2.2 (scope of second generation)
- T-09 Add EF entity `SeatReservation` + configuration.
- T-10 Add EF entity `Payment` + configuration.
- T-11 Add migration `AddBookingSagaTables`.
- T-12 Add `IPaymentGateway` + `FakePaymentGateway` + options.
- T-13 Add `ISeatReservationService` + implementation.
- T-14 Add `ConfirmBookingCommand` + saga handler.
- T-15 Add `CancelBookingCommand` + handler.
- T-16 Add endpoints `POST /bookings/{id}/confirm`, `POST /bookings/{id}/cancel`.
- T-17 Unit tests for saga (success, failure at each step).
- T-18 ADR-006: Saga orchestration vs alternatives.

---

## 10. Out of Scope
- Outbox pattern (Phase 5).
- RabbitMQ / MassTransit (Phase 5).
- Real payment processor.
- Real seat inventory service.
- Refund flow for confirmed bookings (Phase 6+).
- Notifications on booking state changes (Phase 5).

---

## 11. Acceptance Criteria

- `POST /bookings/{id}/tickets` adds a ticket and updates `TotalAmount`.
- `POST /bookings/{id}/confirm` returns success and sets status `Confirmed`.
- With `FakePaymentGateway` configured to fail, `POST /confirm` returns failure,
  booking status is `Expired`, seat reservations are released, and logs show
  the compensation steps.
- Duplicate `POST /confirm` on a `Confirmed` booking returns success without
  side effects.
- All unit tests pass.
- `dotnet build` yields zero warnings and zero errors.
- New ADR-006 committed.

---

## 12. Open Questions
- Q1: Should ticket price come from the flight (via FlightCatalog) or be
  passed by the client? *Decision: passed by the client for now. Pricing
  module is a future bounded context.*
- Q2: Should `ConfirmBooking` allow partial confirmation (some tickets fail,
  others succeed)? *Decision: no - all-or-nothing. Refunds are a separate flow.*

---

## 13. References
- ADR-001: Modular monolith
- ADR-002: CQRS split
- ADR-003: Own schema
- ADR-004: Integration via ACL and polling sync
- ADR-005: Bookings as a separate bounded context
- ADR-006: Saga orchestration (to be written in 3.2.2)
- SPEC-003.1: Bookings module skeleton