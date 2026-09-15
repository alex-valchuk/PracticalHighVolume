using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Persistence;
using Bookings.Infrastructure.Persistence.Repositories;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Npgsql;

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

        return services;
    }
}