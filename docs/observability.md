# Observability

## Stack

- **Jaeger** (UI: http://localhost:16686) - distributed traces
- **Prometheus** (UI: http://localhost:9090) - metrics & alerts
- **Grafana** (UI: http://localhost:3000, admin / admin) - dashboards

## OpenTelemetry metrics - naming

OTel to Prometheus translation adds suffixes:

| OTel instrument | Prometheus metric |
|-----------------|-------------------|
| Counter `bookings.confirmed` | `bookings_confirmed_count_total` |
| Counter `bookings.expired` | `bookings_expired_count_total` |
| Counter `bookings.cancelled` | `bookings_cancelled_count_total` |
| Counter `flights.scheduled` | `flights_scheduled_count_total` |
| Histogram `saga.duration` (ms) | `saga_duration_milliseconds_count` / `_sum` / `_bucket` |
| Counter `cache.hits` | `cache_hits_count_total` |
| Counter `cache.misses` | `cache_misses_count_total` |
| ASP.NET Core request duration | `http_server_request_duration_seconds_count` / `_sum` / `_bucket` |
| .NET runtime | `dotnet_*` |

## Useful PromQL queries

Traffic:

    sum(rate(http_server_request_duration_seconds_count[1m]))

p95 latency (ms):

    histogram_quantile(0.95, sum(rate(http_server_request_duration_seconds_bucket[5m])) by (le)) * 1000

5xx ratio:

    sum(rate(http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m]))
    /
    sum(rate(http_server_request_duration_seconds_count[5m]))

Saga p95 by outcome:

    histogram_quantile(0.95, sum(rate(saga_duration_milliseconds_bucket[5m])) by (le, outcome))

Confirmed bookings per minute:

    sum(rate(bookings_confirmed_count_total[1m])) * 60

Cache hit ratio:

    sum(rate(cache_hits_count_total[5m]))
    /
    (sum(rate(cache_hits_count_total[5m])) + sum(rate(cache_misses_count_total[5m])))

## Trace structure

A single `POST /bookings/{id}/confirm` produces:

- `POST /bookings/{id}/confirm` (server, FlightsPlatform.Api)
  - `command.execute ConfirmBookingCommand` (internal, FlightsPlatform.Commands)
    - `saga.confirm_booking` (internal, FlightsPlatform.Saga)
      - `saga.step.verify_and_reserve`
      - `saga.step.charge_payment`
      - `saga.step.confirm`
        - `MassTransit: publish BookingConfirmed` (producer)
- `booking-confirmed` (consumer, FlightsPlatform.NotificationWorker)
- `booking-confirmed-audit` (consumer, FlightsPlatform.AnalyticsWorker)

Span kind values: `server`, `client`, `producer`, `consumer`, `internal`.
Service identity lives in the `service.name` resource attribute, not in span kind.