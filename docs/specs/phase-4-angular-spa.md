# SPEC-004: Angular SPA for Flights Platform

| Field           | Value                                    |
|-----------------|------------------------------------------|
| Spec ID         | SPEC-004                                 |
| Status          | Draft - awaiting approval                |
| Phase           | 4                                        |
| Created         | 2026-09-16                               |
| Depends on      | SPEC-003.2 (Booking Saga)                |
| Blocks          | SPEC-005 (Redis + Performance)           |

---

## Phase Map (after renumbering)

| Phase | Focus                                    | Spec ID    |
|-------|------------------------------------------|------------|
| 1     | Domain + Clean Architecture (FlightCatalog) | SPEC-001 |
| 2     | Integration with bookings via ACL        | SPEC-002   |
| 3     | Bookings module + Saga                   | SPEC-003   |
| 4     | **Angular SPA** (this spec)              | SPEC-004   |
| 5     | Redis + Performance                      | SPEC-005   |
| 6     | Event-driven (RabbitMQ + Outbox)         | SPEC-006   |
| 7     | Observability (OTel + Grafana + Prom)    | SPEC-007   |
| 8     | Container + Kubernetes + Aspire          | SPEC-008   |
| 9     | Polish + demo scenarios                  | SPEC-009   |

---

## 1. Context

### 1.1 Current state
- Two bounded contexts (FlightCatalog, Bookings) exposed via REST API.
- API documented with OpenAPI, browsable through Scalar.
- No user-facing UI. Manual testing is done via Scalar.
- Multi-step scenarios (create booking -> add tickets -> confirm) are
  cumbersome to exercise without a UI.

### 1.2 Goal
Build an Angular Single Page Application that:
1. Exercises the full user journey across both bounded contexts.
2. Demonstrates real-world SPA architecture (lazy routes, typed services,
   interceptors, guards, environment config).
3. Makes the saga compensation behaviour visible to a human observer.
4. Becomes a portfolio piece showing frontend + backend integration.

### 1.3 Why this matters
- Interviewers expect a senior .NET developer to be able to work alongside
  frontend teams. A working SPA proves this.
- A live demo of the compensation flow (payment declined -> booking Expired)
  in a UI is far more compelling than raw curl commands.
- Angular specifically is the most common enterprise SPA framework in .NET
  shops; it also maps cleanly onto backend concepts (DI, modules, RxJS).

---

## 2. Requirements

### 2.1 Functional

| ID      | Requirement                                                                     |
|---------|---------------------------------------------------------------------------------|
| FR-01   | Dashboard shows counts: flights, airports, bookings, active bookings.           |
| FR-02   | Airports page lists all airports with search; button triggers sync.             |
| FR-03   | Flights page lists flights with filters; create / delay / cancel from UI.       |
| FR-04   | Bookings page lists bookings; create, add tickets, confirm, cancel.             |
| FR-05   | Booking details show saga result including compensations when they happen.      |
| FR-06   | Global snackbar for API errors and successes.                                    |
| FR-07   | Loading states on every async action (no "frozen" UI).                           |
| FR-08   | Light/dark theme switch persisted across sessions.                               |
| FR-09   | Health indicator in header shows whether API is reachable.                       |

### 2.2 Non-functional

| ID      | Requirement                                                                     |
|---------|---------------------------------------------------------------------------------|
| NFR-01  | All HTTP calls are typed and go through a single `ApiService`.                   |
| NFR-02  | No `any` in application code (strict TypeScript).                                |
| NFR-03  | Feature routes are lazy-loaded.                                                  |
| NFR-04  | Errors from API (ProblemDetails-like) are surfaced with `error` and `code`.      |
| NFR-05  | Environment file controls API base URL (no hard-coded hosts).                    |
| NFR-06  | `ng build` produces zero TypeScript and ESLint errors.                           |
| NFR-07  | Dev proxy handles `/api` -> .NET API so no CORS in dev.                          |

---

## 3. Architecture Decisions

### AD-1: Angular (latest stable), standalone APIs, no NgModules
Standalone components, `provideRouter`, `provideHttpClient` are the modern
Angular path. No NgModule boilerplate.

### AD-2: PrimeNG + PrimeFlex for UI
PrimeNG provides data tables, dialogs, toasts, and theming out of the box.
PrimeFlex for layout. This keeps the focus on architecture, not CSS.

### AD-3: Single feature folder per bounded context
`features/airports`, `features/flights`, `features/bookings`, `features/dashboard`.
Each feature has its own route file, services, models, components.

### AD-4: API contract types are manually maintained
A dedicated `core/api/models` folder with interfaces mirroring the backend
DTOs. Code generation from OpenAPI is out of scope for this phase; may be
added later as `openapi-generator-cli`.

### AD-5: Dev proxy, not CORS, in development
Angular dev server proxies `/api` to `https://localhost:50943`. CORS is
configured on the backend for production-like scenarios only.

### AD-6: One component per page + small presentational components
Pages are smart (inject services, orchestrate); child components are dumb
(inputs/outputs only). Encourages testability and reuse.

