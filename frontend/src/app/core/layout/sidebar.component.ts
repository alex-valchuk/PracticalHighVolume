import { Component } from '@angular/core';
import { RouterLink, RouterLinkActive } from '@angular/router';

@Component({
  selector: 'app-sidebar',
  standalone: true,
  imports: [RouterLink, RouterLinkActive],
  template: `
    <aside class="sidebar">
      <div class="brand">
        <i class="pi pi-send"></i>
        <span>Flights Platform</span>
      </div>
      <nav>
        <a routerLink="/dashboard" routerLinkActive="active">
          <i class="pi pi-home"></i><span>Dashboard</span>
        </a>
        <a routerLink="/airports" routerLinkActive="active">
          <i class="pi pi-map-marker"></i><span>Airports</span>
        </a>
        <a routerLink="/flights" routerLinkActive="active">
          <i class="pi pi-send"></i><span>Flights</span>
        </a>
        <a routerLink="/bookings" routerLinkActive="active">
          <i class="pi pi-ticket"></i><span>Bookings</span>
        </a>
      </nav>
    </aside>
  `,
  styles: [`
    .sidebar {
      width: 240px;
      background: var(--surface);
      border-right: 1px solid var(--border);
      display: flex;
      flex-direction: column;
      padding: 1rem 0;
    }
    .brand {
      display: flex;
      align-items: center;
      gap: 0.6rem;
      padding: 0 1.25rem 1rem;
      font-weight: 600;
      font-size: 1.05rem;
      border-bottom: 1px solid var(--border);
      margin-bottom: 1rem;
    }
    .brand .pi { color: var(--primary); font-size: 1.25rem; }
    nav { display: flex; flex-direction: column; gap: 0.25rem; padding: 0 0.5rem; }
    nav a {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      padding: 0.65rem 0.85rem;
      border-radius: 6px;
      color: var(--text);
      font-size: 0.95rem;
      transition: background 0.15s;
    }
    nav a:hover { background: var(--bg); }
    nav a.active {
      background: var(--primary);
      color: white;
    }
    nav a .pi { font-size: 1rem; width: 1.1rem; text-align: center; }
  `]
})
export class SidebarComponent {}