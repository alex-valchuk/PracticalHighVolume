using FlightsPlatform.Application.Abstractions;
using MassTransit;

namespace FlightsPlatform.Api.Messaging;

internal sealed class MassTransitEventPublisher : IIntegrationEventPublisher
{
    private readonly IPublishEndpoint _publishEndpoint;

    public MassTransitEventPublisher(IPublishEndpoint publishEndpoint)
        => _publishEndpoint = publishEndpoint;

    public Task PublishAsync<T>(T @event, CancellationToken ct = default)
        where T : class
        => _publishEndpoint.Publish(@event, ct);
}