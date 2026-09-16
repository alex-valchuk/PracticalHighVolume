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