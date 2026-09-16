#Requires -Version 5.1
$ErrorActionPreference = "Stop"

function Write-File {
    param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)] [string] $Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $full = Join-Path (Get-Location).Path $Path
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path)
}

Write-Host ""
Write-Host "=== SPEC-004 - Script 4.1: Angular SPA foundation ==="
Write-Host ""

$root = (Get-Location).Path

# ===========================================================================
# 0. Prerequisites
# ===========================================================================
Write-Host "=== 0. Prerequisites ==="

$nodeVersion = $null
try { $nodeVersion = (node --version 2>$null) } catch {}
if (-not $nodeVersion) {
    Write-Host "  Node.js not found." -ForegroundColor Red
    Write-Host "  Install Node.js 20 LTS from https://nodejs.org and re-run this script." -ForegroundColor Red
    exit 1
}
Write-Host ("  Node.js " + $nodeVersion) -ForegroundColor Green

$npmVersion = (npm --version 2>$null)
if (-not $npmVersion) {
    Write-Host "  npm not found." -ForegroundColor Red
    exit 1
}
Write-Host ("  npm " + $npmVersion) -ForegroundColor Green

# ===========================================================================
# 1. Create Angular project
# ===========================================================================
Write-Host ""
Write-Host "=== 1. Create Angular project ==="

if (Test-Path -LiteralPath "frontend") {
    Write-Host "  frontend/ already exists - skipping ng new" -ForegroundColor Yellow
} else {
    Write-Host "  Running ng new frontend (this may take 2-5 minutes)..."
    npx --yes @angular/cli@latest new frontend `
        --style=scss `
        --routing `
        --ssr=false `
        --skip-git `
        --package-manager=npm `
        --defaults

    if ($LASTEXITCODE -ne 0) {
        Write-Host "  ng new failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "  + Angular project created" -ForegroundColor Green
}

# ===========================================================================
# 2. Install PrimeNG + primeicons
# ===========================================================================
Write-Host ""
Write-Host "=== 2. Install PrimeNG ==="

Push-Location frontend
try {
    npm install primeng primeicons 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  npm install failed" -ForegroundColor Red
        exit 1
    }
    Write-Host "  + primeng + primeicons installed" -ForegroundColor Green
} finally {
    Pop-Location
}

# ===========================================================================
# 3. Clean default app files
# ===========================================================================
Write-Host ""
Write-Host "=== 3. Clean default app files ==="

$appDir = "frontend/src/app"
if (Test-Path -LiteralPath $appDir) {
    Remove-Item -LiteralPath $appDir -Recurse -Force
    Write-Host "  + cleared frontend/src/app"
}

# ===========================================================================
# 4. proxy.conf.json
# ===========================================================================
Write-Host ""
Write-Host "=== 4. Dev proxy ==="

Write-File "frontend/proxy.conf.json" @'
{
  "/api": {
    "target": "https://localhost:50943",
    "secure": false,
    "changeOrigin": true,
    "logLevel": "info",
    "pathRewrite": { "^/api": "" }
  }
}
'@

# ===========================================================================
# 5. Angular source files
# ===========================================================================
Write-Host ""
Write-Host "=== 5. Angular source files ==="

# --- index.html ---
Write-File "frontend/src/index.html" @'
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Flights Platform</title>
  <base href="/">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="icon" type="image/x-icon" href="favicon.ico">
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/primeicons@7.0.0/primeicons.css">
</head>
<body>
  <app-root></app-root>
</body>
</html>
'@

# --- styles.scss ---
Write-File "frontend/src/styles.scss" @'
/* Global styles */
:root {
  --bg: #f8fafc;
  --surface: #ffffff;
  --border: #e2e8f0;
  --text: #0f172a;
  --text-muted: #64748b;
  --primary: #3b82f6;
  --success: #16a34a;
  --danger: #dc2626;
  --warning: #f59e0b;
}

html.dark {
  --bg: #0f172a;
  --surface: #1e293b;
  --border: #334155;
  --text: #f1f5f9;
  --text-muted: #94a3b8;
}

* { box-sizing: border-box; }

html, body {
  margin: 0;
  padding: 0;
  height: 100%;
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
  background: var(--bg);
  color: var(--text);
  transition: background 0.2s, color 0.2s;
}

button { cursor: pointer; font-family: inherit; }

a { color: var(--primary); text-decoration: none; }

.pi { font-family: "primeicons" !important; }
'@

# --- main.ts ---
Write-File "frontend/src/main.ts" @'
import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';

