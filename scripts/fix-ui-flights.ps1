$root = (Get-Location).Path
$full = Join-Path $root "frontend\src\app\features\flights\flights.page.ts"

$content = @'
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

[System.IO.File]::WriteAllText($full, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host ("  + updated " + $full) -ForegroundColor Green

Write-Host ""
Write-Host "=== Build ==="

Push-Location (Join-Path $root "frontend")
try {
    cmd /c "npm run build 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host "BUILD FAILED" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + build ok" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "DONE. Restart frontend:" -ForegroundColor Green
Write-Host "  cd frontend; npm start"
Write-Host ""
Write-Host "Check Flights page:" -ForegroundColor Yellow
Write-Host "  - 'Create flight' button with text"
Write-Host "  - 'Search' button with text"
Write-Host "  - In table Actions column: 'Delay' and 'Cancel' buttons with text"
Write-Host ""