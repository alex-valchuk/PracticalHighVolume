import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  {
    path: 'dashboard',
    loadComponent: () =>
      import('./features/dashboard/dashboard.page').then(m => m.DashboardPage)
  },
  {
    path: 'airports',
    loadComponent: () =>
      import('./features/airports/airports.page').then(m => m.AirportsPage)
  },
  {
    path: 'flights',
    loadComponent: () =>
      import('./features/flights/flights.page').then(m => m.FlightsPage)
  },
  {
    path: 'bookings',
    loadComponent: () =>
      import('./features/bookings/bookings.page').then(m => m.BookingsPage)
  },
  {
    path: 'bookings/:id',
    loadComponent: () =>
      import('./features/bookings/booking-details.page').then(m => m.BookingDetailsPage)
  },
  { path: '**', redirectTo: 'dashboard' }
];