bootstrapApplication(AppComponent, appConfig)
  .catch((err) => console.error(err));
'@

# --- app.config.ts ---
Write-File "frontend/src/app/app.config.ts" @'
import { ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
import { routes } from './app.routes';
import { apiErrorInterceptor } from './core/api/error.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideRouter(routes),
    provideHttpClient(withInterceptors([apiErrorInterceptor])),
    provideAnimationsAsync()
  ]
};
'@

# --- app.routes.ts ---
Write-File "frontend/src/app/app.routes.ts" @'
import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  {
    path: 'dashboard',
    loadComponent: () =>
      import('./features/dashboard/dashboard.page').then(m => m.DashboardPage)
  },
  {
    path: 'airports',
    loadComponent: () =>
      import('./features/airports/airports.page').then(m => m.AirportsPage)
  },
  {
    path: 'flights',
    loadComponent: () =>
      import('./features/flights/flights.page').then(m => m.FlightsPage)
  },
  {
    path: 'bookings',
    loadComponent: () =>
      import('./features/bookings/bookings.page').then(m => m.BookingsPage)
  },
  { path: '**', redirectTo: 'dashboard' }
];
'@

# --- app.component.ts ---
Write-File "frontend/src/app/app.component.ts" @'
import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { SidebarComponent } from './core/layout/sidebar.component';
import { HeaderComponent } from './core/layout/header.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, SidebarComponent, HeaderComponent],
  template: `
    <div class="app-shell">
      <app-sidebar></app-sidebar>
      <div class="app-main">
        <app-header></app-header>
        <main class="app-content">
          <router-outlet></router-outlet>
        </main>
      </div>
    </div>
  `,
  styles: [`
    .app-shell {
      display: flex;
      min-height: 100vh;
    }
    .app-main {
      flex: 1;
      display: flex;
      flex-direction: column;
      min-width: 0;
    }
    .app-content {
      flex: 1;
      padding: 1.5rem 2rem;
      overflow-y: auto;
    }
  `]
})
export class AppComponent {}
'@

# --- core/api/models/api-error.model.ts ---
Write-File "frontend/src/app/core/api/models/api-error.model.ts" @'
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code?: string
  ) {
    super(message);
    this.name = 'ApiError';
  }
}

export interface BackendErrorBody {
  error?: string;
  code?: string;
  message?: string;
  details?: string[];
}
'@

# --- core/api/models/airport.model.ts ---
Write-File "frontend/src/app/core/api/models/airport.model.ts" @'
export interface Airport {
  id: string;
  code: string;
  name: string;
  city: string;
  timezone: string;
  latitude: number;
  longitude: number;
}

export interface AirportListResponse {
  items: Airport[];
  total: number;
  page: number;
  pageSize: number;
}
'@

# --- core/api/models/flight.model.ts ---
Write-File "frontend/src/app/core/api/models/flight.model.ts" @'
export interface Flight {
  id: string;
  flightNumber: string;
  departureAirport: string;
  departureAirportName?: string | null;
  arrivalAirport: string;
  arrivalAirportName?: string | null;
  scheduledDeparture: string;
  scheduledArrival: string;
  status: number;
  aircraftModel: string;
}

export interface CreateFlightRequest {
  flightNumber: string;
  departureAirport: string;
  arrivalAirport: string;
  departure: string;
  arrival: string;
  aircraftModel: string;
}

export interface DelayFlightRequest {
  newDeparture: string;
  newArrival: string;
}

export interface CancelFlightRequest {
  reason: string;
}
'@

# --- core/api/models/booking.model.ts ---
Write-File "frontend/src/app/core/api/models/booking.model.ts" @'
export interface Ticket {
  id: string;
  ticketNo: string;
  flightId: string;
  amount: number;
}

export interface Booking {
  id: string;
  bookRef: string;
  bookDate: string;
  totalAmount: number;
  currency: string;
  status: number;
  passengerId: string;
  passengerName: string;
  tickets: Ticket[];
}

export interface CreateBookingRequest {
  passengerId: string;
  passengerName: string;
  currency: string;
}

export interface AddTicketRequest {
  flightId: string;
  passengerId: string;
  passengerName: string;
  amount: number;
}

export interface ConfirmBookingResult {
  bookingId: string;
  confirmed: boolean;
  failureReason?: string | null;
}

export interface CancelBookingRequest {
  reason: string;
}

export const BookingStatus = {
  Pending: 0,
  Confirmed: 1,
  Cancelled: 2,
  Expired: 3
} as const;

