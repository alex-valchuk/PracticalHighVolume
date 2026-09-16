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