import { Component } from '@angular/core';

@Component({
  selector: 'app-flights-page',
  standalone: true,
  template: `
    <div class="page">
      <h1>Flights</h1>
      <p class="subtitle">Coming in phase 4.2</p>
    </div>
  `,
  styles: [`
    h1 { margin: 0 0 0.25rem; font-size: 1.5rem; }
    .subtitle { color: var(--text-muted); }
  `]
})
export class FlightsPage {}