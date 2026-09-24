# ADR-018: .NET Aspire as local development orchestrator

## Status
Accepted

## Context
Local development currently relies on `docker compose up` to start
Postgres, Redis, RabbitMQ, Jaeger, Prometheus, Grafana, plus two
dotnet-run terminal windows for API and one worker. This works, but:

- Juggling multiple terminals to see logs is tedious.
- Trace/span inspection requires opening Jaeger in a browser.
- There is no built-in way to correlate logs across processes in real time.

.NET Aspire is Microsoft's official tool for local orchestration of
distributed .NET applications. It provides:

- A single command to start everything.
- A developer dashboard with logs, traces, metrics for all services.
- Automatic service discovery and connection string injection.
- Optional containerized resources (Postgres, Redis, RabbitMQ).

## Decision

Add .NET Aspire **as an alternative** to docker-compose for local
development. Both must work. Neither replaces the other.

- **docker-compose** remains the "closest to production" local option
  and the one documented in the main README quickstart.
- **Aspire AppHost** is the "developer productivity" option. It starts
  the same services but with a first-class dashboard.

Aspire is **not** used for Kubernetes deployment. It is a local tool only.

## Consequences

Positive:
- One command: `dotnet run --project src/Aspire/FlightsPlatform.AppHost`.
- Dashboard shows logs, traces, metrics from all services side by side.
- Faster feedback loop for development.
- Familiar to .NET developers in modern shops.

Negative:
- Adds an additional project to the solution.
- Aspire is still evolving; APIs may change between versions.
- Not all services in our stack are managed by Aspire (Jaeger,
  Prometheus, Grafana are not first-class resources); we rely on
  pre-existing containers for those.

## Alternatives considered

- **Only docker-compose.** Simpler, but loses the developer dashboard
  and first-class .NET integration. Rejected as the sole option.

- **Tye (predecessor of Aspire).** Deprecated by Microsoft. Rejected.

- **Custom script that starts everything.** Works, but reinvents what
  Aspire already provides. Rejected.

## References
- SPEC-008
- .NET Aspire documentation