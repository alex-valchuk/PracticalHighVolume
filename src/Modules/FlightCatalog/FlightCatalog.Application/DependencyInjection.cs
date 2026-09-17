using System.Reflection;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace FlightCatalog.Application;

public static class DependencyInjection
{
    /// <summary>
    /// Registers validators for this module.
    /// MediatR handlers and pipeline behaviors are registered once in the host
    /// so that behaviors are shared and not duplicated per module.
    /// </summary>
    public static IServiceCollection AddFlightCatalogApplication(this IServiceCollection services)
    {
        var assembly = Assembly.GetExecutingAssembly();
        services.AddValidatorsFromAssembly(assembly, includeInternalTypes: true);
        return services;
    }
}