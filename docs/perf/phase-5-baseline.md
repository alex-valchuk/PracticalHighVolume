# Phase 5 performance baseline

All measurements on the same machine, against the same Postgres
(`flights_demo`) with the airport sync already run.

Method: 200 sequential requests, p50/p95/p99 of end-to-end latency in ms.

## Endpoint: GET /flight-catalog/airports/{code} (e.g. SVO)

| Date       | Build                          | p50  | p95  | p99  | Notes |
| ---------- | ------------------------------ | ---- | ---- | ---- | ----- |
| TODO       | before caching                 |      |      |      |       |
| TODO       | after Redis caching (Phase 5.1)|      |      |      |       |

## How to measure

Use `curl` in a loop, or `hey` / `bombardier`:

    bombardier -n 200 -c 10 http://localhost:50943/flight-catalog/airports/SVO

Paste the p50/p95/p99 numbers here after each run.