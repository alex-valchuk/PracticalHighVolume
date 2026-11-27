# Rule: No new PowerShell-centric workflows

- Do not introduce new PowerShell (`.ps1`) scripts.
- Existing helper scripts under `scripts/*.ps1` may remain because they are convenient; keep docs accurate about them.
- Prefer cross-platform commands in docs (e.g., `docker compose ...`, `dotnet ...`, `npm ...`) as the default narrative where practical.
- If a step is Windows/PowerShell-specific, label it clearly and provide context; avoid making PowerShell the only documented path for common tasks.

Rationale: keep onboarding portable while respecting established local helper scripts.
