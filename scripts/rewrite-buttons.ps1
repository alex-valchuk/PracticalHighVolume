# PowerShell 5.1 compatible

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

$root = (Get-Location).Path

Write-Host ""
Write-Host "=== Rewrite buttons: plain HTML with visible text ==="
Write-Host ""

# ===========================================================================
# 1. styles.scss - add .btn utilities
# ===========================================================================
Write-Host "=== 1. styles.scss ==="

Write-File "frontend/src/styles.scss" @'
@import "primeicons/primeicons.css";

:root {
  --bg: #f8fafc;
  --surface: #ffffff;
  --border: #e2e8f0;
  --text: #0f172a;
  --text-muted: #64748b;
  --primary: #3b82f6;
  --primary-hover: #2563eb;
  --success: #16a34a;
  --success-hover: #15803d;
  --danger: #dc2626;
  --danger-hover: #b91c1c;
  --warning: #f59e0b;
  --warning-hover: #d97706;
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

a { color: var(--primary); text-decoration: none; }

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 1.5rem;
  gap: 1rem;
  flex-wrap: wrap;
}
.page-header h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
.page-header .subtitle { color: var(--text-muted); margin: 0; }
.page-header .actions { display: flex; gap: 0.5rem; align-items: center; }

/* ---------- Buttons ---------- */
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.55rem 1rem;
  border-radius: 6px;
  font-size: 0.95rem;
  font-weight: 500;
  border: 1px solid transparent;
  cursor: pointer;
  transition: background 0.15s, opacity 0.15s;
  white-space: nowrap;
  font-family: inherit;
  line-height: 1.1;
  text-decoration: none;
}
.btn i { font-size: 0.95rem; }
.btn:disabled { opacity: 0.5; cursor: not-allowed; }

