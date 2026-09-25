# SPEC-008: Kubernetes Deployment

| Field      | Value                                        |
| ---------- | -------------------------------------------- |
| Spec ID    | SPEC-008                                     |
| Status     | Accepted                                     |
| Phase      | 8                                            |
| Created    | 2026-09-23                                   |
| Depends on | SPEC-007 (observability)                     |
| Blocks     | SPEC-009 (final polish)                      |

---

## 1. Context

### 1.1 Current state

- Full stack runs locally via `docker compose`:
  Postgres, Redis, RabbitMQ, API (host), 2 workers (container),
  Jaeger, Prometheus, Grafana.
- API runs on the host with `dotnet run` — not containerized yet.
- Health checks in place: `/health/live` and `/health/ready`.
- OpenTelemetry exports to Jaeger via OTLP; Prometheus scrapes
  `/metrics` on all three processes.
- Every service already has liveness/readiness semantics defined.

### 1.2 Goal

Deploy the entire stack to Kubernetes with:

1. **Helm chart** for parameterized deployment.
2. **All services as K8s workloads** — Deployments for stateless (API,
   workers, Jaeger, Prometheus, Grafana), StatefulSets for stateful
   (Postgres, Redis, RabbitMQ).
3. **ConfigMaps + Secrets** for configuration and credentials.
4. **Services + Ingress** for internal and external access.
5. **Liveness + readiness probes** wired to our existing `/health/*`.
6. **Horizontal Pod Autoscaler** for workers based on CPU/queue depth.
7. **CI job** that lints the chart and (optionally) applies it to a
   local kind cluster.
8. **.NET Aspire** as an alternative orchestration path for local
   development — replaces `docker compose` as the "one command" way
   to run everything.

### 1.3 Why this matters

- Demonstrates understanding of the full deployment lifecycle:
  image → workload → service → ingress → probes → scaling.
- Helm shows ability to package and parameterize a real system.
- Aspire shows awareness of modern .NET tooling for distributed apps.

---

## 2. Requirements

### 2.1 Functional

| ID    | Requirement                                                                       |
| ----- | --------------------------------------------------------------------------------- |
| FR-01 | `helm install flights ./chart` deploys the entire stack into a K8s namespace.      |
| FR-02 | All stateful services use PersistentVolumeClaims; data survives pod restarts.      |
| FR-03 | Readiness probes reflect real dependency health (Postgres, Redis, RabbitMQ).       |
| FR-04 | Config differences (dev vs prod) are driven by `values.yaml` overrides.            |
| FR-05 | Secrets are stored in K8s Secrets, not hardcoded in the chart.                     |
| FR-06 | Ingress exposes Grafana, Jaeger, RabbitMQ UI, API Scalar to the developer.          |
| FR-07 | HPA scales workers from 1 to 5 replicas based on CPU utilization.                  |
| FR-08 | `dotnet run --project src/Aspire/FlightsPlatform.AppHost` starts the full stack.   |

### 2.2 Non-functional

| ID     | Requirement                                                                    |
| ------ | ------------------------------------------------------------------------------ |
| NFR-01 | Image sizes: API < 200 MB, workers < 150 MB (multi-stage builds).              |
| NFR-02 | All images pull from `mcr.microsoft.com/dotnet/aspnet:10.0-alpine`.            |
| NFR-03 | Helm chart passes `helm lint` and `kubeconform` validation.                    |
| NFR-04 | Resource requests/limits defined for every container.                          |
| NFR-05 | Local dev via kind or Docker Desktop K8s runs the full stack end-to-end.       |

---

## 3. Architecture Decisions

### AD-1: Helm as the packaging format

**Chosen:** Helm 3.

**Reason:** industry standard, versioned releases, rollback,
templated values. A single chart with multiple values files
(`values-dev.yaml`, `values-prod.yaml`) is more maintainable than
hand-written manifests or Kustomize overlays for our size.

### AD-2: kind for local K8s

**Chosen:** kind (Kubernetes in Docker).

**Reason:** runs inside Docker Desktop, no separate VM, fast.
Docker Desktop's built-in K8s also works — the chart does not depend
on which local cluster is used.

### AD-3: StatefulSets for Postgres, Redis, RabbitMQ

**Chosen:** StatefulSet with a `volumeClaimTemplate`.

**Reason:** stable network identity, ordered rollout, persistent
volumes. Deployments are for stateless workloads only.

