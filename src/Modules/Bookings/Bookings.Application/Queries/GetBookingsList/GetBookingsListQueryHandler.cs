using Bookings.Application.Abstractions;
using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingsList;

public sealed class GetBookingsListQueryHandler
    : IRequestHandler<GetBookingsListQuery, GetBookingsListResult>
{
    private readonly IBookingReadRepository _readRepository;

    public GetBookingsListQueryHandler(IBookingReadRepository readRepository)
        => _readRepository = readRepository;

    public async Task<GetBookingsListResult> Handle(GetBookingsListQuery request, CancellationToken ct)
    {
        var (items, total) = await _readRepository.GetAllAsync(request.Page, request.PageSize, ct);
        return new GetBookingsListResult(items, total);
    }
}