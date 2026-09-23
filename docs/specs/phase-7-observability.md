# SPEC-007: Observability

| Field      | Value                                        |
| ---------- | -------------------------------------------- |
| Spec ID    | SPEC-007                                     |
| Status     | Accepted                                     |
| Phase      | 7                                            |
| Created    | 2026-09-21                                   |
| Depends on | SPEC-006 (event-driven architecture)         |
| Blocks     | SPEC-008 (Kubernetes deployment)             |

---

## 1. Context

### 1.1 Current state

- Two bounded contexts (FlightCatalog, Bookings) + two worker processes.
- Event-driven integration via RabbitMQ, transactional Outbox, idempotent consumers.
- Serilog console + file logging on the API.
- **No traces** across HTTP → MediatR → Outbox → RabbitMQ → consumer.
- **No metrics** — we don't know throughput, latency, error rates.
- **No dashboards** — no visual overview of the system's health.
- Debugging across process boundaries means grepping logs in 3 terminals.

### 1.2 Goal

Introduce the **three pillars of observability**:

1. **Traces** — one request ID flows through API, broker, and workers.
   Show the full path on a single timeline.
2. **Metrics** — numeric time series for throughput, latency, error rate,
   queue depth, saga success rate.
3. **Logs** — already present, but now correlated with traces via `TraceId`.

Plus:
- **Dashboards** in Grafana for the on-call engineer.
- **Alerts** defined as code (Prometheus rules).
- **Health checks** exposed for liveness and readiness (prerequisite for Phase 8).

### 1.3 Why this matters

- OpenTelemetry is the industry standard (SDK, collector, exporters, semantic conventions).
- This phase produces **visual artifacts** — a Jaeger trace, a Grafana dashboard — that are far more impressive in a portfolio than code.

---

## 2. Requirements

### 2.1 Functional

| ID    | Requirement                                                                       |
| ----- | --------------------------------------------------------------------------------- |
| FR-01 | A single trace ID spans HTTP request → command handler → outbox → RabbitMQ → consumer. |
| FR-02 | Jaeger UI shows the full timeline with services, spans, and durations.            |
| FR-03 | Prometheus scrapes metrics from API and both workers.                             |
| FR-04 | Grafana dashboards show: HTTP RED metrics, event throughput, saga outcomes, queue depth. |
| FR-05 | Logs contain `TraceId` and `SpanId`; Jaeger links to logs and vice versa.          |
| FR-06 | Health endpoints expose `/health/live` and `/health/ready`.                       |
| FR-07 | Saga compensation produces a visible error span with a specific status.           |
| FR-08 | Sensitive data (passwords, tokens) is not captured in traces or logs.             |

### 2.2 Non-functional

| ID     | Requirement                                                                    |
| ------ | ------------------------------------------------------------------------------ |
| NFR-01 | Trace sampling is configurable; default 100% in dev, 10% in prod.              |
| NFR-02 | Adding OpenTelemetry must not change the public API surface.                   |
| NFR-03 | Metrics endpoint must not be exposed publicly in production (only to scraper). |
| NFR-04 | Dashboards provisioned as code (JSON in Git), not clicked manually.            |
| NFR-05 | Alert rules versioned in Git alongside dashboards.                             |

---

## 3. Architecture Decisions

### AD-1: OpenTelemetry as the instrumentation standard

**Chosen:** OpenTelemetry SDK for .NET.

**Reason:**
- Vendor-neutral. Today we export to Jaeger/Prometheus; tomorrow we can switch to Datadog, New Relic, or Grafana Cloud without touching application code.
- Auto-instrumentation for ASP.NET Core, HttpClient, EF Core, MassTransit.
- Semantic conventions standardize span names and attributes.

### AD-2: Jaeger for traces, Prometheus + Grafana for metrics

