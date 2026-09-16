export interface Flight {
  id: string;
  flightNumber: string;
  departureAirport: string;
  departureAirportName?: string | null;
  arrivalAirport: string;
  arrivalAirportName?: string | null;
  scheduledDeparture: string;
  scheduledArrival: string;
  status: number;
  aircraftModel: string;
}

export interface CreateFlightRequest {
  flightNumber: string;
  departureAirport: string;
  arrivalAirport: string;
  departure: string;
  arrival: string;
  aircraftModel: string;
}

export interface DelayFlightRequest {
  newDeparture: string;
  newArrival: string;
}

export interface CancelFlightRequest {
  reason: string;
}