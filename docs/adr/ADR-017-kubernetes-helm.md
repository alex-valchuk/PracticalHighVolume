# ADR-017: Kubernetes as deployment target, Helm as packaging

## Status
Accepted

## Context
The platform runs locally with docker-compose: Postgres, Redis, RabbitMQ,
API (host), two workers (containers), Jaeger, Prometheus, Grafana. This is
fine for development, but does not reflect how the system would run in a
real production environment.

For an architect-level portfolio project, we want to demonstrate:

- Container orchestration as it is done in industry.
- Packaging and parameterized deployment.
- Health probes wired to real dependency checks.
- Horizontal scaling of stateless workers.
- Ingress for external access.

## Decision

**Kubernetes as the target runtime, Helm as the packaging format.**

1. **Kubernetes** for orchestration: Deployments for stateless workloads
   (API, workers, Jaeger, Prometheus, Grafana), StatefulSets for stateful
   services (Postgres, Redis, RabbitMQ).

2. **Helm 3** as the packaging format: one chart with multiple values
   files (`values.yaml`, `values-dev.yaml`, `values-prod.yaml`). No
   umbrella chart, no subcharts for now.

3. **Liveness and readiness probes** wired to the existing `/health/live`
   and `/health/ready` endpoints. Startup probe for slow-starting API.

4. **Horizontal Pod Autoscaler** for both workers, CPU-based, 1-5 replicas
   in dev, 2-10 in prod.

5. **Ingress (nginx)** for external access to API, Grafana, Jaeger,
   RabbitMQ UI, Prometheus.

6. **kind** as the local Kubernetes distribution for development and CI.
   Docker Desktop Kubernetes works too but kind is scriptable and faster
   to recreate.

7. **No custom operators, no service mesh.** These are production concerns
   that require infrastructure beyond the scope of this project.

## Consequences

Positive:
- All manifests are versioned, reviewable, and reproducible.
- The same chart deploys to any Kubernetes cluster (kind, EKS, AKS, GKE).
- Live demo of `kubectl get pods`, `kubectl describe`, `kubectl logs`.
- Helm values provide clear separation between dev and prod config.

Negative:
- Adds significant infrastructure complexity to a portfolio project.
- Requires Docker with sufficient resources to run a local kind cluster.
- No managed services (RDS, ElastiCache) everything runs in-cluster.

## Alternatives considered

- **Stay on docker-compose only.** Simpler, but misses the industry
  standard for production deployment. Rejected.

- **Kustomize instead of Helm.** Works, but Helm is more widespread and
  has a simpler mental model for our size of project. Rejected.

- **Nomad.** Excellent but rare in .NET shops. Rejected.

- **Managed services (RDS + ElastiCache + AmazonMQ).** More production-like,
  but makes local demo impossible and adds cloud cost. Rejected for scope.

## References
- SPEC-008
- Helm docs
- kind docs
- Kubernetes docs