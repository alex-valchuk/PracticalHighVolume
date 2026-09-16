export interface Airport {
  id: string;
  code: string;
  name: string;
  city: string;
  timezone: string;
  latitude: number;
  longitude: number;
}

export interface AirportListResponse {
  items: Airport[];
  total: number;
  page: number;
  pageSize: number;
}