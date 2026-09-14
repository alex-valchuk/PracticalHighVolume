using FlightCatalog.Application.Abstractions;
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
        var connectionString = configuration.GetConnectionString("FlightCatalog")
            ?? throw new InvalidOperationException(
                "Connection string 'FlightCatalog' is not configured.");

        services.AddSingleton(NpgsqlDataSource.Create(connectionString));

        services.AddDbContext<FlightCatalogDbContext>(opts =>
            opts.UseNpgsql(connectionString));

        services.AddScoped<IFlightRepository, FlightRepository>();
        services.AddScoped<IFlightReadRepository, FlightReadRepository>();
        services.AddScoped<IUnitOfWork, UnitOfWork>();

        return services;
    }
}