using Bookings.Application.Abstractions;
using Bookings.Infrastructure.External;
using Bookings.Infrastructure.Integration.Payments;
using Bookings.Infrastructure.External;
using Bookings.Infrastructure.Options;
using Bookings.Infrastructure.External;
using Bookings.Infrastructure.Persistence;
using Bookings.Infrastructure.External;
using Bookings.Infrastructure.Persistence.Repositories;
using Bookings.Infrastructure.External;
using Bookings.Infrastructure.Persistence.Services;
using Bookings.Infrastructure.External;
using Microsoft.EntityFrameworkCore;
using Bookings.Infrastructure.External;
using Microsoft.Extensions.Configuration;
using Bookings.Infrastructure.External;
using Microsoft.Extensions.DependencyInjection;
using Bookings.Infrastructure.External;
using Npgsql;

using Bookings.Infrastructure.External;
namespace Bookings.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddBookingsInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var connectionString = configuration.GetConnectionString("Booking")
            ?? throw new InvalidOperationException("Connection string 'Booking' is not configured.");

        services.AddDbContext<BookingDbContext>(opts =>
            opts.UseNpgsql(connectionString, npgsql =>
                npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "booking")));

        services.AddSingleton<NpgsqlDataSource>(sp => NpgsqlDataSource.Create(connectionString));

        services.AddScoped<IBookingRepository, BookingRepository>();
        services.AddScoped<IBookingReadRepository, BookingReadRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        services.AddHttpClient<IFlightCatalogClient, HttpFlightCatalogClient>(client =>
        {
            client.BaseAddress = new Uri(
                configuration["FlightCatalog:BaseUrl"]
                ?? throw new InvalidOperationException(
                    "Configuration key 'FlightCatalog:BaseUrl' is required for HttpFlightCatalogClient."));
        });

        services.Configure<PaymentOptions>(configuration.GetSection(PaymentOptions.SectionName));
        services.AddSingleton<PaymentSimulationState>();
        services.AddScoped<ISeatReservationService, SeatReservationService>();
        services.AddScoped<IPaymentGateway, FakePaymentGateway>();

        return services;
    }
}