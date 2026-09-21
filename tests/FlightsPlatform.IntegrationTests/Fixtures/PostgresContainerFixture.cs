using Testcontainers.PostgreSql;
using Xunit;

namespace FlightsPlatform.IntegrationTests.Fixtures;

/// <summary>
/// Spins up a real Postgres container for the duration of a test class.
/// One container per test class (xUnit IClassFixture).
/// </summary>
public sealed class PostgresContainerFixture : IAsyncLifetime
{
    private PostgreSqlContainer _container = null!;

    public string ConnectionString { get; private set; } = string.Empty;

    public async Task InitializeAsync()
    {
        _container = new PostgreSqlBuilder()
            .WithImage("postgres:16-alpine")
            .WithDatabase("flights_test")
            .WithUsername("test")
            .WithPassword("test")
            .Build();

        await _container.StartAsync();

        ConnectionString = _container.GetConnectionString();
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}