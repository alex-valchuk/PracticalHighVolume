using Bookings.Application.Abstractions;
using Bookings.Application.Commands.CancelBooking;
using Bookings.Domain;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class CancelBookingCommandHandlerTests
{
    private static Mock<IIntegrationEventPublisher> Publisher()
    {
        var mock = new Mock<IIntegrationEventPublisher>();
        mock.Setup(p => p.PublishAsync(It.IsAny<It.IsAnyType>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        return mock;
    }

    private static Booking MakeBooking()
        => Booking.CreateDraft(
            PassengerId.Create("1234567890"),
            PassengerName.Create("IVANOV IVAN"),
            "RUB");

    private static CancelBookingCommandHandler Build(
        Mock<IBookingRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<ISeatReservationService> seats)
        => new(repo.Object, uow.Object, seats.Object, Publisher().Object,
               NullLogger<CancelBookingCommandHandler>.Instance);

    [Fact]
    public async Task Handle_PendingBooking_CancelsAndReleasesSeats()
    {
        var booking = MakeBooking();

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var seats = new Mock<ISeatReservationService>();
        seats.Setup(s => s.ReleaseAllForBookingAsync(booking.Id, It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var handler = Build(repo, uow, seats);

        var result = await handler.Handle(
            new CancelBookingCommand(booking.Id, "changed plans"), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        booking.Status.Should().Be(BookingStatus.Cancelled);
        seats.Verify(s => s.ReleaseAllForBookingAsync(booking.Id, It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_BookingNotFound_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Booking?)null);

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<ISeatReservationService>());

        var result = await handler.Handle(
            new CancelBookingCommand(Guid.NewGuid(), "test"), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    [Fact]
    public async Task Handle_AlreadyCancelled_ReturnsDomainError()
    {
        var booking = MakeBooking();
        booking.Cancel("first");

        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.GetByIdAsync(booking.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(booking);

        var handler = Build(repo, new Mock<IUnitOfWork>(), new Mock<ISeatReservationService>());

        var result = await handler.Handle(
            new CancelBookingCommand(booking.Id, "again"), CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("domain_error");
    }
}