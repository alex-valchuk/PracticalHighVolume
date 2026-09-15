using FlightCatalog.Application.Abstractions;
using FlightCatalog.Application.Commands.SyncAirports;
using FlightCatalog.Domain.Aggregates;
using FlightCatalog.Domain.ValueObjects;
using FluentAssertions;
using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using Xunit;

namespace FlightCatalog.UnitTests.Application;

public class SyncAirportsCommandHandlerTests
{
    [Fact]
    public async Task Handle_WithNewAirport_Creates()
    {
        var source = new Mock<IBookingsSourceReader>();
        source.Setup(s => s.ReadAirportsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<ExternalAirport>
            {
                new("SVO", "Sheremetyevo", "Moscow", "Europe/Moscow", "(37.41,55.97)")
            });

        var repo = new Mock<IAirportRepository>();
        repo.Setup(r => r.GetByCodeAsync(It.IsAny<AirportCode>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync((Airport?)null);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new SyncAirportsCommandHandler(
            source.Object, repo.Object, uow.Object,
            NullLogger<SyncAirportsCommandHandler>.Instance);

        var result = await handler.Handle(new SyncAirportsCommand(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Created.Should().Be(1);
        result.Value.Updated.Should().Be(0);
        repo.Verify(r => r.AddAsync(It.IsAny<Airport>(), It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task Handle_WithExistingAirport_Updates()
    {
        var existing = Airport.Create(
            AirportCode.Create("SVO"), "Old", "OldCity", "UTC",
            Coordinates.Create(0, 0));

        var source = new Mock<IBookingsSourceReader>();
        source.Setup(s => s.ReadAirportsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<ExternalAirport>
            {
                new("SVO", "NewName", "NewCity", "Europe/Moscow", "(37.41,55.97)")
            });

        var repo = new Mock<IAirportRepository>();
        repo.Setup(r => r.GetByCodeAsync(It.IsAny<AirportCode>(), It.IsAny<CancellationToken>()))
            .ReturnsAsync(existing);

        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(1);

        var handler = new SyncAirportsCommandHandler(
            source.Object, repo.Object, uow.Object,
            NullLogger<SyncAirportsCommandHandler>.Instance);

        var result = await handler.Handle(new SyncAirportsCommand(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Updated.Should().Be(1);
        result.Value.Created.Should().Be(0);
        existing.Name.Should().Be("NewName");
    }

    [Fact]
    public async Task Handle_WithInvalidCoordinates_Skips()
    {
        var source = new Mock<IBookingsSourceReader>();
        source.Setup(s => s.ReadAirportsAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(new List<ExternalAirport>
            {
                new("BAD", "Bad", "Nowhere", "UTC", "not-a-point")
            });

        var repo = new Mock<IAirportRepository>();
        var uow = new Mock<IUnitOfWork>();
        uow.Setup(u => u.SaveChangesAsync(It.IsAny<CancellationToken>())).ReturnsAsync(0);

        var handler = new SyncAirportsCommandHandler(
            source.Object, repo.Object, uow.Object,
            NullLogger<SyncAirportsCommandHandler>.Instance);

        var result = await handler.Handle(new SyncAirportsCommand(), CancellationToken.None);

        result.IsSuccess.Should().BeTrue();
        result.Value!.Skipped.Should().Be(1);
    }
}