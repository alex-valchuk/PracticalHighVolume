using System.Diagnostics;
using OpenTelemetry;

namespace FlightsPlatform.Observability;

public sealed class SanitizeProcessor : BaseProcessor<Activity>
{
    private static readonly HashSet<string> SensitiveKeys = new(StringComparer.OrdinalIgnoreCase)
    {
        "password", "pwd", "token", "secret", "authorization",
        "cookie", "api-key", "apikey", "connectionstring", "connection_string"
    };

    public override void OnEnd(Activity activity)
    {
        var tags = activity.TagObjects.ToList();
        foreach (var tag in tags)
        {
            if (SensitiveKeys.Contains(tag.Key))
            {
                activity.SetTag(tag.Key, "[REDACTED]");
            }
        }
    }
}