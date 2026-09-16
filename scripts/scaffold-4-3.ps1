# PowerShell 5.1 compatible

function Write-File {
    param(
        [Parameter(Mandatory=$true)] [string] $Path,
        [Parameter(Mandatory=$true)] [string] $Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $full = Join-Path (Get-Location).Path $Path
    [System.IO.File]::WriteAllText($full, $Content, [System.Text.UTF8Encoding]::new($false))
    Write-Host ("  + " + $Path)
}

$root = (Get-Location).Path

Write-Host ""
Write-Host "=== SPEC-004 / 4.3 - Bookings + Saga demo ==="
Write-Host ""

# ===========================================================================
# BACKEND
# ===========================================================================
Write-Host "=== Backend ==="
Write-Host ""

# --- PaymentSimulationState ---
Write-File "src/Modules/Bookings/Bookings.Infrastructure/Options/PaymentSimulationState.cs" @'
namespace Bookings.Infrastructure.Options;

/// <summary>
/// Runtime-mutable simulation flag used by FakePaymentGateway.
/// Lives as a singleton so that a dev endpoint can flip it without restart.
/// Not used in production.
/// </summary>
public sealed class PaymentSimulationState
{
    public bool SimulateFailureAfterCharge { get; set; }
}
'@

# --- FakePaymentGateway: read from PaymentSimulationState ---
Write-File "src/Modules/Bookings/Bookings.Infrastructure/Integration/Payments/FakePaymentGateway.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Options;
using Bookings.Infrastructure.Persistence;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Bookings.Infrastructure.Integration.Payments;

internal sealed class FakePaymentGateway : IPaymentGateway
{
    private readonly BookingDbContext _db;
    private readonly PaymentOptions _options;
    private readonly PaymentSimulationState _simulation;
    private readonly ILogger<FakePaymentGateway> _logger;

    private static readonly Random Rng = new();

    public FakePaymentGateway(
        BookingDbContext db,
        IOptions<PaymentOptions> options,
        PaymentSimulationState simulation,
        ILogger<FakePaymentGateway> logger)
    {
        _db = db;
        _options = options.Value;
        _simulation = simulation;
        _logger = logger;
    }

    public async Task<PaymentResult> ChargeAsync(
        Guid bookingId, decimal amount, string currency, CancellationToken ct = default)
    {
        var delay = _options.MaxDelayMs > _options.MinDelayMs
            ? Rng.Next(_options.MinDelayMs, _options.MaxDelayMs + 1)
            : Math.Max(0, _options.MinDelayMs);

        if (delay > 0)
            await Task.Delay(delay, ct);

        var failRate = Math.Clamp(_options.FailureRatePercent, 0, 100);
        var shouldFail = Rng.Next(100) < failRate;

        if (shouldFail)
        {
            var failed = Domain.Aggregates.Payment.CreateFailed(bookingId, amount, currency);
            _db.Payments.Add(failed);
            await _db.SaveChangesAsync(ct);

            _logger.LogWarning(
                "FakePaymentGateway DECLINED charge: booking={BookingId} amount={Amount} {Currency}",
                bookingId, amount, currency);

            return new PaymentResult(false, null, "Card declined (fake).");
        }

        var reference = "FAKE-" + Guid.NewGuid().ToString("N").Substring(0, 10).ToUpperInvariant();
        var payment = Domain.Aggregates.Payment.CreateCharged(bookingId, amount, currency, reference);
        _db.Payments.Add(payment);
        await _db.SaveChangesAsync(ct);

        var simulate = _simulation.SimulateFailureAfterCharge;

        _logger.LogInformation(
            "FakePaymentGateway CHARGED: booking={BookingId} amount={Amount} {Currency} payment={PaymentId} ref={Ref} simulateFailure={Sim}",
            bookingId, amount, currency, payment.Id, reference, simulate);

        return new PaymentResult(true, payment.Id, null, simulate);
    }

    public async Task RefundAsync(Guid paymentId, CancellationToken ct = default)
    {
        var payment = await _db.Payments.FindAsync(new object[] { paymentId }, ct);
        if (payment is null)
        {
            _logger.LogWarning("FakePaymentGateway REFUND skipped - payment {PaymentId} not found", paymentId);
            return;
        }

        payment.MarkRefunded();
        await _db.SaveChangesAsync(ct);

        _logger.LogInformation("FakePaymentGateway REFUNDED: payment={PaymentId}", paymentId);
    }
}
'@

# --- DependencyInjection: register PaymentSimulationState ---
Write-File "src/Modules/Bookings/Bookings.Infrastructure/DependencyInjection.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Infrastructure.Integration.FlightCatalog;
using Bookings.Infrastructure.Integration.Payments;
using Bookings.Infrastructure.Options;
using Bookings.Infrastructure.Persistence;
using Bookings.Infrastructure.Persistence.Repositories;
using Bookings.Infrastructure.Persistence.Services;
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

        services.AddScoped<IFlightCatalogClient, FlightCatalogClient>();

        services.Configure<PaymentOptions>(configuration.GetSection(PaymentOptions.SectionName));
        services.AddSingleton<PaymentSimulationState>();
        services.AddScoped<ISeatReservationService, SeatReservationService>();
        services.AddScoped<IPaymentGateway, FakePaymentGateway>();

        return services;
    }
}
'@

# --- GetBookingsListQuery + handler in Bookings.Application ---
Write-File "src/Modules/Bookings/Bookings.Application/Queries/GetBookingsList/GetBookingsListQuery.cs" @'
using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingsList;

public sealed record GetBookingsListResult(IReadOnlyList<BookingDto> Items, int Total);

public sealed record GetBookingsListQuery(int Page = 1, int PageSize = 100) : IRequest<GetBookingsListResult>;
'@

Write-File "src/Modules/Bookings/Bookings.Application/Queries/GetBookingsList/GetBookingsListQueryHandler.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.DTOs;
using MediatR;

