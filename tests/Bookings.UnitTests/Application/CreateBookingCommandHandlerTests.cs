using Bookings.Application.Abstractions;
using Bookings.Application.Commands.CreateBooking;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace Bookings.UnitTests.Application;

public class CreateBookingCommandHandlerTests
{
    [Fact]
    public async Task Handle_WithValidRequest_ReturnsSuccess()
    {
        var repo = new Mock<IBookingRepository>();
        repo.Setup(r => r.AddAsync(It.IsAny<Bookings.Domain.Aggregates.Booking>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new CreateBookingCommandHandler(
            repo.Object, uow.Object, NullLogger<CreateBookingCommandHandler>.Instance);

        var result = await handler.Handle(
            new CreateBookingCommand("1234567890", "IVANOV IVAN", "RUB"),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeEmpty();
        repo.Verify(r => r.AddAsync(It.IsAny<Bookings.Domain.Aggregates.Booking>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_WithInvalidPassengerId_ReturnsFailure()
    {
        var repo = new Mock<IBookingRepository>();
        var uow = new Mock<IUnitOfWork>();
        var handler = new CreateBookingCommandHandler(
            repo.Object, uow.Object, NullLogger<CreateBookingCommandHandler>.Instance);

        var result = await handler.Handle(
            new CreateBookingCommand("bad", "IVANOV IVAN", "RUB"),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
    }
}