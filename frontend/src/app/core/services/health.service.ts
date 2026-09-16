import { Injectable, inject, signal } from '@angular/core';
import { ApiService } from '../api/api.service';
import { HealthResponse } from '../api/models/booking.model';

@Injectable({ providedIn: 'root' })
export class HealthService {
  private readonly api = inject(ApiService);
  private readonly online = signal<boolean>(true);
  private timerId: number | null = null;

  readonly isOnline = this.online.asReadonly();

  start(): void {
    if (this.timerId !== null) return;
    this.check();
    this.timerId = window.setInterval(() => this.check(), 15000);
  }

  stop(): void {
    if (this.timerId !== null) {
      clearInterval(this.timerId);
      this.timerId = null;
    }
  }

  private check(): void {
    this.api.get<HealthResponse>('/health').subscribe({
      next: () => this.online.set(true),
      error: () => this.online.set(false)
    });
  }
}