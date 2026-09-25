# ADR-018: .NET Aspire as local development orchestrator

## Status
Accepted

## Context
The platform supports three local development scenarios:

1. **Local IDE** - API from Visual Studio, infrastructure from docker-compose.
   Optimized for debugging the API.
2. **Local K8s** - everything in a kind cluster. Optimized for validating
   Kubernetes manifests and demonstrating production-like behavior.
3. **Aspire** - single AppHost process that starts containers and child
   processes, with a built-in dashboard for logs, traces, and metrics.

Each has a distinct purpose. They are not alternatives to each other;
they coexist.

## Decision

Add .NET Aspire as the third local orchestrator. It does not replace
docker-compose or kind.

### What Aspire gives us

- One command starts Postgres, Redis, RabbitMQ, the API, and both workers.
- A dashboard shows logs, traces, and metrics for all services in one UI.
- Automatic service discovery and connection string injection.
- Faster feedback than docker-compose for the daily dev loop.

### What Aspire does not give us

- It is not a deployment target. Aspire is a local development tool only.
- It does not provision the external demo database, so airport sync is
  disabled in this environment.
- It does not replace Jaeger/Prometheus/Grafana; those are still useful
  for a persistent observability history.

### Configuration

- `src/Hosts/FlightPlatform.AppHost` - the entry point.
- `apphost.csproj` references the API and both workers as project
  references. Aspire starts them as child processes.
- Postgres, Redis, RabbitMQ run as containers, managed by Aspire.
- Connection strings and RabbitMQ settings are injected via
  `WithEnvironment(...)` in `Program.cs`.
- `AirportSync__Enabled=false` - the external source is not available.

### Running

    dotnet run --project src/Hosts/FlightPlatform.AppHost

The dashboard opens in a browser with the API URL. The SPA connects to
that URL via the usual `API_TARGET` mechanism.

## Consequences

Positive:
- One-command startup for daily work.
- Built-in dashboard for logs, traces, metrics.
- Familiar to .NET developers in modern shops.

Negative:
- Additional project in the solution.
- Aspire evolves quickly; APIs may change between versions.
- Not all services are Aspire resources: Jaeger, Prometheus, Grafana
  are not started by the AppHost.

## Alternatives considered

- **Only docker-compose.** Loses the developer dashboard and first-class
  .NET integration. Rejected as the sole option.
- **Only Aspire.** Loses the ability to validate K8s manifests and the
  production-like docker-compose setup. Rejected.
- **Tye (predecessor of Aspire).** Deprecated by Microsoft. Rejected.

## References
- SPEC-008
- docs/environments.md
- .NET Aspire documentation