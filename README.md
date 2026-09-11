# Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         API Gateway / BFF                           │
│                    (ASP.NET Core, Minimal API, YARP)                │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  Flight       │  │  Booking      │  │  Pricing      │
│  Catalog      │  │  Service      │  │  Service      │
│  Service      │  │               │  │               │
│  (CQRS, Redis)│  │ (CQRS, Saga)  │  │ (CQRS, Redis) │
└───────┬───────┘  └───────┬───────┘  └───────┬───────┘
        │                  │                  │
        │    ┌─────────────┼──────────────────┤
        │    │             │                  │
        ▼    ▼             ▼                  ▼
┌────────────────────────────────────────────────────────┐
│              RabbitMQ / MassTransit                     │
│         (Event Bus: BookingCreated, FlightDelayed,      │
│          PaymentProcessed, BookingCancelled)            │
└────────────────────────┬───────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
┌───────────────┐  ┌───────────────┐  ┌───────────────┐
│  Notification │  │  Analytics    │  │  Payment      │
│  Worker       │  │  Worker       │  │  Simulator    │
│  (Background) │  │  (Background) │  │  (Background) │
└───────────────┘  └───────────────┘  └───────────────┘

        ┌────────────────────────────────────────────┐
        │         Infrastructure Layer                │
        │  PostgreSQL (demo) │ Redis │ RabbitMQ       │
        │  MongoDB (audit)   │ Docker│ Kubernetes     │
        │  OpenTelemetry     │ Grafana│ Prometheus    │
        └────────────────────────────────────────────┘
```

# Actors

| Solution      | Reason |
| ------------- | ------------- |
| CQRS                    | Read (flight search) and write (booking) operations have different workloads and data models     |
| MediatR                 | Separation of commands and queries; pipeline behaviors for logging/validation     |
| Clean Architecture      | Domain is independent of infrastructure; easy to test     |
| MassTransit + RabbitMQ  | Asynchronous processing: notifications, analytics, and payments do not block the API |
| Redis                   | Caching popular flights; distributed locking during booking  |
| MongoDB                 | Event audit log (append-only, unstructured payloads) |
| Docker + K8s            | Environment reproducibility; worker scaling  |
| OpenTelemetry + Grafana | Observability: traces, metrics, and logs  |


# SQL Database

1. Go to https://edu.postgrespro.ru/
2. Download demo-big.zip (or demo-medium.zip or demo-small.zip)
3. Run Powershell and go to the folder with downloaded file
4. Execute *docker cp .\postgres-demo-big.zip flights-postgres:/tmp/*
5. Ensure to get *Successfully copied (X)MB (transferred (X)MB) to flights-postgres:/tmp/*
6. Execute *docker exec -i flights-postgres bash -c "unzip -p /tmp/postgres-demo-big.zip | psql -U flights -d postgres"*
7. Ensure to get a long list of successfull database creation commands log
