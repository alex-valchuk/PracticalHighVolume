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
Write-Host "=== SPEC-004 / 4.2 - Airports + Flights (PrimeNG 22 API) ==="
Write-Host ""

# ===========================================================================
# 1. Install @primeng/themes
# ===========================================================================
Write-Host "=== 1. Install @primeng/themes ==="

Push-Location (Join-Path $root "frontend")
try {
    cmd /c "npm install @primeng/themes --save --legacy-peer-deps 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  npm install @primeng/themes failed" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + @primeng/themes installed" -ForegroundColor Green
} finally {
    Pop-Location
}

# ===========================================================================
# 2. styles.scss - minimal, theme comes from providePrimeNG
# ===========================================================================
Write-Host ""
Write-Host "=== 2. styles.scss ==="

Write-File "frontend/src/styles.scss" @'
@import "primeicons/primeicons.css";

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
'@

# ===========================================================================
# 3. app.config.ts - new PrimeNG theming API
# ===========================================================================
Write-Host ""
Write-Host "=== 3. app.config.ts ==="

Write-File "frontend/src/app/app.config.ts" @'
import { ApplicationConfig, provideZonelessChangeDetection } from '@angular/core';
import { provideRouter } from '@angular/router';
import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';
import { providePrimeNG } from 'primeng/config';
import Aura from '@primeng/themes/aura';
import { MessageService, ConfirmationService } from 'primeng/api';
import { routes } from './app.routes';
import { apiErrorInterceptor } from './core/api/error.interceptor';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZonelessChangeDetection(),
    provideRouter(routes),
    provideHttpClient(withInterceptors([apiErrorInterceptor])),
    provideAnimationsAsync(),
    providePrimeNG({
      theme: {
        preset: Aura,
        options: {
          darkModeSelector: '.dark'
        }
      }
    }),
    MessageService,
    ConfirmationService
  ]
};
'@

# ===========================================================================
# 4. app.component.ts
# ===========================================================================
Write-Host ""
Write-Host "=== 4. app.component.ts ==="