### AD-7: No global state library (NgRx / Akita) yet
Services with RxJS `BehaviorSubject` cover our needs. NgRx would be
justified only when cross-feature state grows.

### AD-8: Theme switch via PrimeNG theme tokens + localStorage
Light and dark themes are two CSS files from PrimeNG. A `ThemeService`
swaps the stylesheet link and persists the choice.

---

## 4. Project Structure

    frontend/
    в”њв”Ђв”Ђ angular.json
    в”њв”Ђв”Ђ package.json
    в”њв”Ђв”Ђ proxy.conf.json
    в”њв”Ђв”Ђ tsconfig.json
    в”њв”Ђв”Ђ .eslintrc.json
    в”њв”Ђв”Ђ src/
    в”‚   в”њв”Ђв”Ђ main.ts
    в”‚   в”њв”Ђв”Ђ index.html
    в”‚   в”њв”Ђв”Ђ styles.scss
    в”‚   в”њв”Ђв”Ђ environments/
    в”‚   в”‚   в”њв”Ђв”Ђ environment.ts
    в”‚   в”‚   в””в”Ђв”Ђ environment.production.ts
    в”‚   в””в”Ђв”Ђ app/
    в”‚       в”њв”Ђв”Ђ app.config.ts
    в”‚       в”њв”Ђв”Ђ app.routes.ts
    в”‚       в”њв”Ђв”Ђ app.component.ts
    в”‚       в”њв”Ђв”Ђ core/
    в”‚       в”‚   в”њв”Ђв”Ђ api/
    в”‚       в”‚   в”‚   в”њв”Ђв”Ђ api.service.ts
    в”‚       в”‚   в”‚   в”њв”Ђв”Ђ models/
    в”‚       в”‚   в”‚   в”‚   в”њв”Ђв”Ђ airport.model.ts
    в”‚       в”‚   в”‚   в”‚   в”њв”Ђв”Ђ flight.model.ts
    в”‚       в”‚   в”‚   в”‚   в”њв”Ђв”Ђ booking.model.ts
    в”‚       в”‚   в”‚   в”‚   в””в”Ђв”Ђ api-error.model.ts
    в”‚       в”‚   в”‚   в””в”Ђв”Ђ error.interceptor.ts
    в”‚       в”‚   в”њв”Ђв”Ђ services/
    в”‚       в”‚   в”‚   в”њв”Ђв”Ђ theme.service.ts
    в”‚       в”‚   в”‚   в””в”Ђв”Ђ health.service.ts
    в”‚       в”‚   в””в”Ђв”Ђ layout/
    в”‚       в”‚       в”њв”Ђв”Ђ shell.component.ts
    в”‚       в”‚       в”њв”Ђв”Ђ sidebar.component.ts
    в”‚       в”‚       в””в”Ђв”Ђ header.component.ts
    в”‚       в”њв”Ђв”Ђ shared/
    в”‚       в”‚   в”њв”Ђв”Ђ components/
    в”‚       в”‚   в”‚   в”њв”Ђв”Ђ page-header.component.ts
    в”‚       в”‚   в”‚   в”њв”Ђв”Ђ loading-spinner.component.ts
    в”‚       в”‚   в”‚   в””в”Ђв”Ђ empty-state.component.ts
    в”‚       в”‚   в””в”Ђв”Ђ pipes/
    в”‚       в”‚       в””в”Ђв”Ђ money.pipe.ts
    в”‚       в””в”Ђв”Ђ features/
    в”‚           в”њв”Ђв”Ђ dashboard/
    в”‚           в”њв”Ђв”Ђ airports/
    в”‚           в”њв”Ђв”Ђ flights/
    в”‚           в””в”Ђв”Ђ bookings/

---

## 5. Backend Changes Required

### 5.1 CORS policy
Add CORS for `http://localhost:4200` (Angular dev server) in host `Program.cs`.
Applied only in Development environment.

### 5.2 Health endpoint
Add `GET /health` returning `{ status: "ok", time: ... }`.
Used by the header health indicator.

### 5.3 Dashboard endpoints
Add lightweight aggregate endpoints to avoid N calls from the browser:

    GET /dashboard/summary
      -> {
           flights: 12,
           airports: 104,
           bookings: 7,
           activeBookings: 3
         }

Implemented as a query in the host (thin composition layer), calling
`IMediator` for existing queries or a small Dapper read.

---

## 6. API Contracts Consumed by UI

| Method | Path                                  | Used by           |
|--------|---------------------------------------|-------------------|
| GET    | /health                               | Header indicator  |
| GET    | /dashboard/summary                    | Dashboard         |
| GET    | /flight-catalog/airports              | Airports page     |
| GET    | /flight-catalog/airports/{code}       | Booking details   |
| POST   | /flight-catalog/airports/sync         | Airports page     |
| GET    | /flight-catalog/flights               | Flights page      |
| GET    | /flight-catalog/flights/{id}          | Flight details    |
| POST   | /flight-catalog/flights               | Flights page      |
| POST   | /flight-catalog/flights/{id}/delay    | Flights page      |
| POST   | /flight-catalog/flights/{id}/cancel   | Flights page      |
| GET    | /bookings/{id}                        | Booking details   |
| POST   | /bookings                             | Bookings page     |
| POST   | /bookings/{id}/tickets                | Booking details   |
| POST   | /bookings/{id}/confirm                | Booking details   |
| POST   | /bookings/{id}/cancel                 | Booking details   |