namespace Bookings.Application.Queries.GetBookingsList;

public sealed class GetBookingsListQueryHandler
    : IRequestHandler<GetBookingsListQuery, GetBookingsListResult>
{
    private readonly IBookingReadRepository _readRepository;

    public GetBookingsListQueryHandler(IBookingReadRepository readRepository)
        => _readRepository = readRepository;

    public async Task<GetBookingsListResult> Handle(GetBookingsListQuery request, CancellationToken ct)
    {
        var (items, total) = await _readRepository.GetAllAsync(request.Page, request.PageSize, ct);
        return new GetBookingsListResult(items, total);
    }
}
'@

# --- IBookingReadRepository: add GetAllAsync ---
Write-File "src/Modules/Bookings/Bookings.Application/Abstractions/IBookingReadRepository.cs" @'
using Bookings.Application.DTOs;

namespace Bookings.Application.Abstractions;

public interface IBookingReadRepository
{
    Task<BookingDto?> GetByIdAsync(Guid id, CancellationToken ct = default);
    Task<(IReadOnlyList<BookingDto> Items, int Total)> GetAllAsync(
        int page, int pageSize, CancellationToken ct = default);
}
'@

# --- BookingReadRepository: implement GetAllAsync ---
Write-File "src/Modules/Bookings/Bookings.Infrastructure/Persistence/Repositories/BookingReadRepository.cs" @'
using Bookings.Application.Abstractions;
using Bookings.Application.DTOs;
using Dapper;
using Npgsql;

namespace Bookings.Infrastructure.Persistence.Repositories;

public sealed class BookingReadRepository : IBookingReadRepository
{
    private readonly NpgsqlDataSource _dataSource;

    public BookingReadRepository(NpgsqlDataSource dataSource) => _dataSource = dataSource;

    public async Task<BookingDto?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        const string sqlBooking = @"
            SELECT id             AS Id,
                   book_ref       AS BookRef,
                   book_date      AS BookDate,
                   total_amount   AS TotalAmount,
                   currency       AS Currency,
                   status         AS Status,
                   passenger_id   AS PassengerId,
                   passenger_name AS PassengerName
            FROM booking.bookings
            WHERE id = @Id";

        const string sqlTickets = @"
            SELECT id        AS Id,
                   ticket_no AS TicketNo,
                   flight_id AS FlightId,
                   amount    AS Amount
            FROM booking.tickets
            WHERE booking_id = @Id
            ORDER BY ticket_no";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);

        var booking = await conn.QueryFirstOrDefaultAsync<BookingDto>(
            new CommandDefinition(sqlBooking, new { Id = id }, cancellationToken: ct));

        if (booking is null) return null;

        var tickets = await conn.QueryAsync<TicketDto>(
            new CommandDefinition(sqlTickets, new { Id = id }, cancellationToken: ct));

        booking.Tickets.AddRange(tickets);
        return booking;
    }

    public async Task<(IReadOnlyList<BookingDto> Items, int Total)> GetAllAsync(
        int page, int pageSize, CancellationToken ct = default)
    {
        if (page < 1) page = 1;
        if (pageSize < 1) pageSize = 100;
        if (pageSize > 500) pageSize = 500;

        const string sqlCount = "SELECT COUNT(*) FROM booking.bookings";
        const string sqlPage = @"
            SELECT id             AS Id,
                   book_ref       AS BookRef,
                   book_date      AS BookDate,
                   total_amount   AS TotalAmount,
                   currency       AS Currency,
                   status         AS Status,
                   passenger_id   AS PassengerId,
                   passenger_name AS PassengerName
            FROM booking.bookings
            ORDER BY book_date DESC
            OFFSET @Offset LIMIT @Limit";

        const string sqlTicketsForIds = @"
            SELECT booking_id AS BookingId,
                   id         AS Id,
                   ticket_no  AS TicketNo,
                   flight_id  AS FlightId,
                   amount     AS Amount
            FROM booking.tickets
            WHERE booking_id = ANY(@Ids)
            ORDER BY ticket_no";

        await using var conn = await _dataSource.OpenConnectionAsync(ct);

        var total = await conn.ExecuteScalarAsync<int>(
            new CommandDefinition(sqlCount, cancellationToken: ct));

        var bookings = (await conn.QueryAsync<BookingDto>(
            new CommandDefinition(sqlPage,
                new { Offset = (page - 1) * pageSize, Limit = pageSize },
                cancellationToken: ct))).ToList();

        if (bookings.Count > 0)
        {
            var ids = bookings.Select(b => b.Id).ToArray();

            var tickets = await conn.QueryAsync<TicketWithBookingRow>(
                new CommandDefinition(sqlTicketsForIds, new { Ids = ids }, cancellationToken: ct));

            var byBooking = tickets
                .GroupBy(t => t.BookingId)
                .ToDictionary(g => g.Key, g => g.ToList());

            foreach (var b in bookings)
            {
                if (byBooking.TryGetValue(b.Id, out var list))
                {
                    foreach (var t in list)
                    {
                        b.Tickets.Add(new TicketDto
                        {
                            Id = t.Id,
                            TicketNo = t.TicketNo,
                            FlightId = t.FlightId,
                            Amount = t.Amount
                        });
                    }
                }
            }
        }

        return (bookings, total);
    }

    private sealed class TicketWithBookingRow
    {
        public Guid BookingId { get; init; }
        public Guid Id { get; init; }
        public string TicketNo { get; init; } = default!;
        public Guid FlightId { get; init; }
        public decimal Amount { get; init; }
    }
}
'@

# --- BookingsEndpoints: add GET /bookings list ---
Write-File "src/Modules/Bookings/Bookings.Api/BookingsEndpoints.cs" @'
using Bookings.Api.Contracts;
using Bookings.Application.Commands.AddTicket;
using Bookings.Application.Commands.CancelBooking;
using Bookings.Application.Commands.ConfirmBooking;
using Bookings.Application.Commands.CreateBooking;
using Bookings.Application.Queries.GetBookingById;
using Bookings.Application.Queries.GetBookingsList;
using MediatR;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace Bookings.Api;

