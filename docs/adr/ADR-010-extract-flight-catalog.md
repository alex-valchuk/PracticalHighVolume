# ADR-010 - Extract FlightCatalog into a standalone service

## Status
Accepted (Phase 9).

## Context
Phase 8 containerised the host FlightsPlatform.Api, which still hosted
both bounded contexts (FlightCatalog and Bookings) in one process and
one Kubernetes Deployment. The repository promised "extraction is a
deployment change, not a rewrite", but the promise was untested.

## Decision
Move FlightCatalog into its own process (src/Hosts/FlightCatalog.Service)
and its own Kubernetes Deployment. Bookings calls it over HTTP through
the same IFlightCatalogClient interface declared in Bookings.Application.

## Consequences
- Domain and Application layers of both modules are unchanged.
- Only the Infrastructure layer is touched (client implementation).
- Ingress splits /api/airports and /api/flights to the new service;
  everything else under /api/* stays on FlightsPlatform.Api.
- The saga now crosses a network boundary; retries and circuit breakers
  are deferred to Phase 10.

## Why this was done here (and why it would not be done in most systems)

This repository is a **teaching artifact**. Its value is not that the
system serves traffic efficiently, but that each architectural pattern
is implemented, exercised, and documented. Phase 9 exists to prove a
specific claim made in the README since Phase 1:

> "Extraction is a deployment change, not a rewrite."

Until Phase 9 that claim was untested. Phase 9 tests it by physically
moving FlightCatalog out of the API host into its own process, and
verifies that the Domain and Application layers of both modules are
untouched. The `git diff` for this PR confirms it.

This is a **demonstration of mechanics**, not an optimisation.

## When this would be wrong

Splitting a module into a separate service in a real production system
must be justified by a concrete driver. Without one, the split adds
cost (network hop, two migration streams, two observability surfaces,
cross-service versioning) with no benefit. Extraction is the right call
when at least one of the following holds:

- **Independent deploy cadence.** The module needs to ship on a
  different schedule than the rest of the system (different team,
  different release train).
- **Independent scaling profile.** The module has a read/write or
  burst pattern that differs materially from the rest, and scaling the
  monolith scales the wrong thing.
- **Fault isolation.** A failure in the module must not take down the
  rest of the system, or vice versa.
- **Regulatory or data-residency boundary.** The module's data must
  live, be processed, or be audited under different rules.
- **Organisational boundary.** Different teams own the module and need
  a hard interface to work against.

Extraction is the wrong call when:

- The whole system is deployed together and always will be.
- One team owns all modules and one release cadence is fine.
- There is no distinct load profile, isolation requirement, or
  regulatory pressure.
- The cost of the network hop is meaningful and there is no cache or
  aggregation layer to absorb it.
- There is no operational capacity to run two services (monitoring,
  on-call, migrations, distributed tracing).

## What this phase actually bought us

- A verified boundary: Domain and Application of both modules are
  provably untouched after extraction.
- A list of hidden couplings that were not visible in the source:
  migrations run from the host, health checks against the other
  module's database, connection strings, background services,
  logging rules. Each of these had to be relocated.
- A reusable recipe for Phase 10 (extracting Bookings) and a place
  where the anti-corruption layer between two services is written
  down (the HTTP client with its own local DTO).
- A YARP reverse proxy in the host, which becomes the API Gateway in
  Phase 10.

## What this phase did not buy us

- No latency improvement. A network hop was added, not removed.
- No operational simplification. There is more to run and observe.
- No business value. No user can tell the difference.

The phase is worth keeping in the repository because it **documents
the trade-off**, not because it improves the system.