Write-File "frontend/src/app/app.component.ts" @'
import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { ToastModule } from 'primeng/toast';
import { ConfirmDialogModule } from 'primeng/confirmdialog';
import { SidebarComponent } from './core/layout/sidebar.component';
import { HeaderComponent } from './core/layout/header.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, SidebarComponent, HeaderComponent, ToastModule, ConfirmDialogModule],
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
    <p-toast position="top-right"></p-toast>
    <p-confirmDialog></p-confirmDialog>
  `,
  styles: [`
    .app-shell { display: flex; min-height: 100vh; }
    .app-main { flex: 1; display: flex; flex-direction: column; min-width: 0; }
    .app-content { flex: 1; padding: 1.5rem 2rem; overflow-y: auto; }
  `]
})
export class AppComponent {}
'@

# ===========================================================================
# 5. Airports feature
# ===========================================================================
Write-Host ""
Write-Host "=== 5. Airports ==="

Write-File "frontend/src/app/features/airports/airports.service.ts" @'
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';
import { Airport, AirportListResponse } from '../../core/api/models/airport.model';

export interface SyncAirportsResult {
  read: number;
  created: number;
  updated: number;
  skipped: number;
}

@Injectable({ providedIn: 'root' })
export class AirportsService {
  private readonly api = inject(ApiService);

  list(page = 1, pageSize = 500): Observable<AirportListResponse> {
    return this.api.get<AirportListResponse>('/flight-catalog/airports', { page, pageSize });
  }

  getByCode(code: string): Observable<Airport> {
    return this.api.get<Airport>(`/flight-catalog/airports/${code}`);
  }

  sync(): Observable<SyncAirportsResult> {
    return this.api.post<SyncAirportsResult>('/flight-catalog/airports/sync', {});
  }
}
'@

Write-File "frontend/src/app/features/airports/airports.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DecimalPipe } from '@angular/common';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { MessageService } from 'primeng/api';
import { Airport } from '../../core/api/models/airport.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { AirportsService } from './airports.service';

@Component({
  selector: 'app-airports-page',
  standalone: true,
  imports: [FormsModule, DecimalPipe, TableModule, ButtonModule, InputTextModule, TagModule],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <h1>Airports</h1>
          <p class="subtitle">Reference data synchronized from the external source</p>
        </div>
        <div class="actions">
          <button pButton type="button" icon="pi pi-refresh"
                  label="Sync now"
                  [loading]="syncing()"
                  (click)="sync()"></button>
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
            <th pSortableColumn="code">Code <p-sortIcon field="code"></p-sortIcon></th>
            <th pSortableColumn="name">Name <p-sortIcon field="name"></p-sortIcon></th>
            <th pSortableColumn="city">City <p-sortIcon field="city"></p-sortIcon></th>
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
              No airports. Click "Sync now" to import from the external source.
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
# 6. Flights
# ===========================================================================
Write-Host ""
Write-Host "=== 6. Flights ==="

Write-File "frontend/src/app/features/flights/flights.service.ts" @'
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';
import {
  Flight,
  CreateFlightRequest,
  DelayFlightRequest,
  CancelFlightRequest
} from '../../core/api/models/flight.model';

@Injectable({ providedIn: 'root' })
export class FlightsService {
  private readonly api = inject(ApiService);

  search(from: string, to: string, date: string): Observable<Flight[]> {
    return this.api.get<Flight[]>('/flight-catalog/flights', { from, to, date });
  }

  getById(id: string): Observable<Flight> {
    return this.api.get<Flight>(`/flight-catalog/flights/${id}`);
  }

  create(req: CreateFlightRequest): Observable<{ id: string }> {
    return this.api.post<{ id: string }>('/flight-catalog/flights', req);
  }

  delay(id: string, req: DelayFlightRequest): Observable<void> {
    return this.api.post<void>(`/flight-catalog/flights/${id}/delay`, req);
  }

  cancel(id: string, req: CancelFlightRequest): Observable<void> {
    return this.api.post<void>(`/flight-catalog/flights/${id}/cancel`, req);
  }
}
'@

Write-File "frontend/src/app/features/flights/create-flight-dialog.component.ts" @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { DatePickerModule } from 'primeng/datepicker';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { CreateFlightRequest } from '../../core/api/models/flight.model';
import { FlightsService } from './flights.service';

@Component({
  selector: 'app-create-flight-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, ButtonModule, InputTextModule, DatePickerModule],
  template: `
    <p-dialog
      header="Create flight"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '520px' }"
      (onHide)="reset()">

      <div class="form-grid">
        <label>Flight number</label>
        <input pInputText [(ngModel)]="model.flightNumber" placeholder="PG-0421" />

        <label>Departure airport</label>
        <input pInputText [(ngModel)]="model.departureAirport" placeholder="SVO" maxlength="3" />

        <label>Arrival airport</label>
        <input pInputText [(ngModel)]="model.arrivalAirport" placeholder="OVB" maxlength="3" />

        <label>Departure</label>
        <p-datepicker [(ngModel)]="departureDate" [showTime]="true" dateFormat="yy-mm-dd"></p-datepicker>

        <label>Arrival</label>
        <p-datepicker [(ngModel)]="arrivalDate" [showTime]="true" dateFormat="yy-mm-dd"></p-datepicker>

        <label>Aircraft model</label>
        <input pInputText [(ngModel)]="model.aircraftModel" placeholder="Airbus A320" />
      </div>

      <ng-template #footer>
        <button pButton type="button" label="Cancel" severity="secondary"
                (click)="visible = false"></button>
        <button pButton type="button" label="Create"
                [loading]="saving()"
                (click)="submit()"></button>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 0.75rem 1rem; align-items: center; padding: 0.5rem 0; }
    .form-grid label { color: var(--text-muted); font-size: 0.9rem; }
  `]
})
export class CreateFlightDialogComponent {
  @Input() visible = false;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() created = new EventEmitter<string>();

  private readonly service = inject(FlightsService);
  private readonly messages = inject(MessageService);

  model: CreateFlightRequest = this.empty();
  departureDate: Date | null = null;
  arrivalDate: Date | null = null;
  readonly saving = signal(false);

  private empty(): CreateFlightRequest {
    return {
      flightNumber: '', departureAirport: '', arrivalAirport: '',
      departure: '', arrival: '', aircraftModel: ''
    };
  }

  reset(): void {
    this.model = this.empty();
    this.departureDate = null;
    this.arrivalDate = null;
  }

  submit(): void {
    if (!this.departureDate || !this.arrivalDate) {
      this.messages.add({ severity: 'warn', summary: 'Missing dates', detail: 'Select departure and arrival dates.' });
      return;
    }

    const req: CreateFlightRequest = {
      ...this.model,
      departure: this.departureDate.toISOString(),
      arrival: this.arrivalDate.toISOString()
    };

    this.saving.set(true);
    this.service.create(req).subscribe({
      next: (resp) => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Flight created', detail: `Flight ${req.flightNumber} scheduled.` });
        this.visible = false;
        this.visibleChange.emit(false);
        this.created.emit(resp.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Create failed', detail: err.message });
      }
    });
  }
}
'@

Write-File "frontend/src/app/features/flights/delay-flight-dialog.component.ts" @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { ButtonModule } from 'primeng/button';
import { DatePickerModule } from 'primeng/datepicker';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { DelayFlightRequest, Flight } from '../../core/api/models/flight.model';
import { FlightsService } from './flights.service';

@Component({
  selector: 'app-delay-flight-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, ButtonModule, DatePickerModule],
  template: `
    <p-dialog
      header="Delay flight"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '480px' }"
      (onHide)="reset()">

      <p class="hint">
        Flight <strong>{{ flight?.flightNumber }}</strong>
        ({{ flight?.departureAirport }} -> {{ flight?.arrivalAirport }})
      </p>

      <div class="form-grid">
        <label>New departure</label>
        <p-datepicker [(ngModel)]="newDeparture" [showTime]="true" dateFormat="yy-mm-dd"></p-datepicker>

        <label>New arrival</label>
        <p-datepicker [(ngModel)]="newArrival" [showTime]="true" dateFormat="yy-mm-dd"></p-datepicker>
      </div>

      <ng-template #footer>
        <button pButton type="button" label="Cancel" severity="secondary"
                (click)="visible = false"></button>
        <button pButton type="button" label="Delay"
                [loading]="saving()"
                (click)="submit()"></button>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .hint { color: var(--text-muted); margin: 0 0 1rem; }
    .form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 0.75rem 1rem; align-items: center; padding: 0.5rem 0; }
    .form-grid label { color: var(--text-muted); font-size: 0.9rem; }
  `]
})
export class DelayFlightDialogComponent {
  @Input() visible = false;
  @Input() flight: Flight | null = null;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() delayed = new EventEmitter<string>();

  private readonly service = inject(FlightsService);
  private readonly messages = inject(MessageService);

  newDeparture: Date | null = null;
  newArrival: Date | null = null;
  readonly saving = signal(false);

  reset(): void {
    this.newDeparture = null;
    this.newArrival = null;
  }

  submit(): void {
    if (!this.flight) return;
    if (!this.newDeparture || !this.newArrival) {
      this.messages.add({ severity: 'warn', summary: 'Missing dates', detail: 'Select both dates.' });
      return;
    }

    const req: DelayFlightRequest = {
      newDeparture: this.newDeparture.toISOString(),
      newArrival: this.newArrival.toISOString()
    };

    this.saving.set(true);
    this.service.delay(this.flight.id, req).subscribe({
      next: () => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Flight delayed', detail: `Flight ${this.flight!.flightNumber} delayed.` });
        this.visible = false;
        this.visibleChange.emit(false);
        this.delayed.emit(this.flight!.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Delay failed', detail: err.message });
      }
    });
  }
}
'@

Write-File "frontend/src/app/features/flights/cancel-flight-dialog.component.ts" @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { ButtonModule } from 'primeng/button';
import { TextareaModule } from 'primeng/textarea';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { Flight } from '../../core/api/models/flight.model';
import { FlightsService } from './flights.service';

@Component({
  selector: 'app-cancel-flight-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, ButtonModule, TextareaModule],
  template: `
    <p-dialog
      header="Cancel flight"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '480px' }"
      (onHide)="reset()">

      <p class="hint">
        Cancel flight <strong>{{ flight?.flightNumber }}</strong>? This cannot be undone.
      </p>

      <textarea pTextarea [(ngModel)]="reason" rows="3"
                placeholder="Cancellation reason"
                style="width: 100%;"></textarea>

      <ng-template #footer>
        <button pButton type="button" label="Keep flight" severity="secondary"
                (click)="visible = false"></button>
        <button pButton type="button" label="Cancel flight" severity="danger"
                [loading]="saving()"
                (click)="submit()"></button>
      </ng-template>
    </p-dialog>
  `,
  styles: [`.hint { color: var(--text-muted); margin: 0 0 1rem; }`]
})
export class CancelFlightDialogComponent {
  @Input() visible = false;
  @Input() flight: Flight | null = null;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() cancelled = new EventEmitter<string>();

  private readonly service = inject(FlightsService);
  private readonly messages = inject(MessageService);

  reason = '';
  readonly saving = signal(false);

  reset(): void { this.reason = ''; }

  submit(): void {
    if (!this.flight) return;
    if (!this.reason.trim()) {
      this.messages.add({ severity: 'warn', summary: 'Reason required', detail: 'Enter a reason.' });
      return;
    }

    this.saving.set(true);
    this.service.cancel(this.flight.id, { reason: this.reason.trim() }).subscribe({
      next: () => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Flight cancelled', detail: `Flight ${this.flight!.flightNumber} cancelled.` });
        this.visible = false;
        this.visibleChange.emit(false);
        this.cancelled.emit(this.flight!.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Cancel failed', detail: err.message });
      }
    });
  }
}
'@

Write-File "frontend/src/app/features/flights/flights.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { DatePickerModule } from 'primeng/datepicker';
import { TagModule } from 'primeng/tag';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { Flight, FlightStatus } from '../../core/api/models/booking.model';
import { FlightsService } from './flights.service';
import { CreateFlightDialogComponent } from './create-flight-dialog.component';
import { DelayFlightDialogComponent } from './delay-flight-dialog.component';
import { CancelFlightDialogComponent } from './cancel-flight-dialog.component';

@Component({
  selector: 'app-flights-page',
  standalone: true,
  imports: [
    FormsModule, DatePipe, TableModule, ButtonModule, InputTextModule,
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
          <button pButton type="button" icon="pi pi-plus" label="Create"
                  (click)="showCreate = true"></button>
        </div>
      </div>

      <div class="filters">
        <input pInputText [(ngModel)]="from" placeholder="From (e.g. SVO)" maxlength="3" />
        <input pInputText [(ngModel)]="to" placeholder="To (e.g. OVB)" maxlength="3" />
        <p-datepicker [(ngModel)]="date" dateFormat="yy-mm-dd" [showIcon]="true"></p-datepicker>
        <button pButton type="button" icon="pi pi-search" label="Search"
                [loading]="loading()"
                (click)="search()"></button>
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
            <th style="width: 140px;">Actions</th>
          </tr>
        </ng-template>

        <ng-template #body let-flight>
          <tr>
            <td><strong>{{ flight.flightNumber }}</strong></td>
            <td>
              {{ flight.departureAirport }}
              <span class="muted" *ngIf="flight.departureAirportName">({{ flight.departureAirportName }})</span>
              <i class="pi pi-arrow-right" style="font-size: 0.7rem; margin: 0 0.35rem;"></i>
              {{ flight.arrivalAirport }}
              <span class="muted" *ngIf="flight.arrivalAirportName">({{ flight.arrivalAirportName }})</span>
            </td>
            <td>{{ flight.scheduledDeparture | date:'short' }}</td>
            <td>{{ flight.scheduledArrival | date:'short' }}</td>
            <td>
              <p-tag [value]="statusLabel(flight.status)"
                     [severity]="statusSeverity(flight.status)"></p-tag>
            </td>
            <td>{{ flight.aircraftModel }}</td>
            <td>
              <button pButton type="button" icon="pi pi-clock"
                      severity="warn" text
                      [disabled]="!canDelay(flight)"
                      (click)="openDelay(flight)"
                      title="Delay"></button>
              <button pButton type="button" icon="pi pi-times"
                      severity="danger" text
                      [disabled]="!canCancel(flight)"
                      (click)="openCancel(flight)"
                      title="Cancel"></button>
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
# 7. Build
# ===========================================================================
Write-Host ""
Write-Host "=== 7. Build frontend ==="

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
Write-Host "Restart both:" -ForegroundColor Yellow
Write-Host "  Terminal 1: dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  Terminal 2: cd frontend; npm start"
Write-Host ""
Write-Host "Open http://localhost:4200" -ForegroundColor Yellow
Write-Host ""