public static class BookingsEndpoints
{
    public static IEndpointRouteBuilder MapBookingsEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/bookings").WithTags("Bookings");

        group.MapPost("/", async (
            CreateBookingRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new CreateBookingCommand(req.PassengerId, req.PassengerName, req.Currency);
            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/bookings/{result.Value}", new { id = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapGet("/", async (
            int? page,
            int? pageSize,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(
                new GetBookingsListQuery(page ?? 1, pageSize ?? 100), ct);
            return Results.Ok(new
            {
                items = result.Items,
                total = result.Total,
                page = page ?? 1,
                pageSize = pageSize ?? 100
            });
        });

        group.MapGet("/{id:guid}", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var dto = await mediator.Send(new GetBookingByIdQuery(id), ct);
            return dto is null ? Results.NotFound() : Results.Ok(dto);
        });

        group.MapPost("/{id:guid}/tickets", async (
            Guid id,
            AddTicketRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var cmd = new AddTicketCommand(
                id, req.FlightId, req.PassengerId, req.PassengerName, req.Amount);

            var result = await mediator.Send(cmd, ct);

            return result.IsSuccess
                ? Results.Created($"/bookings/{id}/tickets/{result.Value}",
                    new { ticketId = result.Value })
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/confirm", async (
            Guid id,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new ConfirmBookingCommand(id), ct);
            return result.IsSuccess
                ? Results.Ok(result.Value)
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        group.MapPost("/{id:guid}/cancel", async (
            Guid id,
            CancelBookingRequest req,
            IMediator mediator,
            CancellationToken ct) =>
        {
            var result = await mediator.Send(new CancelBookingCommand(id, req.Reason), ct);
            return result.IsSuccess
                ? Results.NoContent()
                : Results.BadRequest(new { error = result.Error, code = result.ErrorCode });
        });

        return app;
    }
}
'@

# --- Admin endpoints: simulate payment failure ---
Write-File "src/Hosts/FlightsPlatform.Api/Endpoints/AdminEndpoints.cs" @'
using Bookings.Infrastructure.Options;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Routing;

namespace FlightsPlatform.Api.Endpoints;

public static class AdminEndpoints
{
    public static IEndpointRouteBuilder MapAdminEndpoints(this IEndpointRouteBuilder app)
    {
        var group = app.MapGroup("/admin").WithTags("Admin (dev only)");

        group.MapGet("/payment/simulate-failure", (PaymentSimulationState state) =>
            Results.Ok(new { enabled = state.SimulateFailureAfterCharge }));

        group.MapPost("/payment/simulate-failure", (
            SimulateFailureRequest body,
            PaymentSimulationState state) =>
        {
            state.SimulateFailureAfterCharge = body.Enabled;
            return Results.Ok(new { enabled = state.SimulateFailureAfterCharge });
        });

        return app;
    }

    public sealed record SimulateFailureRequest(bool Enabled);
}
'@

# --- Update Program.cs: register PaymentSimulationState + admin endpoints ---
Write-File "src/Hosts/FlightsPlatform.Api/Program.cs" @'
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

if (app.Environment.IsDevelopment())
{
    app.MapAdminEndpoints();
}

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
'@

# ===========================================================================
# FRONTEND
# ===========================================================================
Write-Host ""
Write-Host "=== Frontend ==="
Write-Host ""

# --- Update booking.model.ts - ensure FlightStatus is there ---
Write-File "frontend/src/app/core/api/models/booking.model.ts" @'
export interface Ticket {
  id: string;
  ticketNo: string;
  flightId: string;
  amount: number;
}

export interface Booking {
  id: string;
  bookRef: string;
  bookDate: string;
  totalAmount: number;
  currency: string;
  status: number;
  passengerId: string;
  passengerName: string;
  tickets: Ticket[];
}

