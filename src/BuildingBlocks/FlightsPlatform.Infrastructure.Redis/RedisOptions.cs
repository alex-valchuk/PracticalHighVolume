namespace FlightsPlatform.Infrastructure.Redis;

public sealed class RedisOptions
{
    public const string SectionName = "Redis";

    public string ConnectionString { get; set; } = "localhost:6379";
    public string InstanceName { get; set; } = "flights-platform:";
    public TimeSpan DefaultTtl { get; set; } = TimeSpan.FromMinutes(15);
}