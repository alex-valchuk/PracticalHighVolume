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