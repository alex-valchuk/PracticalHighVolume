export interface Ticket {
  id: string;
  ticketNo: string;
  flightId: string;
  amount: number;
}

export interface Booking {
  id: string;
  bookRef: string;
  bookDate: string;
  totalAmount: number;
  currency: string;
  status: number;
  passengerId: string;
  passengerName: string;
  tickets: Ticket[];
}

export interface BookingListResponse {
  items: Booking[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CreateBookingRequest {
  passengerId: string;
  passengerName: string;
  currency: string;
}

export interface AddTicketRequest {
  flightId: string;
  passengerId: string;
  passengerName: string;
  amount: number;
}

export interface ConfirmBookingResult {
  bookingId: string;
  confirmed: boolean;
  failureReason?: string | null;
}

export interface CancelBookingRequest {
  reason: string;
}

export const BookingStatus = {
  Pending: 0,
  Confirmed: 1,
  Cancelled: 2,
  Expired: 3
} as const;

export const FlightStatus = {
  Scheduled: 0,
  Delayed: 1,
  Departed: 2,
  Arrived: 3,
  Cancelled: 4
} as const;

export interface DashboardSummary {
  flights: number;
  airports: number;
  bookings: number;
  activeBookings: number;
}

export interface HealthResponse {
  status: string;
  time: string;
}