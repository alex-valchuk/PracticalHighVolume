import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';
import {
  Booking,
  BookingListResponse,
  CreateBookingRequest,
  AddTicketRequest,
  ConfirmBookingResult,
  CancelBookingRequest
} from '../../core/api/models/booking.model';

@Injectable({ providedIn: 'root' })
export class BookingsService {
  private readonly api = inject(ApiService);

  list(page = 1, pageSize = 100): Observable<BookingListResponse> {
    return this.api.get<BookingListResponse>('/bookings', { page, pageSize });
  }

  getById(id: string): Observable<Booking> {
    return this.api.get<Booking>(`/bookings/${id}`);
  }

  create(req: CreateBookingRequest): Observable<{ id: string }> {
    return this.api.post<{ id: string }>('/bookings', req);
  }

  addTicket(bookingId: string, req: AddTicketRequest): Observable<{ ticketId: string }> {
    return this.api.post<{ ticketId: string }>(`/bookings/${bookingId}/tickets`, req);
  }

  confirm(bookingId: string): Observable<ConfirmBookingResult> {
    return this.api.post<ConfirmBookingResult>(`/bookings/${bookingId}/confirm`, {});
  }

  cancel(bookingId: string, req: CancelBookingRequest): Observable<void> {
    return this.api.post<void>(`/bookings/${bookingId}/cancel`, req);
  }
}