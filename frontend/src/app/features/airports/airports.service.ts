import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';
import { Airport, AirportListResponse } from '../../core/api/models/airport.model';

export interface SyncAirportsResult {
  read: number;
  created: number;
  updated: number;
  skipped: number;
}

@Injectable({ providedIn: 'root' })
export class AirportsService {
  private readonly api = inject(ApiService);

  list(page = 1, pageSize = 500): Observable<AirportListResponse> {
    return this.api.get<AirportListResponse>('/flight-catalog/airports', { page, pageSize });
  }

  getByCode(code: string): Observable<Airport> {
    return this.api.get<Airport>(`/flight-catalog/airports/${code}`);
  }

  sync(): Observable<SyncAirportsResult> {
    return this.api.post<SyncAirportsResult>('/flight-catalog/airports/sync', {});
  }
}