Alternatives considered:
- **Operators** (Zalando Postgres, Redis Operator) — overkill for a
  portfolio project. Would be the choice in a real production cluster.
- **External managed services** (RDS, ElastiCache) — makes local
  demo impossible; goes against "runs on any cluster".

### AD-4: Secrets vs ConfigMaps

- **ConfigMaps** for non-sensitive: service names, ports, log levels.
- **Secrets** for credentials: Postgres password, RabbitMQ user/pass,
  connection strings.

Chart template uses `values.secrets.*` populated via `--set` or an
external secret manager in production. For local demo, defaults live
in `values-dev.yaml` and are clearly marked "change in prod".

### AD-5: One chart, multiple values files

```
chart/
  Chart.yaml
  values.yaml           # defaults
  values-dev.yaml       # local dev (kind / Docker Desktop K8s)
  values-prod.yaml      # production-like overrides
  templates/
    api.yaml
    notification-worker.yaml
    analytics-worker.yaml
    postgres.yaml
    redis.yaml
    rabbitmq.yaml
    jaeger.yaml
    prometheus.yaml
    grafana.yaml
    ingress.yaml
    secrets.yaml
    configmaps.yaml
    hpa.yaml
    _helpers.tpl
```

**Reason:** one chart is simple to reason about and easy to review.
Multi-chart (umbrella chart with subcharts) is the next step when
components become independently deployable — for now, single chart.

### AD-6: Ingress with nginx-ingress

**Chosen:** nginx-ingress controller.

**Reason:** most common in kind and local setups, well-documented,
single annotation to enable.

Ingress hosts:
- `api.flights.local`     → FlightsPlatform.Api (Scalar UI)
- `grafana.flights.local` → Grafana
- `jaeger.flights.local`  → Jaeger UI
- `rabbit.flights.local`  → RabbitMQ Management

`/etc/hosts` entries documented in README.

### AD-7: HPA for workers

**Chosen:** HPA v2, CPU-based, min 1 max 5 replicas.

**Reason:** workers are the elastic part of the system — they react
to queue depth and can scale horizontally without coordination.

Future enhancement (out of scope): KEDA with RabbitMQ queue-length
scaling. Mentioned in ADR but not implemented.

### AD-8: .NET Aspire as an alternative local orchestrator

**Chosen:** add an Aspire AppHost project alongside docker-compose.

**Reason:** Aspire provides a first-class local dev experience for
distributed .NET apps — service discovery, connection string
injection, dashboard. It is **not** a replacement for Kubernetes,
but a complement for day-to-day development.

Result: two ways to run locally:
- `docker compose up -d` — full stack, closest to prod.
- `dotnet run --project src/Aspire/FlightsPlatform.AppHost` — Aspire
  with dashboard, live logs, traces, metrics.

Both must work. Neither is "the only" way.

### AD-9: Image registry

**Chosen:** local images loaded into kind via `kind load docker-image`.

**Reason:** no external registry needed for the demo. In production,
images go to ACR/GHCR — a one-line change in `values.yaml`
(`image.repository` and `image.tag`).

---

## 4. Chart Structure (detail)

### 4.1 values.yaml (skeleton)

```yaml
global:
  namespace: flights-platform
  imageRegistry: ""       # empty = local images
  imagePullPolicy: IfNotPresent

api:
  image:
    repository: flights-api
    tag: latest
  replicas: 1
  resources:
    requests: { cpu: "100m", memory: "256Mi" }
    limits:   { cpu: "500m", memory: "512Mi" }
  env:
    ASPNETCORE_ENVIRONMENT: Development

notificationWorker:
  image:
    repository: flights-notification-worker
    tag: latest
  replicas: 1
  hpa:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    targetCPU: 70

analyticsWorker:
  image:
    repository: flights-analytics-worker
    tag: latest
  replicas: 1
  hpa:
    enabled: true
    minReplicas: 1
    maxReplicas: 5
    targetCPU: 70

postgres:
  image:
    repository: postgres
    tag: 16-alpine
  storage: 5Gi
  user: flights
  database: flights_demo
  # password comes from Secret

redis:
  image:
    repository: redis
    tag: 7-alpine
  storage: 1Gi

rabbitmq:
  image:
    repository: rabbitmq
    tag: 3.13-management-alpine
  storage: 2Gi

jaeger:
  image:
    repository: jaegertracing/all-in-one
    tag: 1.76.0

prometheus:
  image:
    repository: prom/prometheus
    tag: v2.54.1

grafana:
  image:
    repository: grafana/grafana
    tag: 11.3.0
  adminUser: admin
  # adminPassword comes from Secret

ingress:
  enabled: true
  className: nginx
  hosts:
    api: api.flights.local
    grafana: grafana.flights.local
    jaeger: jaeger.flights.local
    rabbit: rabbit.flights.local
```

