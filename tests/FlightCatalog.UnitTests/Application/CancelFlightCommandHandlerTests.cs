using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.Commands.CancelFlight;
using FlightCatalog.Domain;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FlightCatalog.UnitTests.Application;

public class CancelFlightCommandHandlerTests
{
    private static Mock<IIntegrationEventPublisher> Publisher()
    {
        var mock = new Mock<IIntegrationEventPublisher>();
        mock.Setup(p => p.PublishAsync(It.IsAny<It.IsAnyType>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);
        return mock;
    }

    [Fact]
    public async Task Handle_WhenFlightNotFound_ReturnsFailure()
    {
        var repo = new Mock<IFlightRepository>();
        repo.Setup(r => r.GetByIdAsync(It.IsAny<Guid>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Flight?)null);

        var uow = new Mock<IUnitOfWork>();
        var handler = new CancelFlightCommandHandler(
            repo.Object, uow.Object, Publisher().Object,
            NullLogger<CancelFlightCommandHandler>.Instance);

        var result = await handler.Handle(
            new CancelFlightCommand(Guid.NewGuid(), "test"),
            CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("not_found");
    }

    [Fact]
    public async Task Handle_WhenFlightExists_Succeeds()
    {
        var now = DateTimeOffset.UtcNow;
        var flight = Flight.ScheduleFlight(
            FlightNumber.Create("PG-0001"),
            Route.Create(AirportCode.Create("SVO"), AirportCode.Create("OVB")),
            Schedule.Create(now.AddDays(1), now.AddDays(1).AddHours(4)),
            "Airbus A320");

        var repo = new Mock<IFlightRepository>();
        repo.Setup(r => r.GetByIdAsync(flight.Id, It.IsAny<CancellationToken>()))
            .ReturnsAsync(flight);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new CancelFlightCommandHandler(
            repo.Object, uow.Object, Publisher().Object,
            NullLogger<CancelFlightCommandHandler>.Instance);

        var result = await handler.Handle(
            new CancelFlightCommand(flight.Id, "weather"),
            CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        flight.Status.Should().Be(FlightStatus.Cancelled);
    }
}