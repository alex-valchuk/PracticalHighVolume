using Bookings.Application.Abstractions;
using Bookings.Application.Commands.AddTicket;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class AddTicketCommandHandlerTests
{
    private const int StatusScheduled = 0;
    private const int StatusCancelled = 4;

    private static Booking MakeBooking() =>
        Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static AddTicketCommandHandler Build(
        Mock<IBookingRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<IFlightCatalogClient> fc)
        => new(repo.Object, uow.Object, fc.Object,
               NullLogger<AddTicketCommandHandler>.Instance);

    private static FlightSummary Summary(Guid id, int status = StatusScheduled)
        => new(id, "PG-0001", "SVO", "OVB",
               DateTimeOffset.UtcNow.AddDays(1),
               DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
               status);

    [Fact]
    public async Task Handle_HappyPath_ReturnsTicketId()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var handler = Build(repo, uow, fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "PETROV PETR", 12000m),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeEmpty();
        booking.TotalAmount.Amount.Should().Be(12000m);
        uow.Verify(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_BookingNotFound_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Booking?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<IFlightCatalogClient>());

        var result = await handler.Handle(
            new AddTicketCommand(Guid.NewGuid(), Guid.NewGuid(), "9999999999", "X", 100m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    [Fact]
    public async Task Handle_FlightNotFound_ReturnsFailure()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync((FlightSummary?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(), fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "X", 100m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("flight_not_found");
    }

    [Fact]
    public async Task Handle_FlightCancelled_ReturnsFailure()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId, StatusCancelled));

        var handler = Build(repo, new Mock<IUnitOfWork>(), fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "X", 100m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("flight_unavailable");
    }

    [Fact]
    public async Task Handle_DomainViolation_ReturnsDomainError()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        // First ticket added directly to make duplicate
        booking.AddTicket(
            PassengerId.Create("9999999999"),
            PassengerName.Create("PETROV PETR"),
            flightId,
            10000m);

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var handler = Build(repo, new Mock<IUnitOfWork>(), fc);

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "PETROV PETR", 10000m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("domain_error");
    }
}