import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';

export interface SimulateFailureState {
  enabled: boolean;
}

@Injectable({ providedIn: 'root' })
export class AdminService {
  private readonly api = inject(ApiService);

  getSimulateFailure(): Observable<SimulateFailureState> {
    return this.api.get<SimulateFailureState>('/admin/payment/simulate-failure');
  }

  setSimulateFailure(enabled: boolean): Observable<SimulateFailureState> {
    return this.api.post<SimulateFailureState>('/admin/payment/simulate-failure', { enabled });
  }
}