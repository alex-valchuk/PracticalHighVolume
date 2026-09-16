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