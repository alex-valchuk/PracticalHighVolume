# ADR-009: Angular SPA alongside .NET API

## Status
Accepted

## Context
The platform exposes two bounded contexts (FlightCatalog, Bookings) via REST.
Manual testing through Scalar covers single requests but is clumsy for the
multi-step booking saga (create -> add ticket -> confirm). We need a
user-facing UI to:
1. Exercise end-to-end flows.
2. Demonstrate saga compensations visually.
3. Show a complete frontend + backend integration for portfolio purposes.

## Decision
Build a standalone Angular SPA in `frontend/` at the repository root.

### Key choices

1. **Framework: Angular (latest stable, standalone APIs)**.
   TypeScript-first, DI, RxJS, and CLI match backend concepts.
   Opinionated structure reduces decision fatigue.

2. **UI library: PrimeNG + PrimeFlex**.
   Data tables, dialogs, toasts, date pickers - all ready.
   Focus stays on architecture, not CSS.

3. **No NgModules; standalone components**.
   Modern Angular path. `provideRouter`, `provideHttpClient`,
   `providePrimeNG` in `app.config.ts`.

4. **Zoneless change detection**.
   `provideZonelessChangeDetection()`. Signals drive UI updates.

5. **Dev proxy, not CORS**.
   `proxy.conf.json` maps `/api` to `https://localhost:50943`.
   CORS policy "frontend" is enabled on the backend only for Development.

6. **Feature folder per bounded context**.
   `features/airports`, `features/flights`, `features/bookings`,
   `features/dashboard`. Symmetric with backend modules.

7. **No NgRx / Akita (yet)**.
   Services with RxJS `BehaviorSubject` and Angular `signal` cover our needs.
   Global state library would be premature.

8. **API types are hand-written**.
   `core/api/models/*.ts` mirror the backend DTOs.
   OpenAPI code generation deferred.

9. **Admin endpoints for demo**.
   `/admin/payment/simulate-failure` toggles a runtime flag that makes the
   next confirm trigger saga compensation. Visible only in Development.

### Layout

    frontend/
      src/app/
        core/
          api/          <- ApiService, error interceptor, models
          services/     <- ThemeService, HealthService
          layout/       <- Shell, Sidebar, Header
        shared/         <- (reserved)
        features/
          dashboard/
          airports/
          flights/
          bookings/

## Consequences

Positive:
- End-to-end flows are demonstrable in a browser.
- Saga compensations visible to a human observer.
- Portfolio shows frontend + backend integration.

Negative:
- Two toolchains (dotnet + npm) in one repository.
- Two CI jobs (backend and frontend).
- Slightly more setup for a new contributor.

## Alternatives considered
- **React / Vue**: less aligned with enterprise .NET shops.
- **Server-side Razor Pages**: simpler, but loses the SPA demonstration.
- **Blazor WASM**: interesting, but the goal was to show we can work with
  a mainstream frontend stack, not just .NET everywhere.

## References
- SPEC-004 (Angular SPA spec)
- ADR-001 (Modular monolith)
- ADR-005 (Bookings as a separate bounded context)
- ADR-006 (Saga orchestration)