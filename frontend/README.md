# Frontend

Angular 22 SPA for the Flights Platform.

## Setup

From this directory:

    npm install

## Running against the Local backend

1. From the repository root, start infrastructure:

       docker compose up -d

2. Start the API from Visual Studio (F5).

3. From this directory, start the SPA:

       npm run dev:local

4. Open the browser:

       http://localhost:4200

## Running against the Kubernetes backend

1. Verify pods are running:

       kubectl get pods -n flights-platform

2. From this directory, start the SPA:

       npm run dev:k8s

3. Open the browser:

       http://localhost:4200

## Running against the Aspire backend

1. From the repository root, start the AppHost:

       dotnet run --project src/Hosts/FlightPlatform.AppHost

2. Copy the API URL from the Aspire dashboard (for example,
   `http://localhost:5234`).

3. From this directory, start the SPA with that URL:

       $env:API_TARGET = "http://localhost:5234"
       npm run dev

4. Open the browser:

       http://localhost:4200

The `API_TARGET` value is shown in the Aspire dashboard under the
`flights-api` resource.
## Running against a custom backend

Set the target explicitly, then start:

    $env:API_TARGET = "https://api.staging.example.com"
    npm run dev

Alternatively, create `frontend/.env`:

    API_TARGET=https://api.staging.example.com

Then run:

    npm run dev

## npm scripts

| Script            | Target                                |
| ----------------- | ------------------------------------- |
| `npm run dev:local` | `https://localhost:50943`           |
| `npm run dev:k8s`   | `http://api.flights.local`          |
| `npm run dev`       | value from `.env`, or local default |
| `npm run build`     | production build into `dist/`       |
| `npm test`          | unit tests                          |

## Project files

    .env              local overrides, git-ignored
    .env.example      template, committed
    proxy.conf.js     reads API_TARGET, forwards /api/* to the backend
    angular.json      serve.options.proxyConfig = "proxy.conf.js"

## How requests reach the backend

The SPA sends every request to `/api/*`. The dev server proxies those
requests to the value of `API_TARGET`. On startup the proxy prints the
effective target:

    [proxy] Forwarding /api/* -> https://localhost:50943/*

That line indicates which backend the SPA is currently using.

## Adding a new environment

1. Add a script to `package.json`:

       "dev:staging": "cross-env API_TARGET=https://api.staging.example.com ng serve --proxy-config proxy.conf.js"

2. Run it:

       npm run dev:staging