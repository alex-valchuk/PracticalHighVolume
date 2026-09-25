// Aspire AppHost for local development.
//
// Run from the repository root:
//   dotnet run --project src/Hosts/FlightPlatform.AppHost

using Aspire.Hosting;

var builder = DistributedApplication.CreateBuilder(args);

// --- Credentials passed as parameters -----------------------------------

var postgresUser = builder.AddParameter("postgres-user", "flights");
var postgresPassword = builder.AddParameter("postgres-password", "flights_dev_password", secret: true);
var redisPassword = builder.AddParameter("redis-password", "flights_dev_password", secret: true);
var rabbitUser = builder.AddParameter("rabbit-user", "guest");
var rabbitPassword = builder.AddParameter("rabbit-password", "guest", secret: true);

// --- Infrastructure containers ------------------------------------------

var postgres = builder.AddPostgres("postgres", userName: postgresUser, password: postgresPassword)
    .WithDataVolume("flights-aspire-pgdata");

var redis = builder.AddRedis("redis", password: redisPassword)
    .WithDataVolume("flights-aspire-redisdata");

var rabbitmq = builder.AddRabbitMQ("rabbitmq", userName: rabbitUser, password: rabbitPassword)
    .WithDataVolume("flights-aspire-rabbitmqdata");

// --- Endpoint references (resolved at runtime by Aspire) ----------------

var pgHost = postgres.Resource.PrimaryEndpoint.Property(EndpointProperty.Host);
var pgPort = postgres.Resource.PrimaryEndpoint.Property(EndpointProperty.Port);

var rmqHost = rabbitmq.Resource.PrimaryEndpoint.Property(EndpointProperty.Host);
var rmqPort = rabbitmq.Resource.PrimaryEndpoint.Property(EndpointProperty.Port);

var redisHost = redis.Resource.PrimaryEndpoint.Property(EndpointProperty.Host);
var redisPort = redis.Resource.PrimaryEndpoint.Property(EndpointProperty.Port);

// Connection string reference for Postgres (Npgsql format)
var pgConnStr = ReferenceExpression.Create(
    $"Host={pgHost};Port={pgPort};Database=flights_demo;Username=flights;Password=flights_dev_password");

// Connection string reference for Redis (StackExchange.Redis format)
var redisConnStr = ReferenceExpression.Create(
    $"{redisHost}:{redisPort},password=flights_dev_password");

// --- Application services -----------------------------------------------
//
// AddProject(string name, string projectPath) is used instead of the
// typed AddProject<Projects.X>() because the latter relies on a source
// generator that can be flaky in some environments. The path-based
// overload does the same thing without generation.

var api = builder.AddProject("flights-api", "../FlightsPlatform.Api/FlightsPlatform.Api.csproj")
    .WithEnvironment("ConnectionStrings__FlightCatalog", pgConnStr)
    .WithEnvironment("ConnectionStrings__Booking", pgConnStr)
    .WithEnvironment("ConnectionStrings__BookingsSource", pgConnStr)
    .WithEnvironment("Redis__ConnectionString", redisConnStr)
    .WithEnvironment("RabbitMq__Host", rmqHost)
    .WithEnvironment("RabbitMq__Port", rmqPort)
    .WithEnvironment("RabbitMq__VirtualHost", "/")
    .WithEnvironment("RabbitMq__Username", "guest")
    .WithEnvironment("RabbitMq__Password", "guest")
    .WithEnvironment("AirportSync__Enabled", "false")
    .WithEnvironment("AirportSync__SyncOnStartup", "false")
    .WithExternalHttpEndpoints();

var notificationWorker = builder.AddProject("notification-worker", "../../Workers/FlightsPlatform.NotificationWorker/FlightsPlatform.NotificationWorker.csproj")
    .WithEnvironment("ConnectionStrings__Notification", pgConnStr)
    .WithEnvironment("RabbitMq__Host", rmqHost)
    .WithEnvironment("RabbitMq__Port", rmqPort)
    .WithEnvironment("RabbitMq__VirtualHost", "/")
    .WithEnvironment("RabbitMq__Username", "guest")
    .WithEnvironment("RabbitMq__Password", "guest");

var analyticsWorker = builder.AddProject("analytics-worker", "../../Workers/FlightsPlatform.AnalyticsWorker/FlightsPlatform.AnalyticsWorker.csproj")
    .WithEnvironment("ConnectionStrings__Analytics", pgConnStr)
    .WithEnvironment("RabbitMq__Host", rmqHost)
    .WithEnvironment("RabbitMq__Port", rmqPort)
    .WithEnvironment("RabbitMq__VirtualHost", "/")
    .WithEnvironment("RabbitMq__Username", "guest")
    .WithEnvironment("RabbitMq__Password", "guest");

builder.Build().Run();