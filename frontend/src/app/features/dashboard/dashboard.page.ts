import { Component, inject, OnInit, signal } from '@angular/core';
import { DatePipe } from '@angular/common';
import { ApiService } from '../../core/api/api.service';
import { DashboardSummary } from '../../core/api/models/booking.model';

@Component({
  selector: 'app-dashboard-page',
  standalone: true,
  imports: [DatePipe],
  template: `
    <div class="page">
      <h1>Dashboard</h1>
      <p class="subtitle">Platform overview</p>

      @if (loading()) {
        <p>Loading...</p>
      } @else if (summary()) {
        <div class="cards">
          <div class="card">
            <div class="card-label">Flights</div>
            <div class="card-value">{{ summary()!.flights }}</div>
          </div>
          <div class="card">
            <div class="card-label">Airports</div>
            <div class="card-value">{{ summary()!.airports }}</div>
          </div>
          <div class="card">
            <div class="card-label">Bookings</div>
            <div class="card-value">{{ summary()!.bookings }}</div>
          </div>
          <div class="card">
            <div class="card-label">Active bookings</div>
            <div class="card-value">{{ summary()!.activeBookings }}</div>
          </div>
        </div>
      } @else {
        <p class="error">Failed to load summary.</p>
      }

      <p class="footnote">Last update: {{ now | date:'medium' }}</p>
    </div>
  `,
  styles: [`
    h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
    .subtitle { color: var(--text-muted); margin: 0 0 1.5rem; }
    .cards {
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(220px, 1fr));
      gap: 1rem;
    }
    .card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 8px;
      padding: 1.25rem;
    }
    .card-label { color: var(--text-muted); font-size: 0.85rem; text-transform: uppercase; }
    .card-value { font-size: 2rem; font-weight: 700; margin-top: 0.5rem; }
    .error { color: var(--danger); }
    .footnote { margin-top: 2rem; color: var(--text-muted); font-size: 0.85rem; }
  `]
})
export class DashboardPage implements OnInit {
  private readonly api = inject(ApiService);

  readonly summary = signal<DashboardSummary | null>(null);
  readonly loading = signal(true);
  readonly now = new Date();

  ngOnInit(): void {
    this.api.get<DashboardSummary>('/dashboard/summary').subscribe({
      next: (data) => {
        this.summary.set(data);
        this.loading.set(false);
      },
      error: () => {
        this.loading.set(false);
      }
    });
  }
}