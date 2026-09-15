using Bookings.Application.Abstractions;
using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingById;

public sealed class GetBookingByIdQueryHandler : IRequestHandler<GetBookingByIdQuery, BookingDto?>
{
    private readonly IBookingReadRepository _readRepository;

    public GetBookingByIdQueryHandler(IBookingReadRepository readRepository)
        => _readRepository = readRepository;

    public Task<BookingDto?> Handle(GetBookingByIdQuery request, CancellationToken ct)
        => _readRepository.GetByIdAsync(request.BookingId, ct);
}