export const FlightStatus = {
  Scheduled: 0,
  Delayed: 1,
  Departed: 2,
  Arrived: 3,
  Cancelled: 4
} as const;

export interface DashboardSummary {
  flights: number;
  airports: number;
  bookings: number;
  activeBookings: number;
}

export interface HealthResponse {
  status: string;
  time: string;
}
'@

# --- core/api/api.service.ts ---
Write-File "frontend/src/app/core/api/api.service.ts" @'
import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';

@Injectable({ providedIn: 'root' })
export class ApiService {
  private readonly http = inject(HttpClient);
  private readonly baseUrl = '/api';

  get<T>(path: string, params?: Record<string, string | number>): Observable<T> {
    let httpParams = new HttpParams();
    if (params) {
      for (const [key, value] of Object.entries(params)) {
        httpParams = httpParams.set(key, String(value));
      }
    }
    return this.http.get<T>(`${this.baseUrl}${path}`, { params: httpParams });
  }

  post<T>(path: string, body: unknown): Observable<T> {
    return this.http.post<T>(`${this.baseUrl}${path}`, body);
  }

  put<T>(path: string, body: unknown): Observable<T> {
    return this.http.put<T>(`${this.baseUrl}${path}`, body);
  }

  delete<T>(path: string): Observable<T> {
    return this.http.delete<T>(`${this.baseUrl}${path}`);
  }
}
'@

# --- core/api/error.interceptor.ts ---
Write-File "frontend/src/app/core/api/error.interceptor.ts" @'
import { HttpErrorResponse, HttpInterceptorFn } from '@angular/common/http';
import { catchError, throwError } from 'rxjs';
import { ApiError, BackendErrorBody } from './models/api-error.model';

export const apiErrorInterceptor: HttpInterceptorFn = (req, next) => {
  return next(req).pipe(
    catchError((response: unknown) => {
      if (response instanceof HttpErrorResponse) {
        const body = response.error as BackendErrorBody | null;

        let message = `HTTP ${response.status}`;
        let code: string | undefined;

        if (body) {
          if (Array.isArray(body.details) && body.details.length > 0) {
            message = body.details.join('; ');
          } else if (body.message) {
            message = body.message;
          } else if (body.error) {
            message = body.error;
          }
          code = body.code;
        } else if (response.message) {
          message = response.message;
        }

        return throwError(() => new ApiError(response.status, message, code));
      }
      return throwError(() => response);
    })
  );
};
'@

# --- core/services/theme.service.ts ---
Write-File "frontend/src/app/core/services/theme.service.ts" @'
import { Injectable, signal } from '@angular/core';

type Theme = 'light' | 'dark';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  private readonly storageKey = 'flights-platform-theme';
  private readonly current = signal<Theme>(this.loadTheme());

  readonly theme = this.current.asReadonly();

  constructor() {
    this.apply(this.current());
  }

  toggle(): void {
    const next: Theme = this.current() === 'dark' ? 'light' : 'dark';
    this.current.set(next);
    localStorage.setItem(this.storageKey, next);
    this.apply(next);
  }

  isDark(): boolean {
    return this.current() === 'dark';
  }

  private loadTheme(): Theme {
    const stored = localStorage.getItem(this.storageKey);
    if (stored === 'dark' || stored === 'light') return stored;
    return 'light';
  }

  private apply(theme: Theme): void {
    const root = document.documentElement;
    if (theme === 'dark') {
      root.classList.add('dark');
    } else {
      root.classList.remove('dark');
    }
  }
}
'@

# --- core/services/health.service.ts ---
Write-File "frontend/src/app/core/services/health.service.ts" @'
import { Injectable, inject, signal } from '@angular/core';
import { ApiService } from '../api/api.service';
import { HealthResponse } from '../api/models/booking.model';

@Injectable({ providedIn: 'root' })
export class HealthService {
  private readonly api = inject(ApiService);
  private readonly online = signal<boolean>(true);
  private timerId: number | null = null;

  readonly isOnline = this.online.asReadonly();

  start(): void {
    if (this.timerId !== null) return;
    this.check();
    this.timerId = window.setInterval(() => this.check(), 15000);
  }

  stop(): void {
    if (this.timerId !== null) {
      clearInterval(this.timerId);
      this.timerId = null;
    }
  }

  private check(): void {
    this.api.get<HealthResponse>('/health').subscribe({
      next: () => this.online.set(true),
      error: () => this.online.set(false)
    });
  }
}
'@