export interface BookingListResponse {
  items: Booking[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CreateBookingRequest {
  passengerId: string;
  passengerName: string;
  currency: string;
}

export interface AddTicketRequest {
  flightId: string;
  passengerId: string;
  passengerName: string;
  amount: number;
}

export interface ConfirmBookingResult {
  bookingId: string;
  confirmed: boolean;
  failureReason?: string | null;
}

export interface CancelBookingRequest {
  reason: string;
}

export const BookingStatus = {
  Pending: 0,
  Confirmed: 1,
  Cancelled: 2,
  Expired: 3
} as const;

export const FlightStatus = {
  Scheduled: 0,
  Delayed: 1,
  Departed: 2,
  Arrived: 3,
  Cancelled: 4
} as const;

export interface DashboardSummary {
  flights: number;
  airports: number;
  bookings: number;
  activeBookings: number;
}

export interface HealthResponse {
  status: string;
  time: string;
}
'@

# --- BookingsService ---
Write-File "frontend/src/app/features/bookings/bookings.service.ts" @'
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';
import {
  Booking,
  BookingListResponse,
  CreateBookingRequest,
  AddTicketRequest,
  ConfirmBookingResult,
  CancelBookingRequest
} from '../../core/api/models/booking.model';

@Injectable({ providedIn: 'root' })
export class BookingsService {
  private readonly api = inject(ApiService);

  list(page = 1, pageSize = 100): Observable<BookingListResponse> {
    return this.api.get<BookingListResponse>('/bookings', { page, pageSize });
  }

  getById(id: string): Observable<Booking> {
    return this.api.get<Booking>(`/bookings/${id}`);
  }

  create(req: CreateBookingRequest): Observable<{ id: string }> {
    return this.api.post<{ id: string }>('/bookings', req);
  }

  addTicket(bookingId: string, req: AddTicketRequest): Observable<{ ticketId: string }> {
    return this.api.post<{ ticketId: string }>(`/bookings/${bookingId}/tickets`, req);
  }

  confirm(bookingId: string): Observable<ConfirmBookingResult> {
    return this.api.post<ConfirmBookingResult>(`/bookings/${bookingId}/confirm`, {});
  }

  cancel(bookingId: string, req: CancelBookingRequest): Observable<void> {
    return this.api.post<void>(`/bookings/${bookingId}/cancel`, req);
  }
}
'@

# --- AdminService (simulate failure toggle) ---
Write-File "frontend/src/app/features/bookings/admin.service.ts" @'
import { Injectable, inject } from '@angular/core';
import { Observable } from 'rxjs';
import { ApiService } from '../../core/api/api.service';

export interface SimulateFailureState {
  enabled: boolean;
}

@Injectable({ providedIn: 'root' })
export class AdminService {
  private readonly api = inject(ApiService);

  getSimulateFailure(): Observable<SimulateFailureState> {
    return this.api.get<SimulateFailureState>('/admin/payment/simulate-failure');
  }

  setSimulateFailure(enabled: boolean): Observable<SimulateFailureState> {
    return this.api.post<SimulateFailureState>('/admin/payment/simulate-failure', { enabled });
  }
}
'@

# --- CreateBookingDialog ---
Write-File "frontend/src/app/features/bookings/create-booking-dialog.component.ts" @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { CreateBookingRequest } from '../../core/api/models/booking.model';
import { BookingsService } from './bookings.service';

@Component({
  selector: 'app-create-booking-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, ButtonModule, InputTextModule],
  template: `
    <p-dialog
      header="Create booking"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '480px' }"
      (onHide)="reset()">

      <div class="form-grid">
        <label>Passenger ID</label>
        <input pInputText [(ngModel)]="model.passengerId" placeholder="1234567890" maxlength="20" />

        <label>Passenger name</label>
        <input pInputText [(ngModel)]="model.passengerName" placeholder="IVANOV IVAN" maxlength="200" />

        <label>Currency</label>
        <input pInputText [(ngModel)]="model.currency" placeholder="RUB" maxlength="3" />
      </div>

      <ng-template #footer>
        <button pButton type="button" label="Cancel" severity="secondary"
                (click)="visible = false"></button>
        <button pButton type="button" label="Create"
                [loading]="saving()"
                (click)="submit()"></button>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 0.75rem 1rem; align-items: center; padding: 0.5rem 0; }
    .form-grid label { color: var(--text-muted); font-size: 0.9rem; }
  `]
})
export class CreateBookingDialogComponent {
  @Input() visible = false;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() created = new EventEmitter<string>();

  private readonly service = inject(BookingsService);
  private readonly messages = inject(MessageService);

  model: CreateBookingRequest = this.empty();
  readonly saving = signal(false);

  private empty(): CreateBookingRequest {
    return { passengerId: '', passengerName: '', currency: 'RUB' };
  }

  reset(): void { this.model = this.empty(); }

  submit(): void {
    if (!this.model.passengerId || !this.model.passengerName || !this.model.currency) {
      this.messages.add({ severity: 'warn', summary: 'Missing fields', detail: 'Fill all fields.' });
      return;
    }

    this.saving.set(true);
    this.service.create(this.model).subscribe({
      next: (resp) => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Booking created', detail: 'Draft booking created.' });
        this.visible = false;
        this.visibleChange.emit(false);
        this.created.emit(resp.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Create failed', detail: err.message });
      }
    });
  }
}
'@

# --- AddTicketDialog ---
Write-File "frontend/src/app/features/bookings/add-ticket-dialog.component.ts" @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { InputNumberModule } from 'primeng/inputnumber';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { AddTicketRequest, Booking } from '../../core/api/models/booking.model';
import { BookingsService } from './bookings.service';

@Component({
  selector: 'app-add-ticket-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, ButtonModule, InputTextModule, InputNumberModule],
  template: `
    <p-dialog
      header="Add ticket"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '520px' }"
      (onHide)="reset()">

      <p class="hint">
        Booking <strong>{{ booking?.bookRef }}</strong>
      </p>

      <div class="form-grid">
        <label>Flight ID</label>
        <input pInputText [(ngModel)]="model.flightId" placeholder="GUID of the flight" />

        <label>Passenger ID</label>
        <input pInputText [(ngModel)]="model.passengerId" placeholder="9999999999" maxlength="20" />

        <label>Passenger name</label>
        <input pInputText [(ngModel)]="model.passengerName" placeholder="PETROV PETR" maxlength="200" />

        <label>Amount</label>
        <p-inputNumber [(ngModel)]="model.amount" [min]="0.01" [minFractionDigits]="2" [maxFractionDigits]="2"></p-inputNumber>
      </div>

      <small class="tip">
        Tip: get a flight ID from the Flights page or from Scalar.
      </small>

      <ng-template #footer>
        <button pButton type="button" label="Cancel" severity="secondary"
                (click)="visible = false"></button>
        <button pButton type="button" label="Add ticket"
                [loading]="saving()"
                (click)="submit()"></button>
      </ng-template>
    </p-dialog>
  `,
  styles: [`
    .hint { color: var(--text-muted); margin: 0 0 1rem; }
    .form-grid { display: grid; grid-template-columns: 140px 1fr; gap: 0.75rem 1rem; align-items: center; padding: 0.5rem 0; }
    .form-grid label { color: var(--text-muted); font-size: 0.9rem; }
    .tip { color: var(--text-muted); display: block; margin-top: 0.5rem; }
  `]
})
export class AddTicketDialogComponent {
  @Input() visible = false;
  @Input() booking: Booking | null = null;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() added = new EventEmitter<string>();

  private readonly service = inject(BookingsService);
  private readonly messages = inject(MessageService);

  model: AddTicketRequest = this.empty();
  readonly saving = signal(false);

