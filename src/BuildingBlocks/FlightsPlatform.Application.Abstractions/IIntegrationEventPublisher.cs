namespace FlightsPlatform.Application.Abstractions;

/// <summary>
/// Publishes integration events to the message broker.
/// Implementation lives in the host process (MassTransit).
/// Application layer stays broker-agnostic.
/// </summary>
public interface IIntegrationEventPublisher
{
    Task PublishAsync<T>(T @event, CancellationToken ct = default)
        where T : class;
}