# --- core/layout/sidebar.component.ts ---
Write-File "frontend/src/app/core/layout/sidebar.component.ts" @'
import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  template: `
    <aside class="sidebar">
      <div class="brand">
        <i class="pi pi-send"></i>
        <span>Flights Platform</span>
      </div>
      <nav>
        <a routerLink="/dashboard" routerLinkActive="active">
          <i class="pi pi-home"></i><span>Dashboard</span>
        </a>
        <a routerLink="/airports" routerLinkActive="active">
          <i class="pi pi-map-marker"></i><span>Airports</span>
        </a>
        <a routerLink="/flights" routerLinkActive="active">
          <i class="pi pi-send"></i><span>Flights</span>
        </a>
        <a routerLink="/bookings" routerLinkActive="active">
          <i class="pi pi-ticket"></i><span>Bookings</span>
        </a>
      </nav>
    </aside>
  `,
  styles: [`
    .sidebar {
      width: 240px;
      background: var(--surface);
      border-right: 1px solid var(--border);
      display: flex;
      flex-direction: column;
      padding: 1rem 0;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 0.6rem;
      padding: 0 1.25rem 1rem;
      font-weight: 600;
      font-size: 1.05rem;
      border-bottom: 1px solid var(--border);
      margin-bottom: 1rem;
    }
    .brand .pi { color: var(--primary); font-size: 1.25rem; }
    nav { display: flex; flex-direction: column; gap: 0.25rem; padding: 0 0.5rem; }
    nav a {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.65rem 0.85rem;
      border-radius: 6px;
      color: var(--text);
      font-size: 0.95rem;
      transition: background 0.15s;
    }
    nav a:hover { background: var(--bg); }
    nav a.active {
      background: var(--primary);
      color: white;
    }
    nav a .pi { font-size: 1rem; width: 1.1rem; text-align: center; }
  `]
})
export class SidebarComponent {}
'@

# --- core/layout/header.component.ts ---
Write-File "frontend/src/app/core/layout/header.component.ts" @'
import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { HealthService } from '../services/health.service';
import { ThemeService } from '../services/theme.service';

@Component({
  selector: 'app-header',
  standalone: true,
  template: `
    <header class="header">
      <div class="health" [class.online]="health.isOnline()" [class.offline]="!health.isOnline()">
        <span class="dot"></span>
        <span>{{ health.isOnline() ? 'API online' : 'API offline' }}</span>
      </div>
      <button class="theme-btn" (click)="theme.toggle()" title="Toggle theme">
        <i class="pi" [class.pi-moon]="!theme.isDark()" [class.pi-sun]="theme.isDark()"></i>
      </button>
    </header>
  `,
  styles: [`
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0.75rem 2rem;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
    }
    .health {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 0.9rem;
      color: var(--text-muted);
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--text-muted);
    }
    .health.online .dot { background: var(--success); }
    .health.online span:last-child { color: var(--success); }
    .health.offline .dot { background: var(--danger); }
    .health.offline span:last-child { color: var(--danger); }
    .theme-btn {
      background: transparent;
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.4rem 0.6rem;
      color: var(--text);
    }
    .theme-btn:hover { background: var(--bg); }
  `]
})
export class HeaderComponent implements OnInit, OnDestroy {
  readonly health = inject(HealthService);
  readonly theme = inject(ThemeService);

  ngOnInit(): void {
    this.health.start();
  }

  ngOnDestroy(): void {
    this.health.stop();
  }
}
'@

# --- features/dashboard/dashboard.page.ts ---
Write-File "frontend/src/app/features/dashboard/dashboard.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { ApiService } from '../../core/api/api.service';
import { DashboardSummary } from '../../core/api/models/booking.model';

