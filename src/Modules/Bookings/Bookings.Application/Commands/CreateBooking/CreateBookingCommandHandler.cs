using Bookings.Application.Abstractions;
using Bookings.Domain.Aggregates;
using Bookings.Domain.ValueObjects;
using FlightsPlatform.Application.Abstractions;
using FlightsPlatform.Contracts.Bookings;
using FlightsPlatform.SharedKernel;
using MediatR;
using Microsoft.Extensions.Logging;

namespace Bookings.Application.Commands.CreateBooking;

public sealed class CreateBookingCommandHandler : IRequestHandler<CreateBookingCommand, Result<Guid>>
{
    private readonly IBookingRepository _repository;
    private readonly IUnitOfWork _unitOfWork;
    private readonly IIntegrationEventPublisher _publisher;
    private readonly ILogger<CreateBookingCommandHandler> _logger;

    public CreateBookingCommandHandler(
        IBookingRepository repository,
        IUnitOfWork unitOfWork,
        IIntegrationEventPublisher publisher,
        ILogger<CreateBookingCommandHandler> logger)
    {
        _repository = repository;
        _unitOfWork = unitOfWork;
        _publisher = publisher;
        _logger = logger;
    }

    public async Task<Result<Guid>> Handle(CreateBookingCommand request, CancellationToken ct)
    {
        try
        {
            var booking = Booking.CreateDraft(
                PassengerId.Create(request.PassengerId),
                PassengerName.Create(request.PassengerName),
                request.Currency);

            await _repository.AddAsync(booking, ct);

            await _publisher.PublishAsync(new BookingCreatedIntegrationEvent
            {
                BookingId = booking.Id,
                BookingReference = booking.BookRef.Value,
                PassengerId = booking.PassengerId.Value,
                Currency = booking.TotalAmount.Currency
            }, ct);

            await _unitOfWork.SaveChangesAsync(ct);

            _logger.LogInformation("Created booking {BookingId} ({BookRef})",
                booking.Id, booking.BookRef.Value);

            return Result<Guid>.Success(booking.Id);
        }
        catch (DomainException ex)
        {
            _logger.LogWarning(ex, "Domain rule violated while creating booking");
            return Result<Guid>.Failure(ex.Message, "domain_error");
        }
    }
}