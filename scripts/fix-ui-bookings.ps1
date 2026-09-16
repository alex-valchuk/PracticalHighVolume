$root = (Get-Location).Path

function Save-Utf8 {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path.Replace($root, ".")) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 1. bookings.page.ts
# ---------------------------------------------------------------------------
$p1 = Join-Path $root "frontend\src\app\features\bookings\bookings.page.ts"
$c1 = @'
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
Save-Utf8 $p1 $c1

# ---------------------------------------------------------------------------
# 2. booking-details.page.ts
# ---------------------------------------------------------------------------
$p2 = Join-Path $root "frontend\src\app\features\bookings\booking-details.page.ts"
$c2 = @'
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
Save-Utf8 $p2 $c2

# ---------------------------------------------------------------------------
# 3. create-booking-dialog.component.ts
# ---------------------------------------------------------------------------
$p3 = Join-Path $root "frontend\src\app\features\bookings\create-booking-dialog.component.ts"
$c3 = @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { InputTextModule } from 'primeng/inputtext';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { CreateBookingRequest } from '../../core/api/models/booking.model';
import { BookingsService } from './bookings.service';

@Component({
  selector: 'app-create-booking-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, InputTextModule],
  template: `
    <p-dialog
      header="Create booking"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '480px' }"
      (onHide)="reset()">

      <div class="form-grid">
        <label>Passenger ID</label>
        <input pInputText [(ngModel)]="model.passengerId" placeholder="1234567890" maxlength="20" />

        <label>Passenger name</label>
        <input pInputText [(ngModel)]="model.passengerName" placeholder="IVANOV IVAN" maxlength="200" />

        <label>Currency</label>
        <input pInputText [(ngModel)]="model.currency" placeholder="RUB" maxlength="3" />
      </div>

      <ng-template #footer>
        <div class="dialog-footer">
          <button class="btn btn-secondary" type="button" (click)="visible = false">
            <i class="pi pi-times"></i><span>Cancel</span>
          </button>
          <button class="btn btn-primary" type="button" [disabled]="saving()" (click)="submit()">
            @if (saving()) {
              <i class="pi pi-spin pi-spinner"></i><span>Creating...</span>
            } @else {
              <i class="pi pi-check"></i><span>Create</span>
            }
          </button>
        </div>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 0.75rem 1rem; align-items: center; padding: 0.5rem 0; }
    .form-grid label { color: var(--text-muted); font-size: 0.9rem; }
    .dialog-footer { display: flex; justify-content: flex-end; gap: 0.5rem; }
  `]
})
export class CreateBookingDialogComponent {
  @Input() visible = false;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() created = new EventEmitter<string>();

  private readonly service = inject(BookingsService);
  private readonly messages = inject(MessageService);

  model: CreateBookingRequest = this.empty();
  readonly saving = signal(false);

  private empty(): CreateBookingRequest {
    return { passengerId: '', passengerName: '', currency: 'RUB' };
  }

  reset(): void { this.model = this.empty(); }

