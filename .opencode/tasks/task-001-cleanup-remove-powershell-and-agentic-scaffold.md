# Task 001 — Cleanup: remove PowerShell usage track + agentic scaffold

## Goal
Tidy this repository for agentic development and “dive deeper into microservices/agentic engineering” by:
- Establishing `AGENTS.md` (done in this branch/setup step).
- Establishing `.opencode/` scaffolding (rules, instructions, skills, tasks) (done in this branch/setup step).
- Removing the PowerShell usage track from the current branch state where reasonable (delete/retire PowerShell scripts and update docs to cross-platform commands).
- Producing a clear record of what changed/was removed.

## Scope
In scope:
- Repository root and docs under `docs/`, `frontend/README.md`, `README.md` as they relate to local/dev/K8s run instructions that mention PowerShell.
- `scripts/*.ps1` and any other `*.ps1` files in the repo (verify inventory).
- `.github/workflows/*` (ensure no PowerShell steps introduced; adjust only if they reference removed scripts/flows).
- Add/adjust notes in docs to be cross-platform (bash + Docker + dotnet + npm). If a step is Windows-only, state it explicitly and provide alternatives where possible.

Out of scope (unless required):
- Changing application/runtime behavior (backend/frontend code) beyond docs/config needed to remove PowerShell references.
- Large refactors unrelated to cleanup.

## Inventory (current known PowerShell touchpoints)
Verify with a repo search (example): `rg -n "\.ps1|powershell|pwsh"` (or equivalent). Known items from repo inspection:
- `scripts/dev-local.ps1`
- `scripts/dev-k8s.ps1`
- `scripts/stop-local.ps1`
- `scripts/stop-k8s.ps1`
- `run-from-clipboard.ps1` (repo root) — confirm purpose; remove if it is a one-off helper not needed.
- `README.md` mentions (search for `scripts/dev-local.ps1`, `scripts/dev-k8s.ps1`, `scripts/stop-local.ps1`, `scripts/stop-k8s.ps1`, “PowerShell” text).
- `docs/quickstart.md` describes running the above `.ps1` scripts.
- `docs/environments.md` describes PowerShell-based K8s helper flow and may mention editing hosts via Notepad steps (keep those if still valid, but avoid PowerShell-first phrasing where possible).
- `frontend/README.md` uses PowerShell-style env setting examples like `$env:API_TARGET=...` (replace with cross-platform examples: bash `export ...`, PowerShell shown only as an alternative note if desired, or prefer a single cross-platform approach).
- `.vscode/` or other editor configs: only touch if they reference removed scripts.

## Checklist
- [ ] Run a full inventory of `*.ps1` files and all textual references (`powershell`, `pwsh`, `.ps1`).
- [ ] Decide per-file action:
  - Delete obsolete helper scripts under `scripts/` if their workflow is replaced by documented commands.
  - Delete root `run-from-clipboard.ps1` if it is not used (confirm first).
- [ ] Update `docs/quickstart.md`:
  - Remove instructions to run `scripts/*.ps1`.
  - Provide cross-platform step-by-step commands for “Local environment”, “Kubernetes environment”, and “Switching” (or clearly mark Windows-only notes, but default to portable commands).
- [ ] Update `docs/environments.md`:
  - Replace PowerShell script references with direct commands (docker/kubectl/helm/dotnet/npm) equivalent to current scripts.
  - Keep Kubernetes first-time setup accurate; adjust host-edit instructions to be OS-agnostic guidance (edit hosts file) without requiring PowerShell.
- [ ] Update `README.md`:
  - Remove or rewrite any section that points to `scripts/*.ps1` (e.g., “Helper scripts” section) to point to `docs/quickstart.md` / direct commands.
- [ ] Update `frontend/README.md`:
  - Replace `$env:API_TARGET=...` examples with cross-platform guidance (e.g., `API_TARGET=... npm run ...` on bash, and mention PowerShell as optional alternative in a short note if truly needed).
- [ ] Search and clean any remaining references in `docs/` (including `docs/specs/*`, `docs/backlog/*`) if they are part of “current branch state” guidance; avoid editing historical ADRs unless they contain active how-to instructions that are misleading.
- [ ] Ensure `.opencode/rules/no-powershell.md` is respected going forward.
- [ ] Validate docs readability: commands are copy-pasteable in bash; note Windows cmd caveats only when necessary.
- [ ] Summarize changes in this task file under “Execution notes” (what removed, what replaced, any remaining intentional exceptions).

## Proposed replacement approach (guidance)
- Local dev:
  - `docker compose up -d`
  - run API via IDE or `dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https`
  - frontend: `cd frontend && npm install && npm start` (or documented npm scripts)
- Stop local: `docker compose down`
- K8s flow: document the explicit sequence (mirroring current script intent):
  - `docker compose down`
  - verify cluster/context, build images, `kind load docker-image ...`, `helm upgrade --install ... -f chart/values-dev.yaml -n flights-platform --create-namespace`, `kubectl get pods -n flights-platform`
- For env vars in frontend commands, prefer POSIX form in docs and add a one-line note: on PowerShell use `$env:API_TARGET="..."`.

## Notes / risks
- `scripts/*.ps1` may encode small waits/checks (e.g., sleep, health polling notes). Preserve intent in docs.
- K8s script does image load verification via `docker exec ... crictl ...`; keep that guidance if helpful, but translate to cross-platform instructions.
- Do not delete files outside repo root unless necessary; confirm paths before removal.
- This is a “current branch state” cleanup request: focus on making the repo not rely on PowerShell track going forward.

## Execution notes (updated after correction)

- User correction: the four helper scripts under `scripts/` (`dev-local.ps1`, `dev-k8s.ps1`, `stop-local.ps1`, `stop-k8s.ps1`) are **kept** (useful/convenient). Do **not** remove them.
- Files removed earlier in this task and **restored**:
  - `scripts/dev-local.ps1`, `scripts/dev-k8s.ps1`, `scripts/stop-local.ps1`, `scripts/stop-k8s.ps1` (restored)
- Files removed (still removed unless you want them back):
  - `run-from-clipboard.ps1` (repo root) — removed earlier; only re-add if needed.
- Docs adjusted to keep script-based guidance:
  - `README.md` “Environments”: documents `scripts/*.ps1` helpers (PowerShell) alongside notes.
  - `docs/quickstart.md`: restored script-first shortcuts.
  - `docs/environments.md`: keeps “prefer helper scripts” note.
  - `frontend/README.md`: still includes an optional PowerShell note for `API_TARGET` in-session (acceptable as an alternative), primary examples can be bash-style in practice; no script removals tied to this correction.
- Remaining guidance:
  - Keep `AGENTS.md` and `.opencode/` scaffolding.
  - Avoid introducing *new* PowerShell-first instructions beyond keeping these existing helper scripts documented; prefer cross-platform commands in general docs where practical.
