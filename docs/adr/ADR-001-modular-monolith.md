# ADR-001: Modular Monolith Instead of Microservices

## Status
Accepted

## Context
We are building a flight booking platform on top of a large existing Postgres
database (demo bookings database, ~1.3 GB). Team size is small; delivery speed
matters more than unlimited horizontal scaling at this stage.

## Decision
We start with a modular monolith. Each bounded context (Flight Catalog,
Booking, Pricing) is a separate module inside one solution, one process,
one deployment. Modules communicate via in-process MediatR notifications
(and via an outbox to RabbitMQ later).

## Consequences
Positive:
- Fast local development, single debugging session.
- No distributed transactions, no saga needed yet.
- Strong module boundaries (Domain / Application / Infrastructure / Api),
  so slicing into services later is a mechanical step.

Negative:
- Single process, single point of failure until scaled.
- Requires discipline: no direct calls between modules.

## When to revisit
When a module needs independent scaling, different tech stack, or its own
deployment cadence, we extract it as a service using the same boundaries.