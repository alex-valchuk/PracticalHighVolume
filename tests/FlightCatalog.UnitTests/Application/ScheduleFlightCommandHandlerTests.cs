using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.Commands.ScheduleFlight;
using FlightCatalog.Domain.Aggregates;
using FlightsPlatform.Application.Abstractions;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FlightCatalog.UnitTests.Application;

public class ScheduleFlightCommandHandlerTests
{
    private static ScheduleFlightCommandHandler Build(
        Mock<IFlightRepository> repo,
        Mock<IUnitOfWork> uow,
        Mock<IIntegrationEventPublisher>? publisher = null)
    {
        var pub = publisher ?? new Mock<IIntegrationEventPublisher>();
        pub.Setup(p => p.PublishAsync(It.IsAny<It.IsAnyType>(), It.IsAny<CancellationToken>()))
           .Returns(Task.CompletedTask);

        return new ScheduleFlightCommandHandler(
            repo.Object, uow.Object, pub.Object,
            NullLogger<ScheduleFlightCommandHandler>.Instance);
    }

    [Fact]
    public async Task Handle_WithValidRequest_ReturnsSuccess()
    {
        var repo = new Mock<IFlightRepository>();
        repo.Setup(r => r.AddAsync(It.IsAny<Flight>(), It.IsAny<CancellationToken>()))
            .Returns(Task.CompletedTask);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(1);

        var handler = Build(repo, uow);

        var cmd = new ScheduleFlightCommand(
            "PG-0421", "SVO", "OVB",
            DateTimeOffset.UtcNow.AddDays(1),
            DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
            "Airbus A320");

        var result = await handler.Handle(cmd, CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value.Should().NotBeEmpty();
        repo.Verify(r => r.AddAsync(It.IsAny<Flight>(), It.IsAny<CancellationToken>()), Times.Once);
        uow.Verify(u => u.SaveChangesAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_WithSameDepartureAndArrival_ReturnsFailure()
    {
        var repo = new Mock<IFlightRepository>();
        var uow = new Mock<IUnitOfWork>();
        var handler = Build(repo, uow);

        var cmd = new ScheduleFlightCommand(
            "PG-0421", "SVO", "SVO",
            DateTimeOffset.UtcNow.AddDays(1),
            DateTimeOffset.UtcNow.AddDays(1).AddHours(4),
            "Airbus A320");

        var result = await handler.Handle(cmd, CancellationToken.None);

        result.IsFailure.Should().BeTrue();
        result.ErrorCode.Should().Be("domain_error");
    }
}