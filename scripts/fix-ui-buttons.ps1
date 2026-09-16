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
Write-Host "=== Fix UI: buttons with text + tooltips ==="
Write-Host ""

# ===========================================================================
# 1. Header - theme button with label
# ===========================================================================
Write-Host "=== 1. header.component.ts ==="

Write-File "frontend/src/app/core/layout/header.component.ts" @'
import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { ButtonModule } from 'primeng/button';
import { TooltipModule } from 'primeng/tooltip';
import { HealthService } from '../services/health.service';
import { ThemeService } from '../services/theme.service';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [ButtonModule, TooltipModule],
  template: `
    <header class="header">
      <div class="health" [class.online]="health.isOnline()" [class.offline]="!health.isOnline()"
           [pTooltip]="health.isOnline() ? 'API is reachable' : 'API is not reachable. Start the backend.'"
           tooltipPosition="bottom">
        <span class="dot"></span>
        <span>{{ health.isOnline() ? 'API online' : 'API offline' }}</span>
      </div>
      <button pButton
              type="button"
              [icon]="theme.isDark() ? 'pi pi-sun' : 'pi pi-moon'"
              [label]="theme.isDark() ? 'Light theme' : 'Dark theme'"
              severity="secondary"
              outlined
              (click)="theme.toggle()"
              [pTooltip]="theme.isDark() ? 'Switch to light theme' : 'Switch to dark theme'"
              tooltipPosition="bottom"></button>
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
      cursor: default;
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

# ===========================================================================
# 2. Flights page - Delay / Cancel with labels
# ===========================================================================
Write-Host ""
Write-Host "=== 2. flights.page.ts ==="

Write-File "frontend/src/app/features/flights/flights.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe } from '@angular/common';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { DatePickerModule } from 'primeng/datepicker';
import { TagModule } from 'primeng/tag';
import { TooltipModule } from 'primeng/tooltip';
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
    FormsModule, DatePipe, TableModule, ButtonModule, InputTextModule,
    DatePickerModule, TagModule, TooltipModule,
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
          <button pButton type="button" icon="pi pi-plus" label="Create flight"
                  pTooltip="Schedule a new flight"
                  tooltipPosition="bottom"
                  (click)="showCreate = true"></button>
        </div>
      </div>

      <div class="filters">
        <input pInputText [(ngModel)]="from" placeholder="From (e.g. SVO)" maxlength="3"
               pTooltip="Departure airport (IATA code)" tooltipPosition="top" />
        <input pInputText [(ngModel)]="to" placeholder="To (e.g. OVB)" maxlength="3"
               pTooltip="Arrival airport (IATA code)" tooltipPosition="top" />
        <p-datepicker [(ngModel)]="date" dateFormat="yy-mm-dd" [showIcon]="true"
                      pTooltip="Departure date" tooltipPosition="top"></p-datepicker>
        <button pButton type="button" icon="pi pi-search" label="Search"
                [loading]="loading()"
                pTooltip="Search flights for the selected route and date"
                tooltipPosition="bottom"
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
              <button pButton type="button" icon="pi pi-clock" label="Delay"
                      severity="warn" outlined size="small"
                      [disabled]="!canDelay(flight)"
                      (click)="openDelay(flight)"
                      [pTooltip]="canDelay(flight) ? 'Postpone departure and arrival times' : 'Flight cannot be delayed in current status'"
                      tooltipPosition="left"></button>
              <button pButton type="button" icon="pi pi-times" label="Cancel"
                      severity="danger" outlined size="small"
                      [disabled]="!canCancel(flight)"
                      (click)="openCancel(flight)"
                      [pTooltip]="canCancel(flight) ? 'Cancel this flight' : 'Flight cannot be cancelled in current status'"
                      tooltipPosition="left"></button>
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
    .actions-cell { display: flex; gap: 0.5rem; flex-wrap: nowrap; }
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
# 3. Bookings page - Details with label
# ===========================================================================
Write-Host ""
Write-Host "=== 3. bookings.page.ts ==="

Write-File "frontend/src/app/features/bookings/bookings.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe, DecimalPipe } from '@angular/common';
import { Router } from '@angular/router';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { ToggleSwitchModule } from 'primeng/toggleswitch';
import { TooltipModule } from 'primeng/tooltip';
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
    TableModule, ButtonModule, InputTextModule, TagModule, ToggleSwitchModule, TooltipModule,
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
              <span
                pTooltip="When enabled, the next Confirm will trigger saga compensation: charge succeeds, then fails; refund + release seats + Expired."
                tooltipPosition="bottom">
                Demo: fail next payment
              </span>
            </label>
          </div>
          <button pButton type="button" icon="pi pi-plus" label="Create booking"
                  pTooltip="Create a new draft booking"
                  tooltipPosition="bottom"
                  (click)="showCreate = true"></button>
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
            <th style="width: 160px;">Actions</th>
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
              <button pButton type="button" icon="pi pi-external-link" label="Open"
                      severity="secondary" outlined size="small"
                      (click)="openDetails(booking.id)"
                      pTooltip="View details, add tickets, confirm or cancel"
                      tooltipPosition="left"></button>
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
    .sim-toggle label { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; color: var(--text-muted); cursor: help; }
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
      error: () => { /* admin endpoint may be disabled outside dev - ignore */ }
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

  openDetails(id: string): void {
    this.router.navigate(['/bookings', id]);
  }

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
# 4. Booking details page - tooltips on action buttons
# ===========================================================================
Write-Host ""
Write-Host "=== 4. booking-details.page.ts ==="

Write-File "frontend/src/app/features/bookings/booking-details.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe, DecimalPipe } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { TooltipModule } from 'primeng/tooltip';
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
    TableModule, ButtonModule, TagModule, TooltipModule,
    AddTicketDialogComponent, CancelBookingDialogComponent
  ],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <a routerLink="/bookings" class="back"
             pTooltip="Back to the bookings list" tooltipPosition="right">
            <i class="pi pi-arrow-left"></i> Back to bookings
          </a>
          <h1>
            Booking {{ booking()?.bookRef }}
            @if (booking()) {
              <p-tag [value]="statusLabel(booking()!.status)"
                     [severity]="statusSeverity(booking()!.status)"
                     styleClass="ml-2"></p-tag>
            }
          </h1>
        </div>
        <div class="actions">
          @if (canAddTicket()) {
            <button pButton type="button" icon="pi pi-plus" label="Add ticket"
                    pTooltip="Add a passenger ticket to this booking"
                    tooltipPosition="bottom"
                    (click)="showAddTicket = true"></button>
          }
          @if (canConfirm()) {
            <button pButton type="button" icon="pi pi-check" label="Confirm booking"
                    severity="success"
                    [loading]="confirming()"
                    pTooltip="Run the confirmation saga: reserve seats, charge payment, confirm"
                    tooltipPosition="bottom"
                    (click)="confirm()"></button>
          }
          @if (canCancel()) {
            <button pButton type="button" icon="pi pi-times" label="Cancel booking"
                    severity="danger" outlined
                    pTooltip="Cancel this booking and release any reserved seats"
                    tooltipPosition="bottom"
                    (click)="showCancel = true"></button>
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
            <button pButton type="button" text icon="pi pi-times" label="Dismiss"
                    pTooltip="Hide this panel" tooltipPosition="top"
                    (click)="sagaResult.set(null)"></button>
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
    h1 { display: flex; align-items: center; gap: 0.5rem; margin: 0; font-size: 1.5rem; }
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
    .saga-steps { margin: 0.5rem 0 0; padding-left: 1.25rem; }
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
    if (!id) {
      this.router.navigate(['/bookings']);
      return;
    }
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
        this.messages.add({
          severity: 'success',
          summary: 'Booking confirmed',
          detail: `Saga completed for ${b.bookRef}.`
        });
        this.reload();
      },
      error: (err: ApiError) => {
        this.confirming.set(false);
        this.sagaResult.set({
          bookingId: b.id,
          confirmed: false,
          failureReason: err.message
        });
        this.messages.add({
          severity: 'error',
          summary: 'Saga failed - see details',
          detail: err.message
        });
        this.reload();
      }
    });
  }

  canAddTicket(): boolean {
    return this.booking()?.status === BookingStatus.Pending;
  }

  canConfirm(): boolean {
    const b = this.booking();
    return !!b && b.status === BookingStatus.Pending && b.tickets.length > 0;
  }

  canCancel(): boolean {
    return this.booking()?.status === BookingStatus.Pending;
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
# 5. Airports page - tooltips on Sync and search
# ===========================================================================
Write-Host ""
Write-Host "=== 5. airports.page.ts ==="

Write-File "frontend/src/app/features/airports/airports.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DecimalPipe } from '@angular/common';
import { TableModule, SortIcon } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { TooltipModule } from 'primeng/tooltip';
import { MessageService } from 'primeng/api';
import { Airport } from '../../core/api/models/airport.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { AirportsService } from './airports.service';

@Component({
  selector: 'app-airports-page',
  standalone: true,
  imports: [FormsModule, DecimalPipe, TableModule, SortIcon, ButtonModule, InputTextModule, TagModule, TooltipModule],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <h1>Airports</h1>
          <p class="subtitle">Reference data synchronized from the external source</p>
        </div>
        <div class="actions">
          <button pButton type="button" icon="pi pi-refresh"
                  label="Sync from source"
                  [loading]="syncing()"
                  pTooltip="Import or update airports from the external bookings database"
                  tooltipPosition="bottom"
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
                   pTooltip="Filter the table by any column"
                   tooltipPosition="top"
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
# 6. Build
# ===========================================================================
Write-Host ""
Write-Host "=== 6. Build frontend ==="

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
Write-Host "  - Header: кнопка темы теперь с текстом Light/Dark theme"
Write-Host "  - Flights: Delay и Cancel с текстом + tooltips"
Write-Host "  - Bookings: Open с текстом + tooltips"
Write-Host "  - Booking details: Confirm booking, Cancel booking с текстом"
Write-Host "  - Airports: Sync from source (переименована)"
Write-Host "  - Все иконки-кнопки имеют tooltip при наведении"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "fix(frontend): labels and tooltips on all action buttons"'
Write-Host "  git push"
Write-Host ""