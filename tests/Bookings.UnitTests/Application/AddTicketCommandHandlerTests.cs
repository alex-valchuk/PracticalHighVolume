using Bookings.Application.Abstractions;
using Bookings.Application.Commands.AddTicket;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
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

    private static Mock<IDistributedLockService> LockAcquired()
    {
        var mock = new Mock<IDistributedLockService>();
        var handle = new Mock<IAsyncDisposable>();
        handle.Setup(h => h.DisposeAsync()).Returns(ValueTask.CompletedTask);

        mock.Setup(s => s.TryAcquireAsync(
                It.IsAny<string>(),
                It.IsAny<TimeSpan>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync(handle.Object);

        return mock;
    }

    private static Mock<IDistributedLockService> LockNotAcquired()
    {
        var mock = new Mock<IDistributedLockService>();
        mock.Setup(s => s.TryAcquireAsync(
                It.IsAny<string>(),
                It.IsAny<TimeSpan>(),
                It.IsAny<CancellationToken>()))
            .ReturnsAsync((IAsyncDisposable?)null);
        return mock;
    }

    private static AddTicketCommandHandler Build(
        Mock<IBookingRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<IFlightCatalogClient> fc,
        Mock<IDistributedLockService>? locks = null)
        => new(repo.Object, uow.Object, fc.Object,
               (locks ?? LockAcquired()).Object,
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
    public async Task Handle_WhenLockNotAcquired_ReturnsConcurrentModification()
    {
        var booking = MakeBooking();
        var flightId = Guid.NewGuid();

        var repo = new Mock<IBookingRepository>();
        var uow = new Mock<IUnitOfWork>();
        var fc = new Mock<IFlightCatalogClient>();

        var handler = Build(repo, uow, fc, LockNotAcquired());

        var result = await handler.Handle(
            new AddTicketCommand(booking.Id, flightId, "9999999999", "X", 100m),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("concurrent_modification");

        // Repository and gateway must not be touched under a failed lock.
        repo.Verify(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
        uow.Verify(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Never);
        fc.Verify(f => f.GetFlightAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
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