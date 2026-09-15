using FlightCatalog.Application.Abstractions;
using FlightCatalog.Infrastructure.BackgroundServices;
using FlightCatalog.Infrastructure.Integration.Bookings;
using FlightCatalog.Infrastructure.Persistence;
using FlightCatalog.Infrastructure.Persistence.Repositories;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

namespace FlightCatalog.Infrastructure;

public static class DependencyInjection
{
    public static IServiceCollection AddFlightCatalogInfrastructure(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        var ownConnection = configuration.GetConnectionString("FlightCatalog")
            ?? throw new InvalidOperationException("Connection string 'FlightCatalog' is not configured.");

        var externalConnection = configuration.GetConnectionString("BookingsSource")
            ?? throw new InvalidOperationException("Connection string 'BookingsSource' is not configured.");

        services.AddDbContext<FlightCatalogDbContext>(opts =>
            opts.UseNpgsql(ownConnection, npgsql =>
                npgsql.MigrationsHistoryTable("__EFMigrationsHistory", "flight_catalog")));

        services.AddSingleton<NpgsqlDataSource>(sp => NpgsqlDataSource.Create(ownConnection));

        services.AddKeyedSingleton<NpgsqlDataSource>("bookings",
            (sp, key) => NpgsqlDataSource.Create(externalConnection));

        services.AddScoped<IFlightRepository, FlightRepository>();
        services.AddScoped<IFlightReadRepository, FlightReadRepository>();
        services.AddScoped<IAirportRepository, AirportRepository>();
        services.AddScoped<IAirportReadRepository, AirportReadRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        services.AddScoped<IBookingsSourceReader>(sp =>
        {
            var ds = sp.GetRequiredKeyedService<NpgsqlDataSource>("bookings");
            return new BookingsSourceReader(ds);
        });

        services.Configure<AirportSyncOptions>(configuration.GetSection(AirportSyncOptions.SectionName));
        services.AddHostedService<AirportSyncBackgroundService>();

        return services;
    }
}