using System.Reflection;
using FluentValidation;
using Microsoft.Extensions.DependencyInjection;

namespace Bookings.Application;

public static class DependencyInjection
{
    /// <summary>
    /// Registers validators for this module.
    /// MediatR handlers and pipeline behaviors are registered once in the host.
    /// </summary>
    public static IServiceCollection AddBookingsApplication(this IServiceCollection services)
    {
        var assembly = Assembly.GetExecutingAssembly();
        services.AddValidatorsFromAssembly(assembly, includeInternalTypes: true);
        return services;
    }
}