  submit(): void {
    if (!this.model.passengerId || !this.model.passengerName || !this.model.currency) {
      this.messages.add({ severity: 'warn', summary: 'Missing fields', detail: 'Fill all fields.' });
      return;
    }

    this.saving.set(true);
    this.service.create(this.model).subscribe({
      next: (resp) => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Booking created', detail: 'Draft booking created.' });
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
Save-Utf8 $p3 $c3

# ---------------------------------------------------------------------------
# 4. add-ticket-dialog.component.ts
# ---------------------------------------------------------------------------
$p4 = Join-Path $root "frontend\src\app\features\bookings\add-ticket-dialog.component.ts"
$c4 = @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { InputTextModule } from 'primeng/inputtext';
import { InputNumberModule } from 'primeng/inputnumber';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { AddTicketRequest, Booking } from '../../core/api/models/booking.model';
import { BookingsService } from './bookings.service';

@Component({
  selector: 'app-add-ticket-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, InputTextModule, InputNumberModule],
  template: `
    <p-dialog
      header="Add ticket"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '520px' }"
      (onHide)="reset()">

      <p class="hint">
        Booking <strong>{{ booking?.bookRef }}</strong>
      </p>

      <div class="form-grid">
        <label>Flight ID</label>
        <input pInputText [(ngModel)]="model.flightId" placeholder="GUID of the flight" />

        <label>Passenger ID</label>
        <input pInputText [(ngModel)]="model.passengerId" placeholder="9999999999" maxlength="20" />

        <label>Passenger name</label>
        <input pInputText [(ngModel)]="model.passengerName" placeholder="PETROV PETR" maxlength="200" />

        <label>Amount</label>
        <p-inputnumber [(ngModel)]="model.amount"
                       [minFractionDigits]="2"
                       [maxFractionDigits]="2"></p-inputnumber>
      </div>

      <small class="tip">
        Tip: get a flight ID from the Flights page or from Scalar.
      </small>

      <ng-template #footer>
        <div class="dialog-footer">
          <button class="btn btn-secondary" type="button" (click)="visible = false">
            <i class="pi pi-times"></i><span>Cancel</span>
          </button>
          <button class="btn btn-primary" type="button" [disabled]="saving()" (click)="submit()">
            @if (saving()) {
              <i class="pi pi-spin pi-spinner"></i><span>Adding...</span>
            } @else {
              <i class="pi pi-plus"></i><span>Add ticket</span>
            }
          </button>
        </div>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .hint { color: var(--text-muted); margin: 0 0 1rem; }
    .form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 0.75rem 1rem; align-items: center; padding: 0.5rem 0; }
    .form-grid label { color: var(--text-muted); font-size: 0.9rem; }
    .tip { color: var(--text-muted); display: block; margin-top: 0.5rem; }
    .dialog-footer { display: flex; justify-content: flex-end; gap: 0.5rem; }
  `]
})
export class AddTicketDialogComponent {
  @Input() visible = false;
  @Input() booking: Booking | null = null;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() added = new EventEmitter<string>();

  private readonly service = inject(BookingsService);
  private readonly messages = inject(MessageService);

  model: AddTicketRequest = this.empty();
  readonly saving = signal(false);

  private empty(): AddTicketRequest {
    return { flightId: '', passengerId: '', passengerName: '', amount: 12000 };
  }

  reset(): void { this.model = this.empty(); }

  submit(): void {
    if (!this.booking) return;
    if (!this.model.flightId || !this.model.passengerId || !this.model.passengerName) {
      this.messages.add({ severity: 'warn', summary: 'Missing fields', detail: 'Fill all fields.' });
      return;
    }
    if (!this.model.amount || this.model.amount <= 0) {
      this.messages.add({ severity: 'warn', summary: 'Invalid amount', detail: 'Amount must be positive.' });
      return;
    }

    this.saving.set(true);
    this.service.addTicket(this.booking.id, this.model).subscribe({
      next: () => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Ticket added', detail: 'Ticket added to booking.' });
        this.visible = false;
        this.visibleChange.emit(false);
        this.added.emit(this.booking!.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Add ticket failed', detail: err.message });
      }
    });
  }
}
'@
Save-Utf8 $p4 $c4

# ---------------------------------------------------------------------------
# 5. cancel-booking-dialog.component.ts
# ---------------------------------------------------------------------------
$p5 = Join-Path $root "frontend\src\app\features\bookings\cancel-booking-dialog.component.ts"
$c5 = @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { TextareaModule } from 'primeng/textarea';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { Booking } from '../../core/api/models/booking.model';
import { BookingsService } from './bookings.service';

@Component({
  selector: 'app-cancel-booking-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, TextareaModule],
  template: `
    <p-dialog
      header="Cancel booking"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '480px' }"
      (onHide)="reset()">

      <p class="hint">
        Cancel booking <strong>{{ booking?.bookRef }}</strong>? This cannot be undone.
      </p>

      <textarea pTextarea [(ngModel)]="reason" rows="3"
                placeholder="Cancellation reason"
                style="width: 100%;"></textarea>

      <ng-template #footer>
        <div class="dialog-footer">
          <button class="btn btn-secondary" type="button" (click)="visible = false">
            <i class="pi pi-arrow-left"></i><span>Keep booking</span>
          </button>
          <button class="btn btn-danger" type="button" [disabled]="saving()" (click)="submit()">
            @if (saving()) {
              <i class="pi pi-spin pi-spinner"></i><span>Cancelling...</span>
            } @else {
              <i class="pi pi-times"></i><span>Cancel booking</span>
            }
          </button>
        </div>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .hint { color: var(--text-muted); margin: 0 0 1rem; }
    .dialog-footer { display: flex; justify-content: flex-end; gap: 0.5rem; }
  `]
})
export class CancelBookingDialogComponent {
  @Input() visible = false;
  @Input() booking: Booking | null = null;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() cancelled = new EventEmitter<string>();

  private readonly service = inject(BookingsService);
  private readonly messages = inject(MessageService);

  reason = '';
  readonly saving = signal(false);

  reset(): void { this.reason = ''; }

  submit(): void {
    if (!this.booking) return;
    if (!this.reason.trim()) {
      this.messages.add({ severity: 'warn', summary: 'Reason required', detail: 'Enter a reason.' });
      return;
    }

    this.saving.set(true);
    this.service.cancel(this.booking.id, { reason: this.reason.trim() }).subscribe({
      next: () => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Booking cancelled', detail: 'Booking cancelled.' });
        this.visible = false;
        this.visibleChange.emit(false);
        this.cancelled.emit(this.booking!.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Cancel failed', detail: err.message });
      }
    });
  }
}
'@
Save-Utf8 $p5 $c5

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
Write-Host "Check Bookings:" -ForegroundColor Yellow
Write-Host "  - List page: 'Create booking' + 'Open' buttons with text"
Write-Host "  - Details: 'Add ticket', 'Confirm booking', 'Cancel booking' with text"
Write-Host "  - Create dialog: 'Cancel' / 'Create'"
Write-Host "  - Add ticket dialog: 'Cancel' / 'Add ticket'"
Write-Host "  - Cancel dialog: 'Keep booking' / 'Cancel booking'"
Write-Host ""