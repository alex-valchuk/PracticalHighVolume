# Quickstart

Shortcuts for daily use. Full details in `environments.md`.

Every script lives in `scripts/` and is run from the repository root.

---

## Local environment

    .\scripts\dev-local.ps1

What it does:

1. `docker compose up -d`
2. Waits until Postgres accepts connections
3. Prints the next step (F5 in Visual Studio, then `npm run dev:local`)

Stop:

    .\scripts\stop-local.ps1

---

## Kubernetes environment

    .\scripts\dev-k8s.ps1

What it does:

1. `docker compose down`
2. Verifies the kind cluster exists
3. Builds the three application images
4. Loads them into the kind node
5. Runs `helm upgrade --install`
6. Waits for all pods to become Ready
7. Prints the next step (`npm run dev:k8s`)

Stop:

    .\scripts\stop-k8s.ps1

Deletes the Helm release and optionally the cluster.

---

## Switching

    # local -> K8s
    .\scripts\stop-local.ps1
    .\scripts\dev-k8s.ps1

    # K8s -> local
    .\scripts\stop-k8s.ps1
    .\scripts\dev-local.ps1

---

## Frontend shortcuts

The frontend has two scripts that set `API_TARGET` for you:

    cd frontend
    npm run dev:local     # target = https://localhost:50943
    npm run dev:k8s       # target = http://api.flights.local

No environment variables to remember, no proxy edits.

---

## Typical day

Morning, want to write code:

    .\scripts\dev-local.ps1
    # F5 in Visual Studio
    cd frontend; npm run dev:local

Afternoon, want to check K8s deployment:

    .\scripts\stop-local.ps1
    .\scripts\dev-k8s.ps1
    cd frontend; npm run dev:k8s

Evening, done for today:

    .\scripts\stop-k8s.ps1
    # or
    .\scripts\stop-local.ps1

---

## Full list of scripts

| Script                     | Purpose                                       |
| -------------------------- | --------------------------------------------- |
| `scripts/dev-local.ps1`    | Start local infra + print next steps          |
| `scripts/dev-k8s.ps1`      | Switch to K8s: build, load, deploy, wait      |
| `scripts/stop-local.ps1`   | Stop docker-compose                           |
| `scripts/stop-k8s.ps1`     | Remove Helm release, optionally delete cluster |