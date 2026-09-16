import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';
import {
  Flight,
  CreateFlightRequest,
  DelayFlightRequest,
  CancelFlightRequest
} from '../../core/api/models/flight.model';

@Injectable({ providedIn: 'root' })
export class FlightsService {
  private readonly api = inject(ApiService);

  search(from: string, to: string, date: string): Observable<Flight[]> {
    return this.api.get<Flight[]>('/flight-catalog/flights', { from, to, date });
  }

  getById(id: string): Observable<Flight> {
    return this.api.get<Flight>(`/flight-catalog/flights/${id}`);
  }

  create(req: CreateFlightRequest): Observable<{ id: string }> {
    return this.api.post<{ id: string }>('/flight-catalog/flights', req);
  }

  delay(id: string, req: DelayFlightRequest): Observable<void> {
    return this.api.post<void>(`/flight-catalog/flights/${id}/delay`, req);
  }

  cancel(id: string, req: CancelFlightRequest): Observable<void> {
    return this.api.post<void>(`/flight-catalog/flights/${id}/cancel`, req);
  }
}