---

## 7. Testing Strategy

### 7.1 Unit tests
- `ApiService` error handling: HTTP 400 with `{ error, code }` -> throws
  `ApiError` with both fields.
- `ThemeService`: toggle persists to localStorage; restore on init.

### 7.2 Component tests
- `AirportsPage`: renders table from mocked service; sync button calls service.
- `BookingDetailsPage`: confirm button calls service and reflects result.

### 7.3 No e2e in this phase
Playwright / Cypress deferred to Phase 9.

---

## 8. Tasks

### 8.1 Script 4.1 - Foundation
- T-01 Scaffold Angular project (`ng new` with standalone, routing, SCSS).
- T-02 Install PrimeNG, PrimeFlex, primeicons.
- T-03 Configure `proxy.conf.json` for `/api` and `/health` and `/dashboard`.
- T-04 Environments: dev points to `http://localhost:50943` via proxy.
- T-05 Add CORS to backend host (Development only).
- T-06 Add `GET /health` endpoint.
- T-07 Add `GET /dashboard/summary` endpoint.
- T-08 Shell layout: sidebar + header, 4 routes, lazy-loaded.
- T-09 `ApiService` (typed `get/post` with generic returns).
- T-10 `ApiErrorInterceptor` mapping backend errors to `ApiError`.
- T-11 `ThemeService` with light/dark toggle + localStorage.
- T-12 `HealthService` + header status indicator.
- T-13 Update README with frontend section.

### 8.2 Script 4.2 - Airports + Flights
- T-14 Airports page: table, search, "Sync now" button.
- T-15 Flights page: table, filters, "Create flight" dialog.
- T-16 Delay / cancel actions with confirmation dialogs.
- T-17 Snackbar feedback on success/error.
- T-18 Component tests for Airports and Flights pages.

### 8.3 Script 4.3 - Bookings + Saga demo
- T-19 Bookings page: table, "Create booking" dialog.
- T-20 Booking details: tickets list, add ticket dialog.
- T-21 Confirm button with saga result panel (steps + compensations).
- T-22 Cancel button with reason dialog.
- T-23 "Demo: simulate failure after charge" toggle (calls a new backend
  endpoint that flips `Payment.SimulateFailureAfterCharge` for the running
  process; visible only in Development).
- T-24 Component tests for Bookings and Booking details.

### 8.4 Script 4.4 - Polish
- T-25 Empty states, loading states.
- T-26 README screenshots.
- T-27 ADR-009: Angular SPA alongside .NET API.
- T-28 `ng build` in CI (new job in `.github/workflows/ci.yml`).

---

## 9. Out of Scope
- Authentication / login (Phase 5 or later).
- OpenAPI code generation.
- e2e tests (Phase 9).
- Containerization of frontend (Phase 8).
- Advanced state management (NgRx) вЂ” deferred.
- Internationalization (i18n) вЂ” deferred.
- Accessibility audit вЂ” deferred.

---

## 10. Acceptance Criteria

- `npm install && npm start` starts Angular on `http://localhost:4200`.
- Backend running on `https://localhost:50943` via `dotnet run`.
- Header shows green API status when backend is up, red when down.
- User can complete the entire journey:
  sync airports -> view them -> create flight -> create booking ->
  add ticket -> confirm -> see status flip to Confirmed.
- User can switch theme; reload preserves choice.
- User can trigger compensation via "Simulate failure" toggle and see
  the booking become Expired in UI with a visible compensation panel.
- `ng build --configuration production` succeeds with no errors.
- `ng test` passes all unit and component tests.
- CI: new job runs `npm ci && npm run lint && npm test -- --watch=false`.
- README updated with screenshots and a "Running the frontend" section.
- ADR-009 committed.

---

## 11. Open Questions
- Q1: Should we show raw backend field names or prettified labels?
  *Decision: prettified. Add a small label map per entity.*
- Q2: How to show multi-step saga progress?
  *Decision: timeline component from PrimeNG (Timeline) with per-step
  status derived from the API response and the booking state.*
- Q3: Do we add a "seed demo data" button?
  *Decision: yes, later, in Phase 4.4 polish. Creates a flight + a booking
  in one click for smooth demos.*
- Q4: Should the frontend live inside the .NET solution folder?
  *Decision: no. `frontend/` at the repository root. Keeps toolchains
  independent and CI jobs simple.*

---

## 12. References
- ADR-001 Modular monolith
- ADR-005 Bookings bounded context
- ADR-006 Saga orchestration
- SPEC-005 Redis caching (next phase)
- Angular style guide: https://angular.dev/style-guide
- PrimeNG: https://primeng.org/