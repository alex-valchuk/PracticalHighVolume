using Bookings.Application.Abstractions;
using Bookings.Application.DTOs;
using Dapper;
using Npgsql;

namespace Bookings.Infrastructure.Persistence.Repositories;

public sealed class BookingReadRepository : IBookingReadRepository
{
    private readonly NpgsqlDataSource _dataSource;

    public BookingReadRepository(NpgsqlDataSource dataSource) => _dataSource = dataSource;

    public async Task<BookingDto?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        const string sqlBooking = @"
            SELECT id             AS Id,
                   book_ref       AS BookRef,
                   book_date      AS BookDate,
                   total_amount   AS TotalAmount,
                   currency       AS Currency,
                   status         AS Status,
                   passenger_id   AS PassengerId,
                   passenger_name AS PassengerName
            FROM booking.bookings
            WHERE id = @Id";

        const string sqlTickets = @"
            SELECT id        AS Id,
                   ticket_no AS TicketNo,
                   flight_id AS FlightId,
                   amount    AS Amount
            FROM booking.tickets
            WHERE booking_id = @Id
            ORDER BY ticket_no";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);

        var booking = await conn.QueryFirstOrDefaultAsync<BookingDto>(
            new CommandDefinition(sqlBooking, new { Id = id }, cancellationToken: ct));

        if (booking is null) return null;

        var tickets = await conn.QueryAsync<TicketDto>(
            new CommandDefinition(sqlTickets, new { Id = id }, cancellationToken: ct));

        booking.Tickets.AddRange(tickets);
        return booking;
    }

    public async Task<(IReadOnlyList<BookingDto> Items, int Total)> GetAllAsync(
        int page, int pageSize, CancellationToken ct = default)
    {
        if (page < 1) page = 1;
        if (pageSize < 1) pageSize = 100;
        if (pageSize > 500) pageSize = 500;

        const string sqlCount = "SELECT COUNT(*) FROM booking.bookings";
        const string sqlPage = @"
            SELECT id             AS Id,
                   book_ref       AS BookRef,
                   book_date      AS BookDate,
                   total_amount   AS TotalAmount,
                   currency       AS Currency,
                   status         AS Status,
                   passenger_id   AS PassengerId,
                   passenger_name AS PassengerName
            FROM booking.bookings
            ORDER BY book_date DESC
            OFFSET @Offset LIMIT @Limit";

        const string sqlTicketsForIds = @"
            SELECT booking_id AS BookingId,
                   id         AS Id,
                   ticket_no  AS TicketNo,
                   flight_id  AS FlightId,
                   amount     AS Amount
            FROM booking.tickets
            WHERE booking_id = ANY(@Ids)
            ORDER BY ticket_no";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);

        var total = await conn.ExecuteScalarAsync<int>(
            new CommandDefinition(sqlCount, cancellationToken: ct));

        var bookings = (await conn.QueryAsync<BookingDto>(
            new CommandDefinition(sqlPage,
                new { Offset = (page - 1) * pageSize, Limit = pageSize },
                cancellationToken: ct))).ToList();

        if (bookings.Count > 0)
        {
            var ids = bookings.Select(b => b.Id).ToArray();

            var tickets = await conn.QueryAsync<TicketWithBookingRow>(
                new CommandDefinition(sqlTicketsForIds, new { Ids = ids }, cancellationToken: ct));

            var byBooking = tickets
                .GroupBy(t => t.BookingId)
                .ToDictionary(g => g.Key, g => g.ToList());

            foreach (var b in bookings)
            {
                if (byBooking.TryGetValue(b.Id, out var list))
                {
                    foreach (var t in list)
                    {
                        b.Tickets.Add(new TicketDto
                        {
                            Id = t.Id,
                            TicketNo = t.TicketNo,
                            FlightId = t.FlightId,
                            Amount = t.Amount
                        });
                    }
                }
            }
        }

        return (bookings, total);
    }

    private sealed class TicketWithBookingRow
    {
        public Guid BookingId { get; init; }
        public Guid Id { get; init; }
        public string TicketNo { get; init; } = default!;
        public Guid FlightId { get; init; }
        public decimal Amount { get; init; }
    }
}