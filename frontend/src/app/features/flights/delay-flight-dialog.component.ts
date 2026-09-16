import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { DatePickerModule } from 'primeng/datepicker';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { DelayFlightRequest, Flight } from '../../core/api/models/flight.model';
import { FlightsService } from './flights.service';

@Component({
  selector: 'app-delay-flight-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, DatePickerModule],
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
        <div class="dialog-footer">
          <button class="btn btn-secondary" type="button" (click)="visible = false">
            <i class="pi pi-times"></i><span>Cancel</span>
          </button>
          <button class="btn btn-warn" type="button" [disabled]="saving()" (click)="submit()">
            @if (saving()) {
              <i class="pi pi-spin pi-spinner"></i><span>Saving...</span>
            } @else {
              <i class="pi pi-clock"></i><span>Delay</span>
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
    .dialog-footer { display: flex; justify-content: flex-end; gap: 0.5rem; }
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