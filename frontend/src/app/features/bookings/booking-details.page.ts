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