---
name: repo-cleanup-powerShell-removal
description: Guide for removing PowerShell usage track from this repo (scripts, docs) and replacing with cross-platform instructions.
---

## When to use
Use when the task is to eliminate PowerShell (`.ps1`) scripts and PowerShell-first documentation from this repository on the current branch.

## Steps
1. Inventory all `*.ps1` files and references in docs/CI/config.
2. For each script, decide: delete, or replace behavior with documented shell commands (Docker/Makefile not present; prefer direct commands).
3. Update docs: `README.md`, `docs/quickstart.md`, `docs/environments.md`, `frontend/README.md`, and any others found.
4. Ensure no new PowerShell instructions are added; follow `.opencode/rules/no-powershell.md`.
5. Summarize removals and replacements in the relevant task file under `.opencode/tasks/`.

## Notes for this repo (known)
- `scripts/dev-local.ps1`, `scripts/dev-k8s.ps1`, `scripts/stop-local.ps1`, `scripts/stop-k8s.ps1` exist and are referenced by docs.
- `run-from-clipboard.ps1` and other `*.ps1` at repo root may exist (verify before deleting).
- Prefer documenting:
  - `docker compose up -d` / `docker compose down`
  - `dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https`
  - `cd frontend && npm install && npm start` (or `npm run dev:*` if kept but make them cross-platform carefully)
