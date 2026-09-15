using FlightsPlatform.Application.Abstractions;
using MediatR;

namespace FlightCatalog.Application.Commands.SyncAirports;

public sealed record SyncAirportsResult(int Read, int Created, int Updated, int Skipped);

public sealed record SyncAirportsCommand : IRequest<Result<SyncAirportsResult>>;