# Instructions for agents working in this repo

## Read first
- `AGENTS.md` (root)
- `README.md`
- Relevant ADRs in `docs/adr/` before significant structural decisions

## Working style
- Make small, reviewable changes.
- Preserve existing code style and folder layout.
- Avoid introducing new tooling unless necessary and documented.
- Do not add PowerShell-first docs or scripts.

## Documentation changes
- When updating runbooks, prefer commands that run in bash-compatible shells and match CI.
- If removing scripts, also remove or rewrite references in `README.md`, `docs/quickstart.md`, `docs/environments.md`, `frontend/README.md`, and any other docs found via search.

## Tasks
- Track actionable work items in `.opencode/tasks/` as Markdown files (e.g., `task-001-...md`).
- Each task should include: Goal, Scope, Checklist, and Notes/risks.
