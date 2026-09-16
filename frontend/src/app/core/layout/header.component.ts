import { Component, inject, OnInit, OnDestroy } from '@angular/core';
import { HealthService } from '../services/health.service';
import { ThemeService } from '../services/theme.service';

@Component({
  selector: 'app-header',
  standalone: true,
  template: `
    <header class="header">
      <div class="health" [class.online]="health.isOnline()" [class.offline]="!health.isOnline()">
        <span class="dot"></span>
        <span>{{ health.isOnline() ? 'API online' : 'API offline' }}</span>
      </div>
      <button class="theme-btn" (click)="theme.toggle()" title="Toggle theme">
        <i class="pi" [class.pi-moon]="!theme.isDark()" [class.pi-sun]="theme.isDark()"></i>
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
    .theme-btn {
      background: transparent;
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.4rem 0.6rem;
      color: var(--text);
    }
    .theme-btn:hover { background: var(--bg); }
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