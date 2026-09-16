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
Write-Host "=== Fix: header theme button without binding on pButton ==="
Write-Host ""

Write-File "frontend/src/app/core/layout/header.component.ts" @'
import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { ButtonModule } from 'primeng/button';
import { TooltipModule } from 'primeng/tooltip';
import { HealthService } from '../services/health.service';
import { ThemeService } from '../services/theme.service';

@Component({
  selector: 'app-header',
  standalone: true,
  imports: [ButtonModule, TooltipModule],
  template: `
    <header class="header">
      <div class="health" [class.online]="health.isOnline()" [class.offline]="!health.isOnline()"
           [pTooltip]="health.isOnline() ? 'API is reachable' : 'API is not reachable. Start the backend.'"
           tooltipPosition="bottom">
        <span class="dot"></span>
        <span>{{ health.isOnline() ? 'API online' : 'API offline' }}</span>
      </div>

      <button pButton type="button" severity="secondary" outlined
              (click)="theme.toggle()"
              [pTooltip]="theme.isDark() ? 'Switch to light theme' : 'Switch to dark theme'"
              tooltipPosition="bottom">
        <i class="pi" [class.pi-sun]="theme.isDark()" [class.pi-moon]="!theme.isDark()"></i>
        <span class="theme-label">{{ theme.isDark() ? 'Light theme' : 'Dark theme' }}</span>
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
      cursor: default;
    }
    .dot {
      width: 8px;
      height: 8px;
      border-radius: 50%;
      background: var(--text-muted);
    }
    .health.online .dot { background: var(--success); }
    .health.online span:last-child { color: var(--success); }
    .health.offline .dot { background: var(--danger); }
    .health.offline span:last-child { color: var(--danger); }
    .theme-label { margin-left: 0.5rem; }
  `]
})
export class HeaderComponent implements OnInit, OnDestroy {
  readonly health = inject(HealthService);
  readonly theme = inject(ThemeService);

  ngOnInit(): void {
    this.health.start();
  }

  ngOnDestroy(): void {
    this.health.stop();
  }
}
'@

Write-Host ""
Write-Host "=== Build frontend ==="

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
Write-Host '  git commit -m "fix(frontend): theme toggle button without binding on pButton"'
Write-Host "  git push"
Write-Host ""