@Component({
  selector: 'app-dashboard-page',
  standalone: true,
  imports: [DatePipe],
  template: `
    <div class="page">
      <h1>Dashboard</h1>
      <p class="subtitle">Platform overview</p>

      @if (loading()) {
        <p>Loading...</p>
      } @else if (summary()) {
        <div class="cards">
          <div class="card">
            <div class="card-label">Flights</div>
            <div class="card-value">{{ summary()!.flights }}</div>
          </div>
          <div class="card">
            <div class="card-label">Airports</div>
            <div class="card-value">{{ summary()!.airports }}</div>
          </div>
          <div class="card">
            <div class="card-label">Bookings</div>
            <div class="card-value">{{ summary()!.bookings }}</div>
          </div>
          <div class="card">
            <div class="card-label">Active bookings</div>
            <div class="card-value">{{ summary()!.activeBookings }}</div>
          </div>
        </div>
      } @else {
        <p class="error">Failed to load summary.</p>
      }

      <p class="footnote">Last update: {{ now | date:'medium' }}</p>
    </div>
  `,
  styles: [`
    h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
    .subtitle { color: var(--text-muted); margin: 0 0 1.5rem; }
    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 1rem;
    }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1.25rem;
    }
    .card-label { color: var(--text-muted); font-size: 0.85rem; text-transform: uppercase; }
    .card-value { font-size: 2rem; font-weight: 700; margin-top: 0.5rem; }
    .error { color: var(--danger); }
    .footnote { margin-top: 2rem; color: var(--text-muted); font-size: 0.85rem; }
  `]
})
export class DashboardPage implements OnInit {
  private readonly api = inject(ApiService);

  readonly summary = signal<DashboardSummary | null>(null);
  readonly loading = signal(true);
  readonly now = new Date();

  ngOnInit(): void {
    this.api.get<DashboardSummary>('/dashboard/summary').subscribe({
      next: (data) => {
        this.summary.set(data);
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
      }
    });
  }
}
'@

# --- features/airports/airports.page.ts (placeholder) ---
Write-File "frontend/src/app/features/airports/airports.page.ts" @'
import { Component } from '@angular/core';

@Component({
  selector: 'app-airports-page',
  standalone: true,
  template: `
    <div class="page">
      <h1>Airports</h1>
      <p class="subtitle">Coming in phase 4.2</p>
    </div>
  `,
  styles: [`
    h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
    .subtitle { color: var(--text-muted); }
  `]
})
export class AirportsPage {}
'@

# --- features/flights/flights.page.ts (placeholder) ---
Write-File "frontend/src/app/features/flights/flights.page.ts" @'
import { Component } from '@angular/core';

@Component({
  selector: 'app-flights-page',
  standalone: true,
  template: `
    <div class="page">
      <h1>Flights</h1>
      <p class="subtitle">Coming in phase 4.2</p>
    </div>
  `,
  styles: [`
    h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
    .subtitle { color: var(--text-muted); }
  `]
})
export class FlightsPage {}
'@

# --- features/bookings/bookings.page.ts (placeholder) ---
Write-File "frontend/src/app/features/bookings/bookings.page.ts" @'
import { Component } from '@angular/core';

@Component({
  selector: 'app-bookings-page',
  standalone: true,
  template: `
    <div class="page">
      <h1>Bookings</h1>
      <p class="subtitle">Coming in phase 4.3</p>
    </div>
  `,
  styles: [`
    h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
    .subtitle { color: var(--text-muted); }
  `]
})
export class BookingsPage {}
'@

# ===========================================================================
# 6. angular.json: add proxyConfig to serve options
# ===========================================================================
Write-Host ""
Write-Host "=== 6. angular.json: add proxy ==="

$angularJsonPath = "frontend/angular.json"
if (Test-Path -LiteralPath $angularJsonPath) {
    $aj = [System.IO.File]::ReadAllText($angularJsonPath)

    if ($aj -notmatch '"proxyConfig"') {
        # Insert proxyConfig just after "serve": { ... "options": {
        $aj = $aj -replace '("serve"\s*:\s*\{\s*"builder"[^}]*"options"\s*:\s*\{)', '$1' + "`r`n              `"proxyConfig`": `"proxy.conf.json`","
        [System.IO.File]::WriteAllText((Join-Path (Get-Location).Path $angularJsonPath), $aj, [System.Text.UTF8Encoding]::new($false))
        Write-Host "  + added proxyConfig to angular.json"
    } else {
        Write-Host "  - proxyConfig already present"
    }
} else {
    Write-Host "  ! angular.json not found - add proxyConfig manually" -ForegroundColor Yellow
}

# ===========================================================================
# 7. Backend: CORS + /health + /dashboard/summary
# ===========================================================================
Write-Host ""
Write-Host "=== 7. Backend changes ==="

$hostDir = "src/Hosts/FlightsPlatform.Api"

# --- DashboardEndpoints.cs ---
Write-File "$hostDir/Endpoints/DashboardEndpoints.cs" @'
using Bookings.Domain;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Infrastructure.Persistence;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;
using Microsoft.EntityFrameworkCore;

namespace FlightsPlatform.Api.Endpoints;

