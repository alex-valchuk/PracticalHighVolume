using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingById;

public sealed record GetBookingByIdQuery(Guid BookingId) : IRequest<BookingDto?>;