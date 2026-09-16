using Bookings.Api;
using Bookings.Application;
using Bookings.Infrastructure;
using Bookings.Infrastructure.Persistence;
using FlightCatalog.Api;
using FlightCatalog.Application;
using FlightCatalog.Infrastructure;
using FlightCatalog.Infrastructure.Persistence;
using FlightsPlatform.Api.Endpoints;
using FluentValidation;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.EntityFrameworkCore;
using Scalar.AspNetCore;
using FlightsPlatform.SharedKernel;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOpenApi();

// CORS for Angular dev server (Development only).
builder.Services.AddCors(options =>
{
    options.AddPolicy("frontend", policy =>
    {
        policy.WithOrigins("http://localhost:4200")
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

builder.Services.AddFlightCatalogApplication();
builder.Services.AddFlightCatalogInfrastructure(builder.Configuration);

builder.Services.AddBookingsApplication();
builder.Services.AddBookingsInfrastructure(builder.Configuration);

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
    app.MapScalarApiReference();
    app.UseCors("frontend");
}

app.UseExceptionHandler(errApp => errApp.Run(async ctx =>
{
    var feature = ctx.Features.Get<IExceptionHandlerFeature>();
    var ex = feature?.Error;

    var (status, payload) = ex switch
    {
        ValidationException ve => (StatusCodes.Status400BadRequest,
            (object)new
            {
                error = "validation_failed",
                details = ve.Errors.Select(e => e.ErrorMessage)
            }),
        DomainException de => (StatusCodes.Status400BadRequest,
            new { error = "domain_error", message = de.Message }),
        _ => (StatusCodes.Status500InternalServerError,
            new { error = "internal_error" })
    };

    ctx.Response.StatusCode = status;
    await ctx.Response.WriteAsJsonAsync(payload);
}));

app.UseHttpsRedirection();
app.MapControllers();
app.MapFlightCatalogEndpoints();
app.MapAirportEndpoints();
app.MapBookingsEndpoints();
app.MapDashboardEndpoints();

// Health endpoint for the SPA header indicator.
app.MapGet("/health", () => Results.Ok(new
{
    status = "ok",
    time = DateTimeOffset.UtcNow
}))
.WithTags("Health")
.WithName("GetHealth");

using (var scope = app.Services.CreateScope())
{
    var fcDb = scope.ServiceProvider.GetRequiredService<FlightCatalogDbContext>();
    await fcDb.Database.MigrateAsync();

    var bkDb = scope.ServiceProvider.GetRequiredService<BookingDbContext>();
    await bkDb.Database.MigrateAsync();
}

app.Run();