  private empty(): AddTicketRequest {
    return { flightId: '', passengerId: '', passengerName: '', amount: 12000 };
  }

  reset(): void { this.model = this.empty(); }

  submit(): void {
    if (!this.booking) return;
    if (!this.model.flightId || !this.model.passengerId || !this.model.passengerName || !this.model.amount) {
      this.messages.add({ severity: 'warn', summary: 'Missing fields', detail: 'Fill all fields.' });
      return;
    }

    this.saving.set(true);
    this.service.addTicket(this.booking.id, this.model).subscribe({
      next: () => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Ticket added', detail: 'Ticket added to booking.' });
        this.visible = false;
        this.visibleChange.emit(false);
        this.added.emit(this.booking!.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Add ticket failed', detail: err.message });
      }
    });
  }
}
'@

# --- CancelBookingDialog ---
Write-File "frontend/src/app/features/bookings/cancel-booking-dialog.component.ts" @'
import { Component, EventEmitter, Input, Output, signal, inject } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DialogModule } from 'primeng/dialog';
import { ButtonModule } from 'primeng/button';
import { TextareaModule } from 'primeng/textarea';
import { MessageService } from 'primeng/api';
import { ApiError } from '../../core/api/models/api-error.model';
import { Booking } from '../../core/api/models/booking.model';
import { BookingsService } from './bookings.service';

@Component({
  selector: 'app-cancel-booking-dialog',
  standalone: true,
  imports: [FormsModule, DialogModule, ButtonModule, TextareaModule],
  template: `
    <p-dialog
      header="Cancel booking"
      [(visible)]="visible"
      [modal]="true"
      [style]="{ width: '480px' }"
      (onHide)="reset()">

      <p class="hint">
        Cancel booking <strong>{{ booking?.bookRef }}</strong>? This cannot be undone.
      </p>

      <textarea pTextarea [(ngModel)]="reason" rows="3"
                placeholder="Cancellation reason"
                style="width: 100%;"></textarea>

      <ng-template #footer>
        <button pButton type="button" label="Keep booking" severity="secondary"
                (click)="visible = false"></button>
        <button pButton type="button" label="Cancel booking" severity="danger"
                [loading]="saving()"
                (click)="submit()"></button>
      </ng-template>
    </p-dialog>
  `,
  styles: [`.hint { color: var(--text-muted); margin: 0 0 1rem; }`]
})
export class CancelBookingDialogComponent {
  @Input() visible = false;
  @Input() booking: Booking | null = null;
  @Output() visibleChange = new EventEmitter<boolean>();
  @Output() cancelled = new EventEmitter<string>();

  private readonly service = inject(BookingsService);
  private readonly messages = inject(MessageService);

  reason = '';
  readonly saving = signal(false);

  reset(): void { this.reason = ''; }

  submit(): void {
    if (!this.booking) return;
    if (!this.reason.trim()) {
      this.messages.add({ severity: 'warn', summary: 'Reason required', detail: 'Enter a reason.' });
      return;
    }

    this.saving.set(true);
    this.service.cancel(this.booking.id, { reason: this.reason.trim() }).subscribe({
      next: () => {
        this.saving.set(false);
        this.messages.add({ severity: 'success', summary: 'Booking cancelled', detail: 'Booking cancelled.' });
        this.visible = false;
        this.visibleChange.emit(false);
        this.cancelled.emit(this.booking!.id);
      },
      error: (err: ApiError) => {
        this.saving.set(false);
        this.messages.add({ severity: 'error', summary: 'Cancel failed', detail: err.message });
      }
    });
  }
}
'@

# --- Bookings list page ---
Write-File "frontend/src/app/features/bookings/bookings.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe, DecimalPipe } from '@angular/common';
import { Router } from '@angular/router';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { InputTextModule } from 'primeng/inputtext';
import { TagModule } from 'primeng/tag';
import { ToggleSwitchModule } from 'primeng/toggleswitch';
import { MessageService } from 'primeng/api';
import { Booking, BookingStatus } from '../../core/api/models/booking.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { BookingsService } from './bookings.service';
import { AdminService } from './admin.service';
import { CreateBookingDialogComponent } from './create-booking-dialog.component';

