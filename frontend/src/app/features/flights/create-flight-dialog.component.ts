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