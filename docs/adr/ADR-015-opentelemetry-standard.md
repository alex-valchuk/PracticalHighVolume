# ADR-015: OpenTelemetry as the observability standard

## Status
Accepted

## Context
The platform has two bounded contexts, two worker processes, RabbitMQ, Postgres,
and Redis. Debugging a single user request requires opening four terminals and
grepping logs by hand.

We need a single trace ID across HTTP, MediatR, outbox, RabbitMQ, and the
consumer. We need metrics for throughput, latency, error rate, queue depth.
We need vendor neutrality so we can swap backends without touching app code.

## Decision
Adopt OpenTelemetry (OTel) as the instrumentation standard.

1. OTLP exporter - one protocol for traces and metrics.
2. Resource attributes: service.name, deployment.environment.
3. Auto-instrumentation: ASP.NET Core, HttpClient, EF Core, MassTransit, Runtime.
4. Custom ActivitySources for domain operations: Commands, Saga, Cache.
5. Head-based sampling: ParentBased(TraceIdRatioBased(ratio)).
6. Sanitization processor redacts sensitive attributes before export.
7. Business metrics in one Meter: bookings.confirmed, bookings.expired,
   saga.duration, cache.hits, cache.misses.

## What we do NOT do
- No OTel Collector yet (Phase 8 concern).
- No tail-based sampling.
- No custom trace IDs - W3C traceparent only.
- No log aggregation (Loki) - Serilog files + TraceId correlation.

## Consequences
Positive:
- Single trace across all processes.
- Vendor-neutral.
- Metrics and traces share the resource model.

Negative:
- Additional runtime overhead (<1% typical).
- New dependency surface.

## References
- SPEC-007
- ADR-013 Event-driven integration