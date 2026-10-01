# Phase 9 - Extract FlightCatalog into a standalone service

## Goal
Prove the repository thesis: extraction is a deployment change, not a rewrite.

## Deliverables
- New host src/Hosts/FlightCatalog.Service.
- HttpFlightCatalogClient in Bookings.Infrastructure replacing the
  in-process implementation.
- Helm: second Deployment + Service + ingress paths.
- Aspire AppHost: two services.
- ADR-010.

## Acceptance
- git diff for *.Domain and *.Application is empty.
- SPA works without URL changes.
- Saga (happy and compensation) works across the network hop.