**Chosen:**
- **Jaeger** — traces (open source, runnable in Docker, has its own UI).
- **Prometheus** — metrics storage and alerting.
- **Grafana** — dashboards (also supports Jaeger as a data source for trace-to-logs linking).

**Reason:** standard open-source stack. All three runnable in docker-compose. Production-portable to Grafana Cloud, Tempo, Mimir with minimal changes.

Alternative considered: **Grafana Tempo** instead of Jaeger — more modern, but Jaeger UI is more developed and familiar. Swappable later via OTLP exporter.

### AD-3: OTLP exporter, not vendor-specific

**Chosen:** `OtlpExporter` for traces and metrics.

**Reason:** Jaeger, Tempo, and most modern backends accept OTLP directly. No need for Jaeger-specific client libraries.

### AD-4: Correlation via W3C Trace Context + MassTransit headers

MassTransit automatically propagates `traceparent` (W3C standard) through message headers. The consumer picks it up and continues the trace.

**Reason:** W3C Trace Context is the standard. No custom correlation-ID code needed for the happy path.

`IntegrationEventBase.CorrelationId` stays as an application-level field for business correlation (e.g., "all events related to booking X"), separate from the technical trace ID.

### AD-5: Custom spans for domain-meaningful operations

Auto-instrumentation covers HTTP, DB, and messaging. We add **custom spans** for:
- Command handlers (`[MediatR]` pipeline behavior) — `command.execute ScheduleFlight`.
- Saga steps — `saga.step.reserve_seats`, `saga.step.charge_payment`, `saga.compensation.refund`.
- Cache operations — `cache.get`, `cache.set`, `cache.hit`, `cache.miss`.

**Reason:** business-meaningful operations should appear as first-class spans, not buried in framework noise.

### AD-6: Business metrics as counters and histograms

Beyond technical metrics (HTTP, DB, RabbitMQ), we add:
- `booking.confirmed` counter.
- `booking.expired` counter (compensations).
- `saga.duration` histogram with outcome label (`success` / `failure`).
- `events.published` counter by event type.
- `events.consumed` counter by event type and outcome (`ok` / `skipped` / `error`).

**Reason:** business metrics are what leadership and product care about. They also become the basis for SLOs.

### AD-7: Structured logging with trace correlation

Serilog continues, but the output template is updated to include `TraceId` and `SpanId`. In Grafana/Loki, you can jump from a trace to its logs.

**Reason:** logs, traces, and metrics must be **interconnected**. Three silos are almost useless.

### AD-8: Health checks with liveness/readiness split

- `/health/live` — process is up (no dependency checks).
- `/health/ready` — Postgres, Redis, RabbitMQ reachable.

**Reason:** Kubernetes uses both. Liveness probes should not fail on a transient dependency outage (that would restart a healthy pod).

---

## 4. Cross-Cutting Changes

### 4.1 New building block

`FlightsPlatform.Observability` — a project with:

- `AddFlightPlatformObservability(services, configuration)` extension that wires
  OpenTelemetry for both API and workers.
- Shared resource names (`FlightsPlatform.Api`, `FlightsPlatform.NotificationWorker`, ...).
- Activity source and meter names.
- Sanitization helpers (redact sensitive attributes).

### 4.2 API

- `AddFlightPlatformObservability` + `AddAspNetCoreInstrumentation` + `AddHttpClientInstrumentation` + `AddEntityFrameworkCoreInstrumentation` + MassTransit instrumentation.
- `/metrics` endpoint exposed via `prometheus-net.AspNetCore` (Prometheus scraping).
- `/health/live` and `/health/ready` endpoints.
- Serilog template updated.

### 4.3 Workers

- Same `AddFlightPlatformObservability`, but no HTTP instrumentation.
- MassTransit instrumentation on consumers.
- Prometheus `/metrics` endpoint.
- Health endpoints.

### 4.4 MassTransit instrumentation

