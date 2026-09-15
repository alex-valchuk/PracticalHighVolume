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
}