### 4.2 Secrets

`templates/secrets.yaml` creates:
- `flights-postgres-secret` — Postgres password
- `flights-rabbitmq-secret` — RabbitMQ user/pass
- `flights-grafana-secret` — Grafana admin password

Values come from `values-dev.yaml` (documented as "dev-only, change
in prod") or from `--set secrets.postgresPassword=...` at install time.

### 4.3 Probes

- **API**:
  - `livenessProbe`: `GET /health/live` on port 8080
  - `readinessProbe`: `GET /health/ready` on port 8080
  - `startupProbe`: `GET /health/live`, 30s budget
- **Workers**:
  - `livenessProbe`: TCP check on the metrics port (9101/9102)
  - No readinessProbe (workers have no traffic)
- **Postgres/Redis/RabbitMQ**: standard exec-based probes

---

## 5. Aspire AppHost

New project: `src/Aspire/FlightsPlatform.AppHost`.

```csharp
var builder = DistributedApplication.CreateBuilder(args);

var postgres = builder.AddPostgres("postgres")
    .WithDataVolume()
    .AddDatabase("flights_demo");

var redis = builder.AddRedis("redis");

var rabbit = builder.AddRabbitMQ("rabbitmq");

var api = builder.AddProject<Projects.FlightsPlatform_Api>("api")
    .WithReference(postgres).WithReference(redis).WithReference(rabbit)
    .WithExternalHttpEndpoints();

builder.AddProject<Projects.FlightsPlatform_NotificationWorker>("notification-worker")
    .WithReference(postgres).WithReference(rabbit);

builder.AddProject<Projects.FlightsPlatform_AnalyticsWorker>("analytics-worker")
    .WithReference(postgres).WithReference(rabbit);

builder.Build().Run();
```

Provides: Aspire dashboard with logs, traces, metrics; automatic
service discovery; connection string injection.

**Not wired into K8s** — Aspire is a local dev tool for us, not a
deployment target.

---

## 6. CI/CD

### 6.1 Helm lint job

```yaml
- name: Lint Helm chart
  run: helm lint chart/

- name: Render templates
  run: helm template flights chart/ --values chart/values-dev.yaml > /tmp/rendered.yaml

- name: Validate with kubeconform
  run: kubeconform -strict -summary /tmp/rendered.yaml
```

Runs on every push. Catches template errors before merge.

### 6.2 Optional: apply to kind in CI

```yaml
- name: Create kind cluster
  uses: helm/kind-action@v1

- name: Load images
  run: |
    docker build -t flights-api:latest -f src/Hosts/FlightsPlatform.Api/Dockerfile .
    kind load docker-image flights-api:latest
    # ... workers

- name: Helm install
  run: helm install flights ./chart -f chart/values-dev.yaml --wait --timeout 5m

- name: Smoke test
  run: |
    kubectl wait --for=condition=Ready pod -l app.kubernetes.io/component=api --timeout=120s
    kubectl port-forward svc/api 8080:8080 &
    sleep 5
    curl -f http://localhost:8080/health/ready
```

Optional because it makes CI slower (2-3 min). Can be gated to
push-on-main only.

---

## 7. Dockerfile for API

New file: `src/Hosts/FlightsPlatform.Api/Dockerfile` — same
multi-stage pattern as workers.

Entry: `ENTRYPOINT ["dotnet", "FlightsPlatform.Api.dll"]`
Ports: 8080 (HTTP), 8081 (HTTPS in dev — not used in K8s).

HTTPS is terminated by Ingress; inside the cluster, HTTP only.

---

## 8. Testing Strategy

### 8.1 Chart tests

- `helm lint` on every change.
- `helm template` + `kubeconform` in CI.
- `helm install --dry-run --debug` manual check.

### 8.2 Smoke test in kind

- Deploy chart to kind.
- Port-forward API service.
- Hit `/health/ready` — expect 200.
- Run a booking flow via API — expect success.
- Check that a trace appears in Jaeger.

### 8.3 Manual verification (portfolio screenshots)

- `kubectl get pods -n flights-platform` — all Running.
- `kubectl get svc`, `kubectl get ingress`.
- Grafana screenshot with data from the K8s-deployed API.
- Jaeger screenshot with trace from K8s-deployed API.

---

## 9. Tasks

### 9.1 Script 8.1 — Docker image for API + Helm chart scaffold

- T-01 Dockerfile for FlightsPlatform.Api (multi-stage, alpine).
- T-02 Chart.yaml, values.yaml, values-dev.yaml, _helpers.tpl.
- T-03 Templates: api.yaml, notification-worker.yaml, analytics-worker.yaml.
- T-04 Templates: postgres.yaml, redis.yaml, rabbitmq.yaml.
- T-05 Templates: jaeger.yaml, prometheus.yaml, grafana.yaml.
- T-06 Templates: configmaps.yaml, secrets.yaml.
- T-07 Templates: ingress.yaml, hpa.yaml.
- T-08 ADR-017: Helm as the packaging format, K8s as the target.
- T-09 ADR-018: Aspire as local dev orchestrator.

### 9.2 Script 8.2 — Deploy to kind + smoke test

- T-10 Script: create kind cluster, load images, helm install.
- T-11 Script: port-forward + smoke test (health + booking flow).
- T-12 Script: teardown (helm uninstall, kind delete).
- T-13 README: "Running on Kubernetes" section.
- T-14 docs/kubernetes.md with troubleshooting.

### 9.3 Script 8.3 — Aspire AppHost

- T-15 FlightsPlatform.AppHost project.
- T-16 FlightsPlatform.ServiceDefaults (Aspire default).
- T-17 Wire all services into the AppHost.
- T-18 README: "Running with Aspire" section.
- T-19 Screenshot of Aspire dashboard.

### 9.4 Script 8.4 — CI Helm lint job

- T-20 Add helm lint job to .github/workflows/ci.yml.
- T-21 Add kubeconform validation.
- T-22 (Optional) kind deploy job gated to main.

---

## 10. Out of Scope

- Multi-cluster deployment.
- Service mesh (Istio, Linkerd).
- mTLS between services.
- External secrets manager (Vault, Sealed Secrets).
- Managed services (RDS, ElastiCache, AmazonMQ).
- KEDA queue-based autoscaling.
- Cross-region failover.
- Cluster provisioning (kubeadm, kops, EKS).

---

## 11. Acceptance Criteria

- `helm lint chart/` passes.
- `helm template chart/ --values chart/values-dev.yaml | kubeconform -strict -` passes.
- `helm install flights chart/ -f chart/values-dev.yaml` into a kind
  cluster succeeds.
- All pods reach `Running` and pass readiness within 2 minutes.
- `curl http://api.flights.local/health/ready` returns 200 (with
  `/etc/hosts` entry).
- A full booking flow via the ingress works end-to-end.
- Traces appear in Jaeger from the K8s-deployed API.
- Business metrics appear in Prometheus from the K8s-deployed API.
- HPA scales the notification worker from 1 to 3 replicas under load.
- `dotnet run --project src/Aspire/FlightsPlatform.AppHost` starts
  the full stack locally with the Aspire dashboard.
- ADR-017 and ADR-018 committed.
- README updated with K8s and Aspire sections.

---

## 12. Open Questions

- **Q1:** kind or Docker Desktop K8s?
  *Decision: support both. Scripts default to kind (faster startup,
  easier cleanup). README documents both.*

- **Q2:** Ingress controller — nginx-ingress or Traefik?
  *Decision: nginx-ingress. Most common in tutorials and easier to
  troubleshoot.*

- **Q3:** Do we publish images to GHCR in CI?
  *Decision: no. Images loaded locally into kind. Adding GHCR is a
  one-line change when needed. Avoids registry credentials in CI.*

- **Q4:** Should Aspire replace docker-compose?
  *Decision: no. Both stay. docker-compose is the "closest to prod"
  option; Aspire is the "developer productivity" option.*

- **Q5:** HPA metrics — CPU only or custom queue-depth?
  *Decision: CPU only for Phase 8. KEDA + RabbitMQ queue depth
  documented as a future enhancement.*

---

## 13. References

- ADR-001 Modular monolith
- ADR-013 Event-driven integration
- ADR-015 OpenTelemetry standard
- ADR-016 Observability stack choice
- SPEC-007 Observability
- Helm docs: https://helm.sh/docs/
- kind: https://kind.sigs.k8s.io/
- .NET Aspire: https://learn.microsoft.com/dotnet/aspire/