MassTransit has built-in OpenTelemetry support — `x.ConfigureOpenTelemetry()` on the bus configurator.
This propagates `traceparent` on publish and creates a consumer span on consume, automatically linking traces across processes.

---

## 5. Infrastructure

### 5.1 Docker Compose additions

- `jaeger` — `jaegertracing/all-in-one:1.62` with UI on `:16686`, OTLP receiver on `:4317`.
- `prometheus` — `prom/prometheus:v2.54` scraping API and workers.
- `grafana` — `grafana/grafana:11.3` with UI on `:3000`, admin/admin, auto-provisioned data sources and dashboards.

### 5.2 Configuration

```json
"Observability": {
  "ServiceName": "FlightsPlatform.Api",
  "OtlpEndpoint": "http://localhost:4317",
  "TraceSamplingRatio": 1.0,
  "EnableConsoleExporter": false
}
```

Workers use the same section with a different `ServiceName`.

### 5.3 Dashboard as code

`docker/grafana/dashboards/*.json` — dashboard definitions.
`docker/grafana/provisioning/` — data sources + dashboard loader.
`docker/prometheus/prometheus.yml` — scrape config.
`docker/prometheus/alerts.yml` — alert rules.

All committed to Git, all versioned.

---

## 6. Dashboards

### 6.1 "Flights Platform — Overview"

- **Row: Traffic** — requests/sec by endpoint (from ASP.NET Core metrics).
- **Row: Errors** — 4xx and 5xx rates.
- **Row: Latency** — p50/p95/p99 histogram.
- **Row: Events** — publish/consume rate by type.
- **Row: Saga** — success vs failure ratio, p95 duration.
- **Row: Infrastructure** — RabbitMQ queue depth, Redis hit/miss, Postgres connection pool.

### 6.2 "Flights Platform — Traces"

- Embedded Jaeger search panel.
- Recent traces with `service.name` filter.

### 6.3 "Flights Platform — SLOs"

- Availability SLO (`success / total`).
- Saga success SLO.
- Error budget burn rate.

---

## 7. Alerts

### 7.1 Alert rules (`docker/prometheus/alerts.yml`)

- **HighErrorRate**: 5xx rate > 5% for 5 minutes.
- **SagaFailureRateHigh**: saga failure rate > 10% for 10 minutes.
- **QueueDepthGrowing**: any queue > 1000 messages for 5 minutes.
- **NoTracesReceived**: no spans from API for 2 minutes.
- **WorkerDown**: worker metrics endpoint unreachable for 1 minute.

### 7.2 Notification

Alertmanager is **out of scope** — alerts visible in Prometheus UI and Grafana. Wiring to email/Slack is a one-line addition when needed.

---

## 8. Testing Strategy

### 8.1 Unit tests

- Span names follow semantic conventions (deterministic strings).
- Metric names follow naming conventions (`<namespace>.<entity>.<action>`).
- No sensitive attributes in spans (test the redaction helper).

### 8.2 Integration tests

- Publish `BookingConfirmedIntegrationEvent` → consumer span appears as a child of a publisher span.
- Saga compensation produces an error span with `saga.outcome=compensated`.
- A trace ID is present in log output during a request.

Use `OpenTelemetry.TestHelpers` (`ActivityCollector`) to capture spans in-memory.

### 8.3 Manual verification

- Open Jaeger UI at `http://localhost:16686`.
- Run full booking flow in the SPA.
- Find the trace, verify all services appear as connected spans.
- Open Grafana at `http://localhost:3000`, verify dashboards show live data.

---

## 9. Tasks

### 9.1 Script 7.1 — OpenTelemetry foundation

- T-01 Create `FlightsPlatform.Observability` building block project.
- T-02 Wire OTel in API: traces (OTLP), metrics, ASP.NET Core, HttpClient, EF Core, MassTransit.
- T-03 Wire OTel in NotificationWorker and AnalyticsWorker.
- T-04 Add `/metrics` endpoint via `prometheus-net.AspNetCore`.
- T-05 Add `/health/live` and `/health/ready` endpoints with dependency probes.
- T-06 Update Serilog template to include `TraceId` and `SpanId`.
- T-07 Add `Observability` configuration section to all appsettings.
- T-08 ADR-015: OpenTelemetry as the observability standard.

