$root = (Get-Location).Path
$full = Join-Path $root "frontend\src\app\core\layout\header.component.ts"

$content = @'
import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { HealthService } from '../services/health.service';
import { ThemeService } from '../services/theme.service';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [],
  template: `
    <header class="header">
      <div class="health" [class.online]="health.isOnline()" [class.offline]="!health.isOnline()">
        <span class="dot"></span>
        <span>{{ health.isOnline() ? 'API online' : 'API offline' }}</span>
      </div>

      <button class="btn btn-secondary" type="button" (click)="theme.toggle()">
        <i class="pi" [class.pi-sun]="theme.isDark()" [class.pi-moon]="!theme.isDark()"></i>
        <span>{{ theme.isDark() ? 'Light theme' : 'Dark theme' }}</span>
      </button>
    </header>
  `,
  styles: [`
    .header {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 0.75rem 2rem;
      background: var(--surface);
      border-bottom: 1px solid var(--border);
    }
    .health {
      display: flex;
      align-items: center;
      gap: 0.5rem;
      font-size: 0.9rem;
      color: var(--text-muted);
    }
    .dot { width: 8px; height: 8px; border-radius: 50%; background: var(--text-muted); }
    .health.online .dot { background: var(--success); }
    .health.online span:last-child { color: var(--success); }
    .health.offline .dot { background: var(--danger); }
    .health.offline span:last-child { color: var(--danger); }
  `]
})
export class HeaderComponent implements OnInit, OnDestroy {
  readonly health = inject(HealthService);
  readonly theme = inject(ThemeService);

  ngOnInit(): void { this.health.start(); }
  ngOnDestroy(): void { this.health.stop(); }
}
'@

[System.IO.File]::WriteAllText($full, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host ("  + " + $full)

Write-Host ""
Write-Host "Now add .btn styles to styles.scss"
Write-Host ""
Write-Host "Open frontend/src/styles.scss and add at the end:" -ForegroundColor Yellow
Write-Host ""
Write-Host '  .btn {' -ForegroundColor Cyan
Write-Host '    display: inline-flex;' -ForegroundColor Cyan
Write-Host '    align-items: center;' -ForegroundColor Cyan
Write-Host '    gap: 0.5rem;' -ForegroundColor Cyan
Write-Host '    padding: 0.55rem 1rem;' -ForegroundColor Cyan
Write-Host '    border-radius: 6px;' -ForegroundColor Cyan
Write-Host '    font-size: 0.95rem;' -ForegroundColor Cyan
Write-Host '    font-weight: 500;' -ForegroundColor Cyan
Write-Host '    border: 1px solid transparent;' -ForegroundColor Cyan
Write-Host '    cursor: pointer;' -ForegroundColor Cyan
Write-Host '    font-family: inherit;' -ForegroundColor Cyan
Write-Host '  }' -ForegroundColor Cyan
Write-Host '  .btn-primary { background: #3b82f6; color: #fff; }' -ForegroundColor Cyan
Write-Host '  .btn-success { background: #16a34a; color: #fff; }' -ForegroundColor Cyan
Write-Host '  .btn-danger { background: #dc2626; color: #fff; }' -ForegroundColor Cyan
Write-Host '  .btn-warn { background: #f59e0b; color: #fff; }' -ForegroundColor Cyan
Write-Host '  .btn-secondary { background: transparent; color: var(--text); border-color: var(--border); }' -ForegroundColor Cyan
Write-Host '  .btn-sm { padding: 0.35rem 0.75rem; font-size: 0.85rem; }' -ForegroundColor Cyan
Write-Host '  .btn:disabled { opacity: 0.5; cursor: not-allowed; }' -ForegroundColor Cyan
Write-Host ""
Write-Host "Then run:" -ForegroundColor Yellow
Write-Host "  cd frontend; npm start"
Write-Host ""