@Component({
  selector: 'app-bookings-page',
  standalone: true,
  imports: [
    FormsModule, DatePipe, DecimalPipe,
    TableModule, ButtonModule, InputTextModule, TagModule, ToggleSwitchModule,
    CreateBookingDialogComponent
  ],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <h1>Bookings</h1>
          <p class="subtitle">Manage passenger bookings and confirmations</p>
        </div>
        <div class="actions">
          <div class="sim-toggle">
            <label>
              <p-toggleSwitch [(ngModel)]="simulateFailure" (onChange)="toggleSimulation()"></p-toggleSwitch>
              <span>Demo: fail next payment</span>
            </label>
          </div>
          <button pButton type="button" icon="pi pi-plus" label="Create"
                  (click)="showCreate = true"></button>
        </div>
      </div>

      <p-table
        [value]="bookings()"
        [loading]="loading()"
        [paginator]="true"
        [rows]="20"
        [rowsPerPageOptions]="[10, 20, 50]"
        [globalFilterFields]="['bookRef', 'passengerName', 'passengerId']"
        #dt
        styleClass="p-datatable-sm">

        <ng-template #caption>
          <div class="table-caption">
            <input pInputText type="text"
                   placeholder="Search by ref or passenger..."
                   (input)="dt.filterGlobal($any($event.target).value, 'contains')" />
            <span class="count">{{ bookings().length }} bookings</span>
          </div>
        </ng-template>

        <ng-template #header>
          <tr>
            <th pSortableColumn="bookRef">Ref <p-sort-icon field="bookRef"></p-sort-icon></th>
            <th pSortableColumn="passengerName">Passenger <p-sort-icon field="passengerName"></p-sort-icon></th>
            <th>Book date</th>
            <th>Total</th>
            <th>Tickets</th>
            <th>Status</th>
            <th style="width: 120px;">Actions</th>
          </tr>
        </ng-template>

        <ng-template #body let-booking>
          <tr>
            <td><strong>{{ booking.bookRef }}</strong></td>
            <td>
              {{ booking.passengerName }}
              <span class="muted">({{ booking.passengerId }})</span>
            </td>
            <td>{{ booking.bookDate | date:'short' }}</td>
            <td>{{ booking.totalAmount | number:'1.2-2' }} {{ booking.currency }}</td>
            <td>{{ booking.tickets.length }}</td>
            <td>
              <p-tag [value]="statusLabel(booking.status)"
                     [severity]="statusSeverity(booking.status)"></p-tag>
            </td>
            <td>
              <button pButton type="button" icon="pi pi-external-link"
                      severity="info" text
                      (click)="openDetails(booking.id)"
                      title="Details"></button>
            </td>
          </tr>
        </ng-template>

        <ng-template #emptymessage>
          <tr>
            <td colspan="7" class="empty">
              No bookings yet. Create one to get started.
            </td>
          </tr>
        </ng-template>
      </p-table>

      <app-create-booking-dialog
        [(visible)]="showCreate"
        (created)="onCreated($event)"></app-create-booking-dialog>
    </div>
  `,
  styles: [`
    .table-caption { display: flex; align-items: center; justify-content: space-between; gap: 1rem; flex-wrap: wrap; }
    .count { color: var(--text-muted); font-size: 0.9rem; }
    .muted { color: var(--text-muted); font-size: 0.85rem; }
    .empty { text-align: center; padding: 2rem; color: var(--text-muted); }
    .sim-toggle label { display: flex; align-items: center; gap: 0.5rem; font-size: 0.9rem; color: var(--text-muted); }
  `]
})
export class BookingsPage implements OnInit {
  private readonly service = inject(BookingsService);
  private readonly admin = inject(AdminService);
  private readonly messages = inject(MessageService);
  private readonly router = inject(Router);

  readonly bookings = signal<Booking[]>([]);
  readonly loading = signal(false);
  simulateFailure = false;
  showCreate = false;

  ngOnInit(): void {
    this.load();
    this.loadSimulationState();
  }

  private load(): void {
    this.loading.set(true);
    this.service.list().subscribe({
      next: (resp) => {
        this.bookings.set(resp.items);
        this.loading.set(false);
      },
      error: (err: ApiError) => {
        this.loading.set(false);
        this.messages.add({ severity: 'error', summary: 'Failed to load bookings', detail: err.message });
      }
    });
  }

  private loadSimulationState(): void {
    this.admin.getSimulateFailure().subscribe({
      next: (s) => { this.simulateFailure = s.enabled; },
      error: () => { /* admin endpoint may be disabled outside dev - ignore */ }
    });
  }

  toggleSimulation(): void {
    this.admin.setSimulateFailure(this.simulateFailure).subscribe({
      next: (s) => {
        this.simulateFailure = s.enabled;
        this.messages.add({
          severity: s.enabled ? 'warn' : 'success',
          summary: s.enabled ? 'Demo mode: payment will fail after charge' : 'Demo mode disabled',
          detail: s.enabled
            ? 'Next confirm will trigger saga compensation.'
            : 'Payments behave normally.'
        });
      },
      error: (err: ApiError) => {
        this.messages.add({ severity: 'error', summary: 'Toggle failed', detail: err.message });
      }
    });
  }

  openDetails(id: string): void {
    this.router.navigate(['/bookings', id]);
  }

  onCreated(id: string): void {
    this.load();
    this.openDetails(id);
  }

  statusLabel(s: number): string {
    switch (s) {
      case BookingStatus.Pending:   return 'Pending';
      case BookingStatus.Confirmed: return 'Confirmed';
      case BookingStatus.Cancelled: return 'Cancelled';
      case BookingStatus.Expired:   return 'Expired';
      default: return 'Unknown';
    }
  }

  statusSeverity(s: number): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (s) {
      case BookingStatus.Pending:   return 'warn';
      case BookingStatus.Confirmed: return 'success';
      case BookingStatus.Cancelled: return 'danger';
      case BookingStatus.Expired:   return 'danger';
      default: return 'secondary';
    }
  }
}
'@

# --- Booking details page ---
Write-File "frontend/src/app/features/bookings/booking-details.page.ts" @'
import { Component, inject, OnInit, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { DatePipe, DecimalPipe } from '@angular/common';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { TableModule } from 'primeng/table';
import { ButtonModule } from 'primeng/button';
import { TagModule } from 'primeng/tag';
import { MessageService } from 'primeng/api';
import { Booking, BookingStatus, ConfirmBookingResult } from '../../core/api/models/booking.model';
import { ApiError } from '../../core/api/models/api-error.model';
import { BookingsService } from './bookings.service';
import { AddTicketDialogComponent } from './add-ticket-dialog.component';
import { CancelBookingDialogComponent } from './cancel-booking-dialog.component';

@Component({
  selector: 'app-booking-details-page',
  standalone: true,
  imports: [
    FormsModule, DatePipe, DecimalPipe, RouterLink,
    TableModule, ButtonModule, TagModule,
    AddTicketDialogComponent, CancelBookingDialogComponent
  ],
  template: `
    <div class="page">
      <div class="page-header">
        <div>
          <a routerLink="/bookings" class="back">
            <i class="pi pi-arrow-left"></i> Back to bookings
          </a>
          <h1>
            Booking {{ booking()?.bookRef }}
            @if (booking()) {
              <p-tag [value]="statusLabel(booking()!.status)"
                     [severity]="statusSeverity(booking()!.status)"
                     styleClass="ml-2"></p-tag>
            }
          </h1>
        </div>
        <div class="actions">
          @if (canAddTicket()) {
            <button pButton type="button" icon="pi pi-plus" label="Add ticket"
                    (click)="showAddTicket = true"></button>
          }
          @if (canConfirm()) {
            <button pButton type="button" icon="pi pi-check" label="Confirm"
                    severity="success"
                    [loading]="confirming()"
                    (click)="confirm()"></button>
          }
          @if (canCancel()) {
            <button pButton type="button" icon="pi pi-times" label="Cancel"
                    severity="danger"
                    (click)="showCancel = true"></button>
          }
        </div>
      </div>

      @if (loading()) {
        <p>Loading...</p>
      } @else if (!booking()) {
        <p class="error">Booking not found.</p>
      } @else {
        <div class="info-grid">
          <div class="info-card">
            <div class="label">Passenger</div>
            <div class="value">{{ booking()!.passengerName }}</div>
            <div class="muted">ID: {{ booking()!.passengerId }}</div>
          </div>
          <div class="info-card">
            <div class="label">Book date</div>
            <div class="value">{{ booking()!.bookDate | date:'medium' }}</div>
          </div>
          <div class="info-card">
            <div class="label">Total amount</div>
            <div class="value">{{ booking()!.totalAmount | number:'1.2-2' }} {{ booking()!.currency }}</div>
          </div>
          <div class="info-card">
            <div class="label">Tickets</div>
            <div class="value">{{ booking()!.tickets.length }}</div>
          </div>
        </div>

        @if (sagaResult()) {
          <div class="saga-panel" [class.success]="sagaResult()!.confirmed" [class.failure]="!sagaResult()!.confirmed">
            <div class="saga-header">
              <i class="pi" [class.pi-check-circle]="sagaResult()!.confirmed"
                            [class.pi-exclamation-triangle]="!sagaResult()!.confirmed"></i>
              <strong>
                @if (sagaResult()!.confirmed) {
                  Saga completed: booking confirmed
                } @else {
                  Saga failed and compensated
                }
              </strong>
            </div>
            @if (!sagaResult()!.confirmed) {
              <div class="saga-reason">{{ sagaResult()!.failureReason }}</div>
              <ol class="saga-steps">
                <li class="ok">Verify flights</li>
                <li class="ok">Reserve seats</li>
                <li class="fail">Charge payment (failed)</li>
                <li class="compensate">Compensation: release seats</li>
                <li class="compensate">Compensation: refund payment (if charged)</li>
                <li class="compensate">Compensation: mark booking Expired</li>
              </ol>
            } @else {
              <ol class="saga-steps">
                <li class="ok">Verify flights</li>
                <li class="ok">Reserve seats</li>
                <li class="ok">Charge payment</li>
                <li class="ok">Mark booking Confirmed</li>
              </ol>
            }
            <button pButton type="button" text icon="pi pi-times" label="Dismiss"
                    (click)="sagaResult.set(null)"></button>
          </div>
        }

        <h2>Tickets</h2>
        <p-table [value]="booking()!.tickets" styleClass="p-datatable-sm">
          <ng-template #header>
            <tr>
              <th>Ticket number</th>
              <th>Flight ID</th>
              <th>Amount</th>
            </tr>
          </ng-template>
          <ng-template #body let-ticket>
            <tr>
              <td><code>{{ ticket.ticketNo }}</code></td>
              <td><code class="muted">{{ ticket.flightId }}</code></td>
              <td>{{ ticket.amount | number:'1.2-2' }} {{ booking()!.currency }}</td>
            </tr>
          </ng-template>
          <ng-template #emptymessage>
            <tr>
              <td colspan="3" class="empty">No tickets yet. Add a ticket to continue.</td>
            </tr>
          </ng-template>
        </p-table>
      }

      <app-add-ticket-dialog
        [(visible)]="showAddTicket"
        [booking]="booking()"
        (added)="reload()"></app-add-ticket-dialog>

      <app-cancel-booking-dialog
        [(visible)]="showCancel"
        [booking]="booking()"
        (cancelled)="reload()"></app-cancel-booking-dialog>
    </div>
  `,
  styles: [`
    .back { display: inline-block; margin-bottom: 0.5rem; font-size: 0.9rem; }
    h1 { display: flex; align-items: center; gap: 0.5rem; margin: 0; font-size: 1.5rem; }
    h2 { margin-top: 2rem; font-size: 1.1rem; }
    .info-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; margin-bottom: 1.5rem; }
    .info-card { background: var(--surface); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; }
    .info-card .label { color: var(--text-muted); font-size: 0.8rem; text-transform: uppercase; margin-bottom: 0.35rem; }
    .info-card .value { font-size: 1.1rem; font-weight: 600; }
    .info-card .muted { color: var(--text-muted); font-size: 0.85rem; margin-top: 0.25rem; }
    .muted { color: var(--text-muted); }
    .error { color: var(--danger); }
    .empty { text-align: center; padding: 2rem; color: var(--text-muted); }
    .saga-panel { border-radius: 8px; padding: 1rem 1.25rem; margin-bottom: 1.5rem; border: 1px solid; }
    .saga-panel.success { background: rgba(22,163,74,0.08); border-color: var(--success); }
    .saga-panel.failure { background: rgba(220,38,38,0.08); border-color: var(--danger); }
    .saga-header { display: flex; align-items: center; gap: 0.5rem; font-size: 1.05rem; margin-bottom: 0.5rem; }
    .saga-panel.success .saga-header .pi { color: var(--success); }
    .saga-panel.failure .saga-header .pi { color: var(--danger); }
    .saga-reason { color: var(--danger); margin-bottom: 0.75rem; }
    .saga-steps { margin: 0.5rem 0 0; padding-left: 1.25rem; }
    .saga-steps li { margin-bottom: 0.25rem; }
    .saga-steps li.ok { color: var(--text); }
    .saga-steps li.fail { color: var(--danger); font-weight: 600; }
    .saga-steps li.compensate { color: var(--warning); font-style: italic; }
  `]
})
export class BookingDetailsPage implements OnInit {
  private readonly service = inject(BookingsService);
  private readonly route = inject(ActivatedRoute);
  private readonly router = inject(Router);
  private readonly messages = inject(MessageService);

  readonly booking = signal<Booking | null>(null);
  readonly loading = signal(false);
  readonly confirming = signal(false);
  readonly sagaResult = signal<ConfirmBookingResult | null>(null);

  showAddTicket = false;
  showCancel = false;

  ngOnInit(): void {
    const id = this.route.snapshot.paramMap.get('id');
    if (!id) {
      this.router.navigate(['/bookings']);
      return;
    }
    this.load(id);
  }

  private load(id: string): void {
    this.loading.set(true);
    this.service.getById(id).subscribe({
      next: (b) => { this.booking.set(b); this.loading.set(false); },
      error: (err: ApiError) => {
        this.loading.set(false);
        this.messages.add({ severity: 'error', summary: 'Failed to load booking', detail: err.message });
      }
    });
  }

  reload(): void {
    const b = this.booking();
    if (b) this.load(b.id);
  }

  confirm(): void {
    const b = this.booking();
    if (!b) return;

    this.confirming.set(true);
    this.sagaResult.set(null);

    this.service.confirm(b.id).subscribe({
      next: (res) => {
        this.confirming.set(false);
        this.sagaResult.set(res);
        this.messages.add({
          severity: 'success',
          summary: 'Booking confirmed',
          detail: `Saga completed for ${b.bookRef}.`
        });
        this.reload();
      },
      error: (err: ApiError) => {
        this.confirming.set(false);
        this.sagaResult.set({
          bookingId: b.id,
          confirmed: false,
          failureReason: err.message
        });
        this.messages.add({
          severity: 'error',
          summary: 'Saga failed - see details',
          detail: err.message
        });
        this.reload();
      }
    });
  }

  canAddTicket(): boolean {
    return this.booking()?.status === BookingStatus.Pending;
  }

  canConfirm(): boolean {
    const b = this.booking();
    return !!b && b.status === BookingStatus.Pending && b.tickets.length > 0;
  }

  canCancel(): boolean {
    return this.booking()?.status === BookingStatus.Pending;
  }

  statusLabel(s: number): string {
    switch (s) {
      case BookingStatus.Pending:   return 'Pending';
      case BookingStatus.Confirmed: return 'Confirmed';
      case BookingStatus.Cancelled: return 'Cancelled';
      case BookingStatus.Expired:   return 'Expired';
      default: return 'Unknown';
    }
  }

  statusSeverity(s: number): 'success' | 'info' | 'warn' | 'danger' | 'secondary' {
    switch (s) {
      case BookingStatus.Pending:   return 'warn';
      case BookingStatus.Confirmed: return 'success';
      case BookingStatus.Cancelled: return 'danger';
      case BookingStatus.Expired:   return 'danger';
      default: return 'secondary';
    }
  }
}
'@

# --- Update routes: add /bookings/:id ---
Write-File "frontend/src/app/app.routes.ts" @'
import { Routes } from '@angular/router';

export const routes: Routes = [
  { path: '', redirectTo: 'dashboard', pathMatch: 'full' },
  {
    path: 'dashboard',
    loadComponent: () =>
      import('./features/dashboard/dashboard.page').then(m => m.DashboardPage)
  },
  {
    path: 'airports',
    loadComponent: () =>
      import('./features/airports/airports.page').then(m => m.AirportsPage)
  },
  {
    path: 'flights',
    loadComponent: () =>
      import('./features/flights/flights.page').then(m => m.FlightsPage)
  },
  {
    path: 'bookings',
    loadComponent: () =>
      import('./features/bookings/bookings.page').then(m => m.BookingsPage)
  },
  {
    path: 'bookings/:id',
    loadComponent: () =>
      import('./features/bookings/booking-details.page').then(m => m.BookingDetailsPage)
  },
  { path: '**', redirectTo: 'dashboard' }
];
'@

# ===========================================================================
# Build backend + frontend
# ===========================================================================
Write-Host ""
Write-Host "=== Build backend ==="

dotnet build

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "BACKEND BUILD FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "  + backend ok" -ForegroundColor Green

Write-Host ""
Write-Host "=== Build frontend ==="

Push-Location (Join-Path $root "frontend")
try {
    cmd /c "npm run build 2>&1"
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "FRONTEND BUILD FAILED" -ForegroundColor Red
        Pop-Location
        exit 1
    }
    Write-Host "  + frontend ok" -ForegroundColor Green
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Restart both:" -ForegroundColor Yellow
Write-Host "  Terminal 1: dotnet run --project src/Hosts/FlightsPlatform.Api --launch-profile https"
Write-Host "  Terminal 2: cd frontend; npm start"
Write-Host ""
Write-Host "Try the full flow:" -ForegroundColor Yellow
Write-Host "  1. Airports -> Sync"
Write-Host "  2. Flights  -> Create a flight, copy its ID"
Write-Host "  3. Bookings -> Create a booking"
Write-Host "  4. Booking details -> Add ticket (paste flight ID)"
Write-Host "  5. Confirm -> saga runs"
Write-Host ""
Write-Host "Demo compensation:" -ForegroundColor Yellow
Write-Host "  - Toggle 'Demo: fail next payment' on the Bookings page"
Write-Host "  - Create + fill + confirm a new booking"
Write-Host "  - Saga panel shows compensation steps, status becomes Expired"
Write-Host "  - Toggle back off"
Write-Host ""
Write-Host "Commit:" -ForegroundColor Yellow
Write-Host "  git add ."
Write-Host '  git commit -m "feat(frontend): phase 4.3 - Bookings and saga demo"'
Write-Host "  git push"
Write-Host ""