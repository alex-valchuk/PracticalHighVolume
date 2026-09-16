using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingsList;

public sealed record GetBookingsListResult(IReadOnlyList<BookingDto> Items, int Total);

public sealed record GetBookingsListQuery(int Page = 1, int PageSize = 100) : IRequest<GetBookingsListResult>;