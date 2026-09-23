using System.Diagnostics;

namespace FlightsPlatform.Observability;

public static class ActivitySources
{
    public const string Name = "FlightsPlatform";
    public static readonly ActivitySource Instance = new(Name);

    public static class Commands
    {
        public const string Name = "FlightsPlatform.Commands";
        public static readonly ActivitySource Instance = new(Name);
    }

    public static class Saga
    {
        public const string Name = "FlightsPlatform.Saga";
        public static readonly ActivitySource Instance = new(Name);
    }

    public static class Cache
    {
        public const string Name = "FlightsPlatform.Cache";
        public static readonly ActivitySource Instance = new(Name);
    }

    public static IEnumerable<string> All()
    {
        yield return Name;
        yield return Commands.Name;
        yield return Saga.Name;
        yield return Cache.Name;
    }
}