.btn-primary { background: var(--primary); color: #fff; }
.btn-primary:hover:not(:disabled) { background: var(--primary-hover); }

.btn-success { background: var(--success); color: #fff; }
.btn-success:hover:not(:disabled) { background: var(--success-hover); }

.btn-danger { background: var(--danger); color: #fff; }
.btn-danger:hover:not(:disabled) { background: var(--danger-hover); }

.btn-warn { background: var(--warning); color: #fff; }
.btn-warn:hover:not(:disabled) { background: var(--warning-hover); }

.btn-secondary {
  background: transparent;
  color: var(--text);
  border-color: var(--border);
}
.btn-secondary:hover:not(:disabled) { background: var(--bg); }

.btn-sm {
  padding: 0.35rem 0.75rem;
  font-size: 0.85rem;
}
.btn-sm i { font-size: 0.85rem; }
'@

# ===========================================================================
# 2. Header
# ===========================================================================
Write-Host ""
Write-Host "=== 2. header.component.ts ==="

Write-File "frontend/src/app/core/layout/header.component.ts" @'
import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { TooltipModule } from 'primeng/tooltip';
import { HealthService } from '../services/health.service';
import { ThemeService } from '../services/theme.service';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [TooltipModule],
  template: `
    <header class="header">
      <div class="health" [class.online]="health.isOnline()" [class.offline]="!health.isOnline()">
        <span class="dot"></span>
        <span>{{ health.isOnline() ? 'API online' : 'API offline' }}</span>
      </div>

      <button class="btn btn-secondary" type="button" (click)="theme.toggle()">
        @if (theme.isDark()) {
          <i class="pi pi-sun"></i><span>Light theme</span>
        } @else {
          <i class="pi pi-moon"></i><span>Dark theme</span>
        }
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
    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--text-muted); }
    .health.online .dot { background: var(--success); }
    .health.online span:last-child { color: var(--success); }
    .health.offline .dot { background: var(--danger); }
    .health.offline span:last-child { color: var(--danger); }
  `]
})
export class HeaderComponent implements OnInit, OnDestroy {
  readonly health = inject(HealthService);
  readonly theme = inject(ThemeService);

  ngOnInit(): void { this.health.start(); }
  ngOnDestroy(): void { this.health.stop(); }
}
'@

# ===========================================================================
# 3. Airports page
# ===========================================================================
Write-Host ""
Write-Host "=== 3. airports.page.ts ==="

Write-File "frontend/src/app/features/airports/airports.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DecimalPipe } from '@angular/common';
import { TableModule, SortIcon } from 'primeng/table';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { MessageService } from 'primeng/api';
import { Airport } from '../../core/api/models/airport.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { AirportsService } from './airports.service';

@Component({
  selector: 'app-airports-page',
  standalone: true,
  imports: [FormsModule, DecimalPipe, TableModule, SortIcon, InputTextModule, TagModule],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <h1>Airports</h1>
          <p class="subtitle">Reference data synchronized from the external source</p>
        </div>
        <div class="actions">
          <button class="btn btn-primary" type="button"
                  [disabled]="syncing()"
                  (click)="sync()">
            @if (syncing()) {
              <i class="pi pi-spin pi-spinner"></i><span>Syncing...</span>
            } @else {
              <i class="pi pi-refresh"></i><span>Sync from source</span>
            }
          </button>
        </div>
      </div>

      <p-table
        [value]="airports()"
        [loading]="loading()"
        [paginator]="true"
        [rows]="20"
        [rowsPerPageOptions]="[10, 20, 50, 100]"
        [globalFilterFields]="['code', 'name', 'city', 'timezone']"
        #dt
        styleClass="p-datatable-sm">

        <ng-template #caption>
          <div class="table-caption">
            <input pInputText type="text"
                   placeholder="Search by code, name, city..."
                   (input)="dt.filterGlobal($any($event.target).value, 'contains')" />
            <span class="count">{{ airports().length }} airports</span>
          </div>
        </ng-template>

        <ng-template #header>
          <tr>
            <th pSortableColumn="code">Code <p-sort-icon field="code"></p-sort-icon></th>
            <th pSortableColumn="name">Name <p-sort-icon field="name"></p-sort-icon></th>
            <th pSortableColumn="city">City <p-sort-icon field="city"></p-sort-icon></th>
            <th>Timezone</th>
            <th>Coordinates</th>
          </tr>
        </ng-template>

        <ng-template #body let-airport>
          <tr>
            <td><p-tag [value]="airport.code" severity="info"></p-tag></td>
            <td>{{ airport.name }}</td>
            <td>{{ airport.city }}</td>
            <td>{{ airport.timezone }}</td>
            <td class="coords">
              {{ airport.latitude | number:'1.2-2' }},
              {{ airport.longitude | number:'1.2-2' }}
            </td>
          </tr>
        </ng-template>

        <ng-template #emptymessage>
          <tr>
            <td colspan="5" class="empty">
              No airports. Click "Sync from source" to import from the external source.
            </td>
          </tr>
        </ng-template>
      </p-table>
    </div>
  `,
  styles: [`
    .table-caption { display: flex; align-items: center; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }
    .count { color: var(--text-muted); font-size: 0.9rem; }
    .coords { color: var(--text-muted); font-family: monospace; font-size: 0.85rem; }
    .empty { text-align: center; padding: 2rem; color: var(--text-muted); }
  `]
})
export class AirportsPage implements OnInit {
  private readonly service = inject(AirportsService);
  private readonly messages = inject(MessageService);

  readonly airports = signal<Airport[]>([]);
  readonly loading = signal(false);
  readonly syncing = signal(false);

  ngOnInit(): void { this.load(); }

  private load(): void {
    this.loading.set(true);
    this.service.list().subscribe({
      next: (resp) => {
        this.airports.set(resp.items);
        this.loading.set(false);
      },
      error: (err: ApiError) => {
        this.loading.set(false);
        this.messages.add({ severity: 'error', summary: 'Failed to load airports', detail: err.message });
      }
    });
  }

  sync(): void {
    this.syncing.set(true);
    this.service.sync().subscribe({
      next: (r) => {
        this.syncing.set(false);
        this.messages.add({
          severity: 'success',
          summary: 'Sync completed',
          detail: `Read: ${r.read}, created: ${r.created}, updated: ${r.updated}, skipped: ${r.skipped}`
        });
        this.load();
      },
      error: (err: ApiError) => {
        this.syncing.set(false);
        this.messages.add({ severity: 'error', summary: 'Sync failed', detail: err.message });
      }
    });
  }
}
'@

# ===========================================================================
# 4. Flights page
# ===========================================================================
Write-Host ""
Write-Host "=== 4. flights.page.ts ==="

Write-File "frontend/src/app/features/flights/flights.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { TableModule } from 'primeng/table';
import { InputTextModule } from 'primeng/inputtext';
import { DatePickerModule } from 'primeng/datepicker';
import { TagModule } from 'primeng/tag';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { Flight } from '../../core/api/models/flight.model';
import { FlightStatus } from '../../core/api/models/booking.model';
import { FlightsService } from './flights.service';
import { CreateFlightDialogComponent } from './create-flight-dialog.component';
import { DelayFlightDialogComponent } from './delay-flight-dialog.component';
import { CancelFlightDialogComponent } from './cancel-flight-dialog.component';

@Component({
  selector: 'app-flights-page',
  standalone: true,
  imports: [
    FormsModule, DatePipe, TableModule, InputTextModule,
    DatePickerModule, TagModule,
    CreateFlightDialogComponent, DelayFlightDialogComponent, CancelFlightDialogComponent
  ],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <h1>Flights</h1>
          <p class="subtitle">Search and manage scheduled flights</p>
        </div>
        <div class="actions">
          <button class="btn btn-primary" type="button" (click)="showCreate = true">
            <i class="pi pi-plus"></i><span>Create flight</span>
          </button>
        </div>
      </div>

      <div class="filters">
        <input pInputText [(ngModel)]="from" placeholder="From (e.g. SVO)" maxlength="3" />
        <input pInputText [(ngModel)]="to" placeholder="To (e.g. OVB)" maxlength="3" />
        <p-datepicker [(ngModel)]="date" dateFormat="yy-mm-dd" [showIcon]="true"></p-datepicker>
        <button class="btn btn-primary" type="button" [disabled]="loading()" (click)="search()">
          @if (loading()) {
            <i class="pi pi-spin pi-spinner"></i><span>Searching...</span>
          } @else {
            <i class="pi pi-search"></i><span>Search</span>
          }
        </button>
      </div>

      <p-table
        [value]="flights()"
        [loading]="loading()"
        [paginator]="true"
        [rows]="20"
        [rowsPerPageOptions]="[10, 20, 50]"
        styleClass="p-datatable-sm">

        <ng-template #header>
          <tr>
            <th>Flight</th>
            <th>Route</th>
            <th>Departure</th>
            <th>Arrival</th>
            <th>Status</th>
            <th>Aircraft</th>
            <th style="width: 220px;">Actions</th>
          </tr>
        </ng-template>

        <ng-template #body let-flight>
          <tr>
            <td><strong>{{ flight.flightNumber }}</strong></td>
            <td>
              {{ flight.departureAirport }}
              @if (flight.departureAirportName) {
                <span class="muted">({{ flight.departureAirportName }})</span>
              }
              <i class="pi pi-arrow-right" style="font-size: 0.7rem; margin: 0 0.35rem;"></i>
              {{ flight.arrivalAirport }}
              @if (flight.arrivalAirportName) {
                <span class="muted">({{ flight.arrivalAirportName }})</span>
              }
            </td>
            <td>{{ flight.scheduledDeparture | date:'short' }}</td>
            <td>{{ flight.scheduledArrival | date:'short' }}</td>
            <td>
              <p-tag [value]="statusLabel(flight.status)"
                     [severity]="statusSeverity(flight.status)"></p-tag>
            </td>
            <td>{{ flight.aircraftModel }}</td>
            <td class="actions-cell">
              <button class="btn btn-warn btn-sm" type="button"
                      [disabled]="!canDelay(flight)"
                      (click)="openDelay(flight)">
                <i class="pi pi-clock"></i><span>Delay</span>
              </button>
              <button class="btn btn-danger btn-sm" type="button"
                      [disabled]="!canCancel(flight)"
                      (click)="openCancel(flight)">
                <i class="pi pi-times"></i><span>Cancel</span>
              </button>
            </td>
          </tr>
        </ng-template>

        <ng-template #emptymessage>
          <tr>
            <td colspan="7" class="empty">
              No flights found. Adjust filters or create a new flight.
            </td>
          </tr>
        </ng-template>
      </p-table>

      <app-create-flight-dialog
        [(visible)]="showCreate"
        (created)="onMutated()"></app-create-flight-dialog>

      <app-delay-flight-dialog
        [(visible)]="showDelay"
        [flight]="selected()"
        (delayed)="onMutated()"></app-delay-flight-dialog>

      <app-cancel-flight-dialog
        [(visible)]="showCancel"
        [flight]="selected()"
        (cancelled)="onMutated()"></app-cancel-flight-dialog>
    </div>
  `,
  styles: [`
    .filters { display: flex; gap: 0.5rem; align-items: center; margin-bottom: 1rem; flex-wrap: wrap; }
    .muted { color: var(--text-muted); font-size: 0.85rem; }
    .empty { text-align: center; padding: 2rem; color: var(--text-muted); }
    .actions-cell { display: flex; gap: 0.5rem; }
  `]
})
export class FlightsPage implements OnInit {
  private readonly service = inject(FlightsService);
  private readonly messages = inject(MessageService);

  readonly flights = signal<Flight[]>([]);
  readonly loading = signal(false);
  readonly selected = signal<Flight | null>(null);

  from = 'SVO';
  to = 'OVB';
  date: Date = new Date();

  showCreate = false;
  showDelay = false;
  showCancel = false;

  ngOnInit(): void { this.search(); }

  search(): void {
    if (!this.from || !this.to || !this.date) {
      this.messages.add({ severity: 'warn', summary: 'Missing filters', detail: 'Enter route and date.' });
      return;
    }

    const dateStr = this.toIsoDate(this.date);
    this.loading.set(true);
    this.service.search(this.from.toUpperCase(), this.to.toUpperCase(), dateStr).subscribe({
      next: (list) => { this.flights.set(list); this.loading.set(false); },
      error: (err: ApiError) => {
        this.loading.set(false);
        this.messages.add({ severity: 'error', summary: 'Search failed', detail: err.message });
      }
    });
  }

  openDelay(flight: Flight): void { this.selected.set(flight); this.showDelay = true; }
  openCancel(flight: Flight): void { this.selected.set(flight); this.showCancel = true; }
  onMutated(): void { this.search(); }

  canDelay(f: Flight): boolean {
    return f.status === FlightStatus.Scheduled || f.status === FlightStatus.Delayed;
  }

  canCancel(f: Flight): boolean {
    return f.status !== FlightStatus.Cancelled
        && f.status !== FlightStatus.Departed
        && f.status !== FlightStatus.Arrived;
  }

  statusLabel(s: number): string {
    switch (s) {
      case FlightStatus.Scheduled: return 'Scheduled';
      case FlightStatus.Delayed:   return 'Delayed';
      case FlightStatus.Departed:  return 'Departed';
      case FlightStatus.Arrived:   return 'Arrived';
      case FlightStatus.Cancelled: return 'Cancelled';
      default: return 'Unknown';
    }
  }

  statusSeverity(s: number): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (s) {
      case FlightStatus.Scheduled: return 'success';
      case FlightStatus.Delayed:   return 'warn';
      case FlightStatus.Departed:  return 'info';
      case FlightStatus.Arrived:   return 'info';
      case FlightStatus.Cancelled: return 'danger';
      default: return 'secondary';
    }
  }

  private toIsoDate(d: Date): string {
    const y = d.getFullYear();
    const m = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${y}-${m}-${day}`;
  }
}
'@

# ===========================================================================
# 5. Bookings page
# ===========================================================================
Write-Host ""
Write-Host "=== 5. bookings.page.ts ==="

Write-File "frontend/src/app/features/bookings/bookings.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe, DecimalPipe } from '@angular/common';
import { Router } from '@angular/router';
import { TableModule } from 'primeng/table';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { ToggleSwitchModule } from 'primeng/toggleswitch';
import { MessageService } from 'primeng/api';
import { Booking, BookingStatus } from '../../core/api/models/booking.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { BookingsService } from './bookings.service';
import { AdminService } from './admin.service';
import { CreateBookingDialogComponent } from './create-booking-dialog.component';

@Component({
  selector: 'app-bookings-page',
  standalone: true,
  imports: [
    FormsModule, DatePipe, DecimalPipe,
    TableModule, InputTextModule, TagModule, ToggleSwitchModule,
    CreateBookingDialogComponent
  ],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <h1>Bookings</h1>
          <p class="subtitle">Manage passenger bookings and confirmations</p>
        </div>
        <div class="actions">
          <div class="sim-toggle">
            <label>
              <p-toggleswitch [(ngModel)]="simulateFailure" (onChange)="toggleSimulation()"></p-toggleswitch>
              <span>Demo: fail next payment</span>
            </label>
          </div>
          <button class="btn btn-primary" type="button" (click)="showCreate = true">
            <i class="pi pi-plus"></i><span>Create booking</span>
          </button>
        </div>
      </div>

      <p-table
        [value]="bookings()"
        [loading]="loading()"
        [paginator]="true"
        [rows]="20"
        [rowsPerPageOptions]="[10, 20, 50]"
        [globalFilterFields]="['bookRef', 'passengerName', 'passengerId']"
        #dt
        styleClass="p-datatable-sm">

        <ng-template #caption>
          <div class="table-caption">
            <input pInputText type="text"
                   placeholder="Search by ref or passenger..."
                   (input)="dt.filterGlobal($any($event.target).value, 'contains')" />
            <span class="count">{{ bookings().length }} bookings</span>
          </div>
        </ng-template>

        <ng-template #header>
          <tr>
            <th pSortableColumn="bookRef">Ref <p-sort-icon field="bookRef"></p-sort-icon></th>
            <th pSortableColumn="passengerName">Passenger <p-sort-icon field="passengerName"></p-sort-icon></th>
            <th>Book date</th>
            <th>Total</th>
            <th>Tickets</th>
            <th>Status</th>
            <th style="width: 140px;">Actions</th>
          </tr>
        </ng-template>

        <ng-template #body let-booking>
          <tr>
            <td><strong>{{ booking.bookRef }}</strong></td>
            <td>
              {{ booking.passengerName }}
              <span class="muted">({{ booking.passengerId }})</span>
            </td>
            <td>{{ booking.bookDate | date:'short' }}</td>
            <td>{{ booking.totalAmount | number:'1.2-2' }} {{ booking.currency }}</td>
            <td>{{ booking.tickets.length }}</td>
            <td>
              <p-tag [value]="statusLabel(booking.status)"
                     [severity]="statusSeverity(booking.status)"></p-tag>
            </td>
            <td>
              <button class="btn btn-secondary btn-sm" type="button" (click)="openDetails(booking.id)">
                <i class="pi pi-external-link"></i><span>Open</span>
              </button>
            </td>
          </tr>
        </ng-template>

        <ng-template #emptymessage>
          <tr>
            <td colspan="7" class="empty">
              No bookings yet. Create one to get started.
            </td>
          </tr>
        </ng-template>
      </p-table>

      <app-create-booking-dialog
        [(visible)]="showCreate"
        (created)="onCreated($event)"></app-create-booking-dialog>
    </div>
  `,
  styles: [`
    .table-caption { display: flex; align-items: center; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }
    .count { color: var(--text-muted); font-size: 0.9rem; }
    .muted { color: var(--text-muted); font-size: 0.85rem; }
    .empty { text-align: center; padding: 2rem; color: var(--text-muted); }
    .sim-toggle label { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; color: var(--text-muted); cursor: pointer; }
  `]
})
export class BookingsPage implements OnInit {
  private readonly service = inject(BookingsService);
  private readonly admin = inject(AdminService);
  private readonly messages = inject(MessageService);
  private readonly router = inject(Router);

