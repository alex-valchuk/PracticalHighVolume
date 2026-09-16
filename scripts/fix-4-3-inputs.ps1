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
Write-Host "=== Fix 4.3: lowercase p-inputnumber / p-toggleswitch ==="
Write-Host ""

# --- 1. add-ticket-dialog.component.ts ---
Write-Host "=== 1. add-ticket-dialog.component.ts ==="

Write-File "frontend/src/app/features/bookings/add-ticket-dialog.component.ts" @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { InputNumberModule } from 'primeng/inputnumber';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { AddTicketRequest, Booking } from '../../core/api/models/booking.model';
import { BookingsService } from './bookings.service';

@Component({
  selector: 'app-add-ticket-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, ButtonModule, InputTextModule, InputNumberModule],
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
        <button pButton type="button" label="Cancel" severity="secondary"
                (click)="visible = false"></button>
        <button pButton type="button" label="Add ticket"
                [loading]="saving()"
                (click)="submit()"></button>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .hint { color: var(--text-muted); margin: 0 0 1rem; }
    .form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 0.75rem 1rem; align-items: center; padding: 0.5rem 0; }
    .form-grid label { color: var(--text-muted); font-size: 0.9rem; }
    .tip { color: var(--text-muted); display: block; margin-top: 0.5rem; }
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

# --- 2. Patch bookings.page.ts: p-toggleSwitch -> p-toggleswitch ---
Write-Host ""
Write-Host "=== 2. bookings.page.ts ==="

$bookingsPath = Join-Path $root "frontend\src\app\features\bookings\bookings.page.ts"
$content = [System.IO.File]::ReadAllText($bookingsPath)
$content = $content -replace '<p-toggleSwitch ', '<p-toggleswitch '
$content = $content -replace '<p-toggleSwitch>', '<p-toggleswitch>'
$content = $content -replace '</p-toggleSwitch>', '</p-toggleswitch>'
[System.IO.File]::WriteAllText($bookingsPath, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "  + updated bookings.page.ts (p-toggleswitch)"

# --- 3. Verify ---
Write-Host ""
Write-Host "=== 3. Verify ==="

$addTicketPath = Join-Path $root "frontend\src\app\features\bookings\add-ticket-dialog.component.ts"
$c1 = [System.IO.File]::ReadAllText($addTicketPath)
if ($c1 -match '<p-inputnumber') {
    Write-Host "  OK add-ticket uses <p-inputnumber>" -ForegroundColor Green
} else {
    Write-Host "  FAIL: <p-inputnumber> not found" -ForegroundColor Red
}

$c2 = [System.IO.File]::ReadAllText($bookingsPath)
if ($c2 -match '<p-toggleswitch') {
    Write-Host "  OK bookings.page uses <p-toggleswitch>" -ForegroundColor Green
} else {
    Write-Host "  FAIL: <p-toggleswitch> not found" -ForegroundColor Red
}

# --- 4. Build ---
Write-Host ""
Write-Host "=== 4. Build frontend ==="

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
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "fix(frontend): PrimeNG 22 lowercase selectors for inputnumber and toggleswitch"'
Write-Host "  git push"
Write-Host ""