public static class DashboardEndpoints
{
    public static IEndpointRouteBuilder MapDashboardEndpoints(this IEndpointRouteBuilder app)
    {
        app.MapGet("/dashboard/summary", async (
            FlightCatalogDbContext fcDb,
            BookingDbContext bkDb,
            CancellationToken ct) =>
        {
            var flights = await fcDb.Flights.CountAsync(ct);
            var airports = await fcDb.Airports.CountAsync(ct);
            var bookings = await bkDb.Bookings.CountAsync(ct);
            var activeBookings = await bkDb.Bookings
                .CountAsync(b => b.Status == BookingStatus.Pending, ct);

            return Results.Ok(new
            {
                flights,
                airports,
                bookings,
                activeBookings
            });
        })
        .WithTags("Dashboard")
        .WithName("GetDashboardSummary");

        return app;
    }
}
'@

# --- Program.cs (full rewrite with CORS, health, dashboard) ---
Write-File "$hostDir/Program.cs" @'
using Bookings.Api;
using Bookings.Application;
using Bookings.Infrastructure;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Api;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FlightsPlatform.Api.Endpoints;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;
using FlightsPlatform.SharedKernel;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

// CORS for Angular dev server (Development only).
builder.Services.AddCors(options =>
{
    options.AddPolicy("frontend", policy =>
    {
        policy.WithOrigins("http://localhost:4200")
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

builder.Services.AddFlightCatalogApplication();
builder.Services.AddFlightCatalogInfrastructure(builder.Configuration);

builder.Services.AddBookingsApplication();
builder.Services.AddBookingsInfrastructure(builder.Configuration);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
    app.UseCors("frontend");
}

app.UseExceptionHandler(errApp => errApp.Run(async ctx =>
{
    var feature = ctx.Features.Get<IExceptionHandlerFeature>();
    var ex = feature?.Error;

    var (status, payload) = ex switch
    {
        ValidationException ve => (StatusCodes.Status400BadRequest,
            (object)new
            {
                error = "validation_failed",
                details = ve.Errors.Select(e => e.ErrorMessage)
            }),
        DomainException de => (StatusCodes.Status400BadRequest,
            new { error = "domain_error", message = de.Message }),
        _ => (StatusCodes.Status500InternalServerError,
            new { error = "internal_error" })
    };

    ctx.Response.StatusCode = status;
    await ctx.Response.WriteAsJsonAsync(payload);
}));

app.UseHttpsRedirection();
app.MapControllers();
app.MapFlightCatalogEndpoints();
app.MapAirportEndpoints();
app.MapBookingsEndpoints();
app.MapDashboardEndpoints();

// Health endpoint for the SPA header indicator.
app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    time = DateTimeOffset.UtcNow
}))
.WithTags("Health")
.WithName("GetHealth");

using (var scope = app.Services.CreateScope())
{
    var fcDb = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await fcDb.Database.MigrateAsync();

    var bkDb = scope.ServiceProvider.GetRequiredService<BookingDbContext>();
    await bkDb.Database.MigrateAsync();
}

app.Run();
'@

# ===========================================================================
# 8. Build backend + build frontend
# ===========================================================================
Write-Host ""
Write-Host "=== 8. Build backend ==="

Get-ChildItem -Path . -Include bin,obj -Recurse -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notlike "*\frontend\*" } |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

dotnet restore
dotnet build --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Host "  BACKEND BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + backend build ok" -ForegroundColor Green

Write-Host ""
Write-Host "=== 9. Build frontend (production, sanity check) ==="

Push-Location frontend
try {
    npm run build 2>&1 | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  FRONTEND BUILD FAILED - see errors above" -ForegroundColor Red
        exit 1
    }
    Write-Host "  + frontend build ok" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Run backend:" -ForegroundColor Yellow
Write-Host "  dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host ""
Write-Host "Run frontend (in another terminal):" -ForegroundColor Yellow
Write-Host "  cd frontend"
Write-Host "  npm start"
Write-Host ""
Write-Host "Open: http://localhost:4200" -ForegroundColor Yellow
Write-Host ""
Write-Host "You should see:" -ForegroundColor Yellow
Write-Host "  - Sidebar with Dashboard / Airports / Flights / Bookings"
Write-Host "  - Header with green API status indicator"
Write-Host "  - Theme toggle button (light/dark)"
Write-Host "  - Dashboard with counts (flights, airports, bookings, active)"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(frontend): phase 4.1 - Angular SPA foundation"'
Write-Host "  git push"
Write-Host ""