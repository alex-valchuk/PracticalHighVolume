using FlightCatalog.Application.Commands.SyncAirports;
using MediatR;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FlightCatalog.Infrastructure.BackgroundServices;

public sealed class AirportSyncBackgroundService : BackgroundService
{
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly AirportSyncOptions _options;
    private readonly ILogger<AirportSyncBackgroundService> _logger;

    public AirportSyncBackgroundService(
        IServiceScopeFactory scopeFactory,
        IOptions<AirportSyncOptions> options,
        ILogger<AirportSyncBackgroundService> logger)
    {
        _scopeFactory = scopeFactory;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("Airport sync is disabled by configuration.");
            return;
        }

        _logger.LogInformation(
            "Airport sync started. Interval={Interval} min, SyncOnStartup={SyncOnStartup}",
            _options.IntervalMinutes, _options.SyncOnStartup);

        if (_options.SyncOnStartup)
        {
            await SafeSyncAsync(stoppingToken);
        }

        var interval = TimeSpan.FromMinutes(Math.Max(1, _options.IntervalMinutes));
        using var timer = new PeriodicTimer(interval);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                if (!await timer.WaitForNextTickAsync(stoppingToken))
                    break;
                await SafeSyncAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }

        _logger.LogInformation("Airport sync stopped.");
    }

    private async Task SafeSyncAsync(CancellationToken ct)
    {
        try
        {
            using var scope = _scopeFactory.CreateScope();
            var mediator = scope.ServiceProvider.GetRequiredService<IMediator>();
            await mediator.Send(new SyncAirportsCommand(), ct);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Airport sync iteration failed.");
        }
    }
}