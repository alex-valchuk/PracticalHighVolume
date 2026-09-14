using FlightCatalog.Domain.Events;
using FlightCatalog.Domain.ValueObjects;
using FlightsPlatform.SharedKernel;

namespace FlightCatalog.Domain.Aggregates;

public sealed class Flight : AggregateRoot<Guid>
{
    public FlightNumber FlightNumber { get; private set; } = default!;
    public Route Route { get; private set; } = default!;
    public Schedule Schedule { get; private set; } = default!;
    public FlightStatus Status { get; private set; }
    public string AircraftModel { get; private set; } = default!;

    private Flight() { }

    private Flight(Guid id, FlightNumber number, Route route, Schedule schedule, string aircraftModel)
        : base(id)
    {
        FlightNumber = number;
        Route = route;
        Schedule = schedule;
        AircraftModel = aircraftModel;
        Status = FlightStatus.Scheduled;
    }

    public static Flight ScheduleFlight(
        FlightNumber number,
        Route route,
        Schedule schedule,
        string aircraftModel)
    {
        if (string.IsNullOrWhiteSpace(aircraftModel))
            throw new DomainException("Aircraft model is required.");

        var flight = new Flight(Guid.NewGuid(), number, route, schedule, aircraftModel);

        flight.Raise(new FlightScheduled(
            flight.Id,
            number.Value,
            route.Departure.Value,
            route.Arrival.Value,
            schedule.Departure,
            schedule.Arrival));

        return flight;
    }

    public void Delay(DateTimeOffset newDeparture, DateTimeOffset newArrival)
    {
        if (Status == FlightStatus.Cancelled)
            throw new DomainException("Cannot delay a cancelled flight.");

        if (Status == FlightStatus.Departed || Status == FlightStatus.Arrived)
            throw new DomainException("Cannot delay a flight that already departed or arrived.");

        var oldDeparture = Schedule.Departure;
        var delay = newDeparture - oldDeparture;

        Schedule = Schedule.Create(newDeparture, newArrival);
        Status = FlightStatus.Delayed;

        Raise(new FlightDelayed(
            Id,
            FlightNumber.Value,
            oldDeparture,
            newDeparture,
            delay >= TimeSpan.FromHours(3)));
    }

    public void Cancel(string reason)
    {
        if (Status == FlightStatus.Departed || Status == FlightStatus.Arrived)
            throw new DomainException("Cannot cancel a flight that already departed or arrived.");

        if (Status == FlightStatus.Cancelled)
            throw new DomainException("Flight is already cancelled.");

        if (string.IsNullOrWhiteSpace(reason))
            throw new DomainException("Cancellation reason is required.");

        Status = FlightStatus.Cancelled;
        Raise(new FlightCancelled(Id, FlightNumber.Value, reason));
    }
}