  readonly bookings = signal<Booking[]>([]);
  readonly loading = signal(false);
  simulateFailure = false;
  showCreate = false;

  ngOnInit(): void {
    this.load();
    this.loadSimulationState();
  }

  private load(): void {
    this.loading.set(true);
    this.service.list().subscribe({
      next: (resp) => {
        this.bookings.set(resp.items);
        this.loading.set(false);
      },
      error: (err: ApiError) => {
        this.loading.set(false);
        this.messages.add({ severity: 'error', summary: 'Failed to load bookings', detail: err.message });
      }
    });
  }

  private loadSimulationState(): void {
    this.admin.getSimulateFailure().subscribe({
      next: (s) => { this.simulateFailure = s.enabled; },
      error: () => { /* ignore if admin disabled */ }
    });
  }

  toggleSimulation(): void {
    this.admin.setSimulateFailure(this.simulateFailure).subscribe({
      next: (s) => {
        this.simulateFailure = s.enabled;
        this.messages.add({
          severity: s.enabled ? 'warn' : 'success',
          summary: s.enabled ? 'Demo mode: payment will fail after charge' : 'Demo mode disabled',
          detail: s.enabled
            ? 'Next confirm will trigger saga compensation.'
            : 'Payments behave normally.'
        });
      },
      error: (err: ApiError) => {
        this.messages.add({ severity: 'error', summary: 'Toggle failed', detail: err.message });
      }
    });
  }