### 9.2 Script 7.2 — Jaeger + Prometheus + Grafana

- T-09 Add `jaeger`, `prometheus`, `grafana` to docker-compose.
- T-10 Prometheus scrape config for API + workers.
- T-11 Grafana provisioning: datasources (Prometheus, Jaeger), dashboard loader.
- T-12 Overview dashboard JSON.
- T-13 SLO dashboard JSON.
- T-14 Alert rules YAML.
- T-15 ADR-016: Observability stack choice.

### 9.3 Script 7.3 — Custom instrumentation + business metrics

- T-16 MediatR behavior that creates a span for every command.
- T-17 Saga step spans (reserve seats, charge payment, confirm, compensation).
- T-18 Cache hit/miss counters in `RedisCacheService`.
- T-19 Business metrics in command handlers (`booking.confirmed`, `booking.expired`).
- T-20 Tests using `ActivityCollector` for spans and metrics.
- T-21 Update README with observability section + screenshot of Jaeger trace.

---

## 10. Out of Scope

- **Alertmanager** and notification routing (email, Slack) — deferred.
- **Loki** for log aggregation — logs stay on disk. Adding Loki is a small follow-up but not essential for this phase.
- **Continuous profiling** (Pyroscope) — deferred to Phase 9.
- **Distributed sampling strategies** (tail-based sampling) — head-based only.
- **Grafana Cloud** deployment — local only.

---

## 11. Acceptance Criteria

- `docker compose up` starts Jaeger, Prometheus, Grafana alongside the rest.
- `http://localhost:16686` — Jaeger UI shows traces from API and both workers.
- `http://localhost:9090` — Prometheus UI shows scrape targets as UP.
- `http://localhost:3000` — Grafana shows the "Flights Platform — Overview" dashboard with live data.
- **A full booking flow produces ONE trace** with spans for:
  - HTTP request
  - `ScheduleFlight` / `CreateBooking` / `ConfirmBooking` commands
  - EF Core save
  - Outbox publish
  - RabbitMQ receive
  - Consumer execution
- Saga compensation path produces spans with `saga.step.*` and `saga.compensation.*` names.
- Logs on API and workers contain `TraceId` matching the Jaeger trace.
- `/health/live` returns 200 even when Postgres is stopped.
- `/health/ready` returns 503 when Postgres is stopped.
- All unit and integration tests pass.
- ADR-015 and ADR-016 committed.
- README updated.

---

## 12. Open Questions

- **Q1:** Should we ship traces to Jaeger directly, or add an **OpenTelemetry Collector** in between?
  *Decision: ship directly for Phase 7 (fewer moving parts). Add Collector in Phase 8 when deployment complexity justifies it.*

- **Q2:** Sampling — 100% in dev, but what in "prod-like"?
  *Decision: 10% head sampling by default, controlled via `TraceSamplingRatio` config. Always sample errors (parent-based with error override).*

- **Q3:** Do we need log aggregation (Loki) now?
  *Decision: no. Serilog writes to files + console. Loki is easy to add in Phase 9 if needed.*

- **Q4:** Should we expose Prometheus metrics on the same port as HTTP, or a separate one?
  *Decision: same port, path `/metrics`. Simpler for Docker/K8s scraping. Later, if needed, move to a sidecar exporter.*

---

## 13. References

- ADR-001 Modular monolith
- ADR-013 Event-driven integration
- ADR-014 Outbox pattern
- SPEC-006 Event-driven architecture
- OpenTelemetry .NET: https://opentelemetry.io/docs/languages/net/
- MassTransit observability: https://masstransit.io/documentation/configuration/observability