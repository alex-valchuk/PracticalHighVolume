# Rule: Architecture boundaries (modular monolith)

- Respect module boundaries: `Domain` must not depend on EF Core, ASP.NET, or Infrastructure.
- No cross-module `Domain` references. Cross-module calls must go through interfaces declared in the caller's `Application` layer, implemented in the caller's `Infrastructure`.
- Keep CQRS pattern: reads with Dapper, writes with EF Core (follow existing module patterns).
- External integration (`bookings.*` schema) remains read-only via ACL + polling/sync patterns already present.
- Prefer Minimal API endpoint mapping patterns in `*.Api` and composition/wiring in the host (`src/Hosts/FlightsPlatform.Api`).