  openDetails(id: string): void { this.router.navigate(['/bookings', id]); }

  onCreated(id: string): void {
    this.load();
    this.openDetails(id);
  }

  statusLabel(s: number): string {
    switch (s) {
      case BookingStatus.Pending:   return 'Pending';
      case BookingStatus.Confirmed: return 'Confirmed';
      case BookingStatus.Cancelled: return 'Cancelled';
      case BookingStatus.Expired:   return 'Expired';
      default: return 'Unknown';
    }
  }

  statusSeverity(s: number): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (s) {
      case BookingStatus.Pending:   return 'warn';
      case BookingStatus.Confirmed: return 'success';
      case BookingStatus.Cancelled: return 'danger';
      case BookingStatus.Expired:   return 'danger';
      default: return 'secondary';
    }
  }
}
'@

# ===========================================================================
# 6. Booking details page
# ===========================================================================
Write-Host ""
Write-Host "=== 6. booking-details.page.ts ==="

Write-File "frontend/src/app/features/bookings/booking-details.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe, DecimalPipe } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TableModule } from 'primeng/table';
import { TagModule } from 'primeng/tag';
import { MessageService } from 'primeng/api';
import { Booking, BookingStatus, ConfirmBookingResult } from '../../core/api/models/booking.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { BookingsService } from './bookings.service';
import { AddTicketDialogComponent } from './add-ticket-dialog.component';
import { CancelBookingDialogComponent } from './cancel-booking-dialog.component';

