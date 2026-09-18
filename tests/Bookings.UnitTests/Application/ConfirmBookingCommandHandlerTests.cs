using Bookings.Application.Abstractions;
using Bookings.Application.Commands.ConfirmBooking;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class ConfirmBookingCommandHandlerTests
{
    private const int StatusScheduled = 0;
    private const int StatusCancelled = 4;

    private static Booking MakeBookingWithTicket(out Guid flightId)
    {
        var booking = Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

        flightId = Guid.NewGuid();
        booking.AddTicket(
            PassengerId.Create("9999999999"),
            PassengerName.Create("PETROV PETR"),
            flightId,
            12000m);

        return booking;
    }

    private static FlightSummary Summary(Guid id, int status = StatusScheduled)
        => new(id, "PG-0001", "SVO", "OVB",
               DateTimeOffset.UtcNow.AddDays(1),
               DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
               status);

    private static Mock<IIntegrationEventPublisher> Publisher()
    {
        var mock = new Mock<IIntegrationEventPublisher>();
        mock.Setup(p => p.PublishAsync(It.IsAny<It.IsAnyType>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        return mock;
    }

    private static ConfirmBookingCommandHandler Build(
        Mock<IBookingRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<IFlightCatalogClient> fc,
        Mock<ISeatReservationService> seats,
        Mock<IPaymentGateway> pay)
        => new(repo.Object, uow.Object, fc.Object, seats.Object, pay.Object,
               Publisher().Object,
               NullLogger<ConfirmBookingCommandHandler>.Instance);

    private static void SetupBooking(Mock<IBookingRepository> repo, Booking b)
    {
        repo.Setup(r => r.GetByIdAsync(b.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(b);
    }

    [Fact]
    public async Task Handle_HappyPath_ConfirmsBooking()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Guid.NewGuid());

        var paymentId = Guid.NewGuid();
        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(true, paymentId, null));

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Confirmed.Should().BeTrue();
        booking.Status.Should().Be(BookingStatus.Confirmed);

        seats.Verify(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()), Times.Once);
        pay.Verify(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()), Times.Once);
        seats.Verify(s => s.ReleaseAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
        pay.Verify(p => p.RefundAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_AlreadyConfirmed_IsIdempotent()
    {
        var booking = MakeBookingWithTicket(out _);
        booking.Confirm();

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var seats = new Mock<ISeatReservationService>();
        var pay = new Mock<IPaymentGateway>();

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<IFlightCatalogClient>(), seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Confirmed.Should().BeTrue();

        seats.Verify(s => s.ReserveAsync(It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
        pay.Verify(p => p.ChargeAsync(It.IsAny<Guid>(), It.IsAny<decimal>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_NoTickets_ReturnsFailure()
    {
        var booking = Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var handler = Build(repo, new Mock<IUnitOfWork>(),
            new Mock<IFlightCatalogClient>(),
            new Mock<ISeatReservationService>(),
            new Mock<IPaymentGateway>());

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("no_tickets");
    }

    [Fact]
    public async Task Handle_FlightCancelled_TriggersCompensation()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId, StatusCancelled));

        var seats = new Mock<ISeatReservationService>();
        var pay = new Mock<IPaymentGateway>();

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_failed");
        booking.Status.Should().Be(BookingStatus.Expired);

        pay.Verify(p => p.ChargeAsync(It.IsAny<Guid>(), It.IsAny<decimal>(), It.IsAny<string>(), It.IsAny<CancellationToken>()), Times.Never);
        seats.Verify(s => s.ReleaseAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_PaymentDeclined_ReleasesSeatsAndExpires()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var reservationId = Guid.NewGuid();
        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(reservationId);

        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(false, null, "Card declined (fake)."));

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_failed");
        booking.Status.Should().Be(BookingStatus.Expired);

        seats.Verify(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()), Times.Once);
        pay.Verify(p => p.RefundAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()), Times.Never);
    }

    [Fact]
    public async Task Handle_BookingNotFound_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Booking?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(),
            new Mock<IFlightCatalogClient>(),
            new Mock<ISeatReservationService>(),
            new Mock<IPaymentGateway>());

        var result = await handler.Handle(new ConfirmBookingCommand(Guid.NewGuid()), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    [Fact]
    public async Task Handle_SimulateFailureAfterCharge_RefundsAndReleases()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var reservationId = Guid.NewGuid();
        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(reservationId);
        seats.Setup(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var paymentId = Guid.NewGuid();
        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(true, paymentId, null, SimulateFailureAfterCharge: true));
        pay.Setup(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_failed");
        booking.Status.Should().Be(BookingStatus.Expired);

        pay.Verify(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()), Times.Once);
        seats.Verify(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_UnexpectedExceptionAfterCharge_RefundsAndReleases()
    {
        var booking = MakeBookingWithTicket(out var flightId);

        var repo = new Mock<IBookingRepository>();
        SetupBooking(repo, booking);

        var uow = new Mock<IUnitOfWork>();
        uow.SetupSequence(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()))
            .ThrowsAsync(new InvalidOperationException("Simulated DB failure"))
            .ReturnsAsync(1);

        var fc = new Mock<IFlightCatalogClient>();
        fc.Setup(f => f.GetFlightAsync(flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(Summary(flightId));

        var reservationId = Guid.NewGuid();
        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReserveAsync(booking.Id, It.IsAny<Guid>(), flightId, It.IsAny<CancellationToken>()))
            .ReturnsAsync(reservationId);
        seats.Setup(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var paymentId = Guid.NewGuid();
        var pay = new Mock<IPaymentGateway>();
        pay.Setup(p => p.ChargeAsync(booking.Id, 12000m, "RUB", It.IsAny<CancellationToken>()))
            .ReturnsAsync(new PaymentResult(true, paymentId, null));
        pay.Setup(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var handler = Build(repo, uow, fc, seats, pay);

        var result = await handler.Handle(new ConfirmBookingCommand(booking.Id), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("saga_error");
        booking.Status.Should().Be(BookingStatus.Expired);

        pay.Verify(p => p.RefundAsync(paymentId, It.IsAny<CancellationToken>()), Times.Once);
        seats.Verify(s => s.ReleaseAsync(reservationId, It.IsAny<CancellationToken>()), Times.Once);
    }
}