$root = (Get-Location).Path

function Save-Utf8 {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path.Replace($root, ".")) -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 1. create-flight-dialog.component.ts
# ---------------------------------------------------------------------------
$p1 = Join-Path $root "frontend\src\app\features\flights\create-flight-dialog.component.ts"
$c1 = @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { InputTextModule } from 'primeng/inputtext';
import { DatePickerModule } from 'primeng/datepicker';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { CreateFlightRequest } from '../../core/api/models/flight.model';
import { FlightsService } from './flights.service';

@Component({
  selector: 'app-create-flight-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, InputTextModule, DatePickerModule],
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
Save-Utf8 $p1 $c1

# ---------------------------------------------------------------------------
# 2. delay-flight-dialog.component.ts
# ---------------------------------------------------------------------------
$p2 = Join-Path $root "frontend\src\app\features\flights\delay-flight-dialog.component.ts"
$c2 = @'
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
'@
Save-Utf8 $p2 $c2

# ---------------------------------------------------------------------------
# 3. cancel-flight-dialog.component.ts
# ---------------------------------------------------------------------------
$p3 = Join-Path $root "frontend\src\app\features\flights\cancel-flight-dialog.component.ts"
$c3 = @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { TextareaModule } from 'primeng/textarea';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { Flight } from '../../core/api/models/flight.model';
import { FlightsService } from './flights.service';

@Component({
  selector: 'app-cancel-flight-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, TextareaModule],
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
        <div class="dialog-footer">
          <button class="btn btn-secondary" type="button" (click)="visible = false">
            <i class="pi pi-arrow-left"></i><span>Keep flight</span>
          </button>
          <button class="btn btn-danger" type="button" [disabled]="saving()" (click)="submit()">
            @if (saving()) {
              <i class="pi pi-spin pi-spinner"></i><span>Cancelling...</span>
            } @else {
              <i class="pi pi-times"></i><span>Cancel flight</span>
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
Save-Utf8 $p3 $c3

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
Write-Host "Check all three flight dialogs:" -ForegroundColor Yellow
Write-Host "  - Create flight dialog: Cancel / Create buttons"
Write-Host "  - Delay dialog: Cancel / Delay buttons"
Write-Host "  - Cancel dialog: Keep flight / Cancel flight buttons"
Write-Host ""