@Component({
  selector: 'app-booking-details-page',
  standalone: true,
  imports: [
    FormsModule, DatePipe, DecimalPipe, RouterLink,
    TableModule, TagModule,
    AddTicketDialogComponent, CancelBookingDialogComponent
  ],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <a routerLink="/bookings" class="back">
            <i class="pi pi-arrow-left"></i> Back to bookings
          </a>
          <h1>
            Booking {{ booking()?.bookRef }}
            @if (booking()) {
              <p-tag [value]="statusLabel(booking()!.status)"
                     [severity]="statusSeverity(booking()!.status)"></p-tag>
            }
          </h1>
        </div>
        <div class="actions">
          @if (canAddTicket()) {
            <button class="btn btn-secondary" type="button" (click)="showAddTicket = true">
              <i class="pi pi-plus"></i><span>Add ticket</span>
            </button>
          }
          @if (canConfirm()) {
            <button class="btn btn-success" type="button"
                    [disabled]="confirming()"
                    (click)="confirm()">
              @if (confirming()) {
                <i class="pi pi-spin pi-spinner"></i><span>Confirming...</span>
              } @else {
                <i class="pi pi-check"></i><span>Confirm booking</span>
              }
            </button>
          }
          @if (canCancel()) {
            <button class="btn btn-danger" type="button" (click)="showCancel = true">
              <i class="pi pi-times"></i><span>Cancel booking</span>
            </button>
          }
        </div>
      </div>

      @if (loading()) {
        <p>Loading...</p>
      } @else if (!booking()) {
        <p class="error">Booking not found.</p>
      } @else {
        <div class="info-grid">
          <div class="info-card">
            <div class="label">Passenger</div>
            <div class="value">{{ booking()!.passengerName }}</div>
            <div class="muted">ID: {{ booking()!.passengerId }}</div>
          </div>
          <div class="info-card">
            <div class="label">Book date</div>
            <div class="value">{{ booking()!.bookDate | date:'medium' }}</div>
          </div>
          <div class="info-card">
            <div class="label">Total amount</div>
            <div class="value">{{ booking()!.totalAmount | number:'1.2-2' }} {{ booking()!.currency }}</div>
          </div>
          <div class="info-card">
            <div class="label">Tickets</div>
            <div class="value">{{ booking()!.tickets.length }}</div>
          </div>
        </div>

        @if (sagaResult()) {
          <div class="saga-panel" [class.success]="sagaResult()!.confirmed" [class.failure]="!sagaResult()!.confirmed">
            <div class="saga-header">
              <i class="pi" [class.pi-check-circle]="sagaResult()!.confirmed"
                            [class.pi-exclamation-triangle]="!sagaResult()!.confirmed"></i>
              <strong>
                @if (sagaResult()!.confirmed) {
                  Saga completed: booking confirmed
                } @else {
                  Saga failed and compensated
                }
              </strong>
            </div>
            @if (!sagaResult()!.confirmed) {
              <div class="saga-reason">{{ sagaResult()!.failureReason }}</div>
              <ol class="saga-steps">
                <li class="ok">Verify flights</li>
                <li class="ok">Reserve seats</li>
                <li class="fail">Charge payment (failed)</li>
                <li class="compensate">Compensation: release seats</li>
                <li class="compensate">Compensation: refund payment (if charged)</li>
                <li class="compensate">Compensation: mark booking Expired</li>
              </ol>
            } @else {
              <ol class="saga-steps">
                <li class="ok">Verify flights</li>
                <li class="ok">Reserve seats</li>
                <li class="ok">Charge payment</li>
                <li class="ok">Mark booking Confirmed</li>
              </ol>
            }
            <button class="btn btn-secondary btn-sm" type="button" (click)="sagaResult.set(null)">
              <i class="pi pi-times"></i><span>Dismiss</span>
            </button>
          </div>
        }

        <h2>Tickets</h2>
        <p-table [value]="booking()!.tickets" styleClass="p-datatable-sm">
          <ng-template #header>
            <tr>
              <th>Ticket number</th>
              <th>Flight ID</th>
              <th>Amount</th>
            </tr>
          </ng-template>
          <ng-template #body let-ticket>
            <tr>
              <td><code>{{ ticket.ticketNo }}</code></td>
              <td><code class="muted">{{ ticket.flightId }}</code></td>
              <td>{{ ticket.amount | number:'1.2-2' }} {{ booking()!.currency }}</td>
            </tr>
          </ng-template>
          <ng-template #emptymessage>
            <tr>
              <td colspan="3" class="empty">No tickets yet. Add a ticket to continue.</td>
            </tr>
          </ng-template>
        </p-table>
      }

      <app-add-ticket-dialog
        [(visible)]="showAddTicket"
        [booking]="booking()"
        (added)="reload()"></app-add-ticket-dialog>

      <app-cancel-booking-dialog
        [(visible)]="showCancel"
        [booking]="booking()"
        (cancelled)="reload()"></app-cancel-booking-dialog>
    </div>
  `,
  styles: [`
    .back { display: inline-block; margin-bottom: 0.5rem; font-size: 0.9rem; }
    h1 { display: flex; align-items: center; gap: 0.75rem; margin: 0; font-size: 1.5rem; }
    h2 { margin-top: 2rem; font-size: 1.1rem; }
    .info-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }
    .info-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; }
    .info-card .label { color: var(--text-muted); font-size: 0.8rem; text-transform: uppercase; margin-bottom: 0.35rem; }
    .info-card .value { font-size: 1.1rem; font-weight: 600; }
    .info-card .muted { color: var(--text-muted); font-size: 0.85rem; margin-top: 0.25rem; }
    .muted { color: var(--text-muted); }
    .error { color: var(--danger); }
    .empty { text-align: center; padding: 2rem; color: var(--text-muted); }
    .saga-panel { border-radius: 8px; padding: 1rem 1.25rem; margin-bottom: 1.5rem; border: 1px solid; }
    .saga-panel.success { background: rgba(22,163,74,0.08); border-color: var(--success); }
    .saga-panel.failure { background: rgba(220,38,38,0.08); border-color: var(--danger); }
    .saga-header { display: flex; align-items: center; gap: 0.5rem; font-size: 1.05rem; margin-bottom: 0.5rem; }
    .saga-panel.success .saga-header .pi { color: var(--success); }
    .saga-panel.failure .saga-header .pi { color: var(--danger); }
    .saga-reason { color: var(--danger); margin-bottom: 0.75rem; }
    .saga-steps { margin: 0.5rem 0 1rem; padding-left: 1.25rem; }
    .saga-steps li { margin-bottom: 0.25rem; }
    .saga-steps li.ok { color: var(--text); }
    .saga-steps li.fail { color: var(--danger); font-weight: 600; }
    .saga-steps li.compensate { color: var(--warning); font-style: italic; }
  `]
})
export class BookingDetailsPage implements OnInit {
  private readonly service = inject(BookingsService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly messages = inject(MessageService);

  readonly booking = signal<Booking | null>(null);
  readonly loading = signal(false);
  readonly confirming = signal(false);
  readonly sagaResult = signal<ConfirmBookingResult | null>(null);

  showAddTicket = false;
  showCancel = false;

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id');
    if (!id) { this.router.navigate(['/bookings']); return; }
    this.load(id);
  }

  private load(id: string): void {
    this.loading.set(true);
    this.service.getById(id).subscribe({
      next: (b) => { this.booking.set(b); this.loading.set(false); },
      error: (err: ApiError) => {
        this.loading.set(false);
        this.messages.add({ severity: 'error', summary: 'Failed to load booking', detail: err.message });
      }
    });
  }

  reload(): void {
    const b = this.booking();
    if (b) this.load(b.id);
  }

  confirm(): void {
    const b = this.booking();
    if (!b) return;

    this.confirming.set(true);
    this.sagaResult.set(null);

    this.service.confirm(b.id).subscribe({
      next: (res) => {
        this.confirming.set(false);
        this.sagaResult.set(res);
        this.messages.add({ severity: 'success', summary: 'Booking confirmed', detail: `Saga completed for ${b.bookRef}.` });
        this.reload();
      },
      error: (err: ApiError) => {
        this.confirming.set(false);
        this.sagaResult.set({ bookingId: b.id, confirmed: false, failureReason: err.message });
        this.messages.add({ severity: 'error', summary: 'Saga failed - see details', detail: err.message });
        this.reload();
      }
    });
  }

  canAddTicket(): boolean { return this.booking()?.status === BookingStatus.Pending; }

  canConfirm(): boolean {
    const b = this.booking();
    return !!b && b.status === BookingStatus.Pending && b.tickets.length > 0;
  }

  canCancel(): boolean { return this.booking()?.status === BookingStatus.Pending; }

  statusLabel(s: number): string {
    switch (s) {
      case BookingStatus.Pending:   return 'Pending';
      case BookingStatus.Confirmed: return 'Confirmed';
      case BookingStatus.Cancelled: return 'Cancelled';
      case BookingStatus.Expired:   return 'Expired';
      default: return 'Unknown';
    }
  }

  statusSeverity(s: number): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (s) {
      case BookingStatus.Pending:   return 'warn';
      case BookingStatus.Confirmed: return 'success';
      case BookingStatus.Cancelled: return 'danger';
      case BookingStatus.Expired:   return 'danger';
      default: return 'secondary';
    }
  }
}
'@

# ===========================================================================
# 7-11. Dialogs - replace pButton in footers with .btn
# ===========================================================================
Write-Host ""
Write-Host "=== 7. dialogs ==="

# create-flight-dialog: replace pButton in footer
$cfd = Join-Path $root "frontend\src\app\features\flights\create-flight-dialog.component.ts"
$c = [System.IO.File]::ReadAllText($cfd)
$c = $c -replace '<button pButton type="button" label="Cancel" severity="secondary"\s+\(click\)="visible = false"></button>',
  '<button class="btn btn-secondary" type="button" (click)="visible = false"><i class="pi pi-times"></i><span>Cancel</span></button>'
$c = $c -replace '<button pButton type="button" label="Create"\s+\[loading\]="saving\(\)"\s+\(click\)="submit\(\)"></button>',
  '<button class="btn btn-primary" type="button" [disabled]="saving()" (click)="submit()">@if (saving()) { <i class="pi pi-spin pi-spinner"></i><span>Creating...</span> } @else { <i class="pi pi-check"></i><span>Create</span> }</button>'
[System.IO.File]::WriteAllText($cfd, $c, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + create-flight-dialog.component.ts"

# delay-flight-dialog
$dfd = Join-Path $root "frontend\src\app\features\flights\delay-flight-dialog.component.ts"
$c = [System.IO.File]::ReadAllText($dfd)
$c = $c -replace '<button pButton type="button" label="Cancel" severity="secondary"\s+\(click\)="visible = false"></button>',
  '<button class="btn btn-secondary" type="button" (click)="visible = false"><i class="pi pi-times"></i><span>Cancel</span></button>'
$c = $c -replace '<button pButton type="button" label="Delay"\s+\[loading\]="saving\(\)"\s+\(click\)="submit\(\)"></button>',
  '<button class="btn btn-warn" type="button" [disabled]="saving()" (click)="submit()">@if (saving()) { <i class="pi pi-spin pi-spinner"></i><span>Saving...</span> } @else { <i class="pi pi-clock"></i><span>Delay</span> }</button>'
[System.IO.File]::WriteAllText($dfd, $c, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + delay-flight-dialog.component.ts"

# cancel-flight-dialog
$cancelfd = Join-Path $root "frontend\src\app\features\flights\cancel-flight-dialog.component.ts"
$c = [System.IO.File]::ReadAllText($cancelfd)
$c = $c -replace '<button pButton type="button" label="Keep flight" severity="secondary"\s+\(click\)="visible = false"></button>',
  '<button class="btn btn-secondary" type="button" (click)="visible = false"><i class="pi pi-arrow-left"></i><span>Keep flight</span></button>'
$c = $c -replace '<button pButton type="button" label="Cancel flight" severity="danger"\s+\[loading\]="saving\(\)"\s+\(click\)="submit\(\)"></button>',
  '<button class="btn btn-danger" type="button" [disabled]="saving()" (click)="submit()">@if (saving()) { <i class="pi pi-spin pi-spinner"></i><span>Cancelling...</span> } @else { <i class="pi pi-times"></i><span>Cancel flight</span> }</button>'
[System.IO.File]::WriteAllText($cancelfd, $c, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + cancel-flight-dialog.component.ts"

# create-booking-dialog
$cbd = Join-Path $root "frontend\src\app\features\bookings\create-booking-dialog.component.ts"
$c = [System.IO.File]::ReadAllText($cbd)
$c = $c -replace '<button pButton type="button" label="Cancel" severity="secondary"\s+\(click\)="visible = false"></button>',
  '<button class="btn btn-secondary" type="button" (click)="visible = false"><i class="pi pi-times"></i><span>Cancel</span></button>'
$c = $c -replace '<button pButton type="button" label="Create"\s+\[loading\]="saving\(\)"\s+\(click\)="submit\(\)"></button>',
  '<button class="btn btn-primary" type="button" [disabled]="saving()" (click)="submit()">@if (saving()) { <i class="pi pi-spin pi-spinner"></i><span>Creating...</span> } @else { <i class="pi pi-check"></i><span>Create</span> }</button>'
[System.IO.File]::WriteAllText($cbd, $c, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + create-booking-dialog.component.ts"

# add-ticket-dialog
$atd = Join-Path $root "frontend\src\app\features\bookings\add-ticket-dialog.component.ts"
$c = [System.IO.File]::ReadAllText($atd)
$c = $c -replace '<button pButton type="button" label="Cancel" severity="secondary"\s+\(click\)="visible = false"></button>',
  '<button class="btn btn-secondary" type="button" (click)="visible = false"><i class="pi pi-times"></i><span>Cancel</span></button>'
$c = $c -replace '<button pButton type="button" label="Add ticket"\s+\[loading\]="saving\(\)"\s+\(click\)="submit\(\)"></button>',
  '<button class="btn btn-primary" type="button" [disabled]="saving()" (click)="submit()">@if (saving()) { <i class="pi pi-spin pi-spinner"></i><span>Adding...</span> } @else { <i class="pi pi-plus"></i><span>Add ticket</span> }</button>'
[System.IO.File]::WriteAllText($atd, $c, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + add-ticket-dialog.component.ts"

# cancel-booking-dialog
$canbd = Join-Path $root "frontend\src\app\features\bookings\cancel-booking-dialog.component.ts"
$c = [System.IO.File]::ReadAllText($canbd)
$c = $c -replace '<button pButton type="button" label="Keep booking" severity="secondary"\s+\(click\)="visible = false"></button>',
  '<button class="btn btn-secondary" type="button" (click)="visible = false"><i class="pi pi-arrow-left"></i><span>Keep booking</span></button>'
$c = $c -replace '<button pButton type="button" label="Cancel booking" severity="danger"\s+\[loading\]="saving\(\)"\s+\(click\)="submit\(\)"></button>',
  '<button class="btn btn-danger" type="button" [disabled]="saving()" (click)="submit()">@if (saving()) { <i class="pi pi-spin pi-spinner"></i><span>Cancelling...</span> } @else { <i class="pi pi-times"></i><span>Cancel booking</span> }</button>'
[System.IO.File]::WriteAllText($canbd, $c, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + cancel-booking-dialog.component.ts"

# ===========================================================================
# 12. Build
# ===========================================================================
Write-Host ""
Write-Host "=== 12. Build frontend ==="

Push-Location (Join-Path $root "frontend")
try {
    cmd /c "npm run build 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "FRONTEND BUILD FAILED - see errors above" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + frontend build ok" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Restart frontend:" -ForegroundColor Yellow
Write-Host "  cd frontend; npm start"
Write-Host ""
Write-Host "Что изменилось:" -ForegroundColor Yellow
Write-Host "  - Все кнопки теперь plain HTML с классом .btn"
Write-Host "  - Текст ВСЕГДА виден: 'Sync from source', 'Create flight', 'Delay', 'Cancel', 'Open', 'Confirm booking' и т.д."
Write-Host "  - Иконка + текст рядом"
Write-Host "  - Loading state: иконка spinner + 'Syncing...' / 'Creating...' / 'Confirming...'"
Write-Host "  - Никаких PrimeNG pButton — они больше не могут сломать отображение"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "refactor(frontend): plain HTML buttons with guaranteed visible text"'
Write-Host "  git push"
Write-Host ""