# Environments

How to run the platform in each supported environment.

All commands assume the current directory is the repository root unless
stated otherwise.

> For daily use, prefer the helper scripts. See `quickstart.md`.

---

## URLs

### Local (docker-compose)

| Service    | URL                                | Credentials    |
| ---------- | ---------------------------------- | -------------- |
| SPA        | http://localhost:4200              | -              |
| API        | https://localhost:50943/scalar/v1  | -              |
| Jaeger     | http://localhost:16686             | -              |
| Prometheus | http://localhost:9090              | -              |
| Grafana    | http://localhost:3000              | admin / admin  |
| RabbitMQ   | http://localhost:15672             | guest / guest  |

### Kubernetes (kind)

| Service    | URL                                 | Credentials    |
| ---------- | ----------------------------------- | -------------- |
| SPA        | http://localhost:4200               | -              |
| API        | http://api.flights.local/scalar/v1  | -              |
| Jaeger     | http://jaeger.flights.local         | -              |
| Prometheus | http://prometheus.flights.local     | -              |
| Grafana    | http://grafana.flights.local        | admin / admin  |
| RabbitMQ   | http://rabbit.flights.local         | guest / guest  |

---

## Local environment

Backend runs from the IDE, infrastructure runs in docker-compose.

### Start

1. From the repository root, start infrastructure:

       docker compose up -d

2. Open the solution in Visual Studio:

       FlightsPlatform.slnx

   Set `FlightsPlatform.Api` as the startup project, press F5.

3. In a separate terminal, start the SPA:

       cd frontend
       npm run dev:local

4. Open the browser:

       http://localhost:4200

### Stop

1. Stop the SPA: Ctrl+C in its terminal.
2. Stop the API: Stop button in Visual Studio.
3. Stop infrastructure:

       docker compose down

### Rebuild after backend code changes

The IDE rebuilds and restarts the API automatically on F5.

### Rebuild after frontend code changes

Angular dev server reloads automatically.

---

## Kubernetes environment

Everything runs inside a kind cluster. The SPA runs on the host.

### First-time setup (once per machine)

1. From the repository root, stop local infrastructure to avoid running
   two stacks at the same time:

       docker compose down

2. Create the kind cluster:

       kind create cluster --config kind-config.yaml

3. Install the ingress controller:

       kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

4. Add hosts entries (run Notepad as Administrator, edit
   `C:\Windows\System32\drivers\etc\hosts`, add the following lines):

       127.0.0.1 api.flights.local
       127.0.0.1 grafana.flights.local
       127.0.0.1 jaeger.flights.local
       127.0.0.1 rabbit.flights.local
       127.0.0.1 prometheus.flights.local

5. Build the application images:

       docker build -t flights-api:latest -f src/Hosts/FlightsPlatform.Api/Dockerfile .
       docker build -t flights-notification-worker:latest -f src/Workers/FlightsPlatform.NotificationWorker/Dockerfile .
       docker build -t flights-analytics-worker:latest -f src/Workers/FlightsPlatform.AnalyticsWorker/Dockerfile .

6. Load images into the kind node:

       kind load docker-image flights-api:latest --name flights
       kind load docker-image flights-notification-worker:latest --name flights
       kind load docker-image flights-analytics-worker:latest --name flights

7. Deploy the Helm chart:

       helm install flights ./chart -f ./chart/values-dev.yaml -n flights-platform --create-namespace

8. Wait until all pods are Running:

       kubectl get pods -n flights-platform --watch

   Press Ctrl+C when every pod shows `Running 1/1`.

9. Start the SPA:

       cd frontend
       npm run dev:k8s

10. Open the browser:

        http://localhost:4200

### Daily startup (cluster already exists)

1. From the repository root, stop local infrastructure:

       docker compose down

2. Select the kind context:

       kubectl config use-context kind-flights

3. Verify pods:

       kubectl get pods -n flights-platform

   If all pods are Running, skip to step 5.

4. Rebuild images if code changed:

       docker build -t flights-api:latest -f src/Hosts/FlightsPlatform.Api/Dockerfile .
       kind load docker-image flights-api:latest --name flights

   Repeat for the workers if their code changed.

5. Upgrade the release if images changed:

       helm upgrade flights ./chart -f ./chart/values-dev.yaml -n flights-platform

6. Start the SPA:

       cd frontend
       npm run dev:k8s

7. Open the browser:

        http://localhost:4200

### Rebuild after backend code changes

1. From the repository root, rebuild the image (example: API):

       docker build -t flights-api:latest -f src/Hosts/FlightsPlatform.Api/Dockerfile .

2. Load the image into kind:

       kind load docker-image flights-api:latest --name flights

3. Restart the deployment:

       kubectl rollout restart deployment/flights-api -n flights-platform

4. Watch the new pod:

       kubectl get pods -n flights-platform --watch

### Rebuild after frontend code changes

No action required. The SPA runs on the host via `npm run dev:k8s`
and Angular reloads automatically.

### Stop

1. Stop the SPA: Ctrl+C in its terminal.
2. Remove the Helm release:

       helm uninstall flights -n flights-platform

3. Delete the cluster (frees disk and memory):

       kind delete cluster --name flights

---

## Switching between environments

### Local to Kubernetes

1. Stop infrastructure:

       docker compose down

2. Select the kind context:

       kubectl config use-context kind-flights

3. Verify pods:

       kubectl get pods -n flights-platform

4. Follow the "Daily startup" steps above starting from step 4.

5. Restart the SPA with the K8s target:

       cd frontend
       npm run dev:k8s

### Kubernetes to Local

1. Stop the SPA: Ctrl+C in its terminal.
2. Start infrastructure:

       docker compose up -d

3. Start the API from Visual Studio (F5).
4. Start the SPA with the local target:

       cd frontend
       npm run dev:local

---

## Common commands

### Inspect resources

    kubectl get pods -n flights-platform
    kubectl get svc -n flights-platform
    kubectl get ingress -n flights-platform
    kubectl get hpa -n flights-platform
    kubectl top pods -n flights-platform

### Logs

    kubectl logs -n flights-platform deployment/flights-api --follow
    kubectl logs -n flights-platform deployment/flights-notification-worker --follow
    kubectl logs -n flights-platform deployment/flights-analytics-worker --follow

### Shell into a pod

    kubectl exec -it -n flights-platform deployment/flights-api -- sh

### Port-forward a service

    kubectl port-forward -n flights-platform svc/flights-api 8080:80
    kubectl port-forward -n flights-platform svc/flights-jaeger 16686:16686

### Events and diagnostics

    kubectl get events -n flights-platform --sort-by=.lastTimestamp
    kubectl describe pod -n flights-platform -l app.kubernetes.io/component=api