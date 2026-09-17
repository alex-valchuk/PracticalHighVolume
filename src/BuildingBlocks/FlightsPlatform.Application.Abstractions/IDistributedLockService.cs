namespace FlightsPlatform.Application.Abstractions;

/// <summary>
/// Distributed lock primitive. Backed by Redis in production,
/// by a no-op implementation in tests that don't care about locking.
/// </summary>
public interface IDistributedLockService
{
    /// <summary>
    /// Attempts to acquire a lock. Returns null if the lock is already held.
    /// Dispose the returned handle to release the lock (owner-safe).
    /// </summary>
    Task<IAsyncDisposable?> TryAcquireAsync(
        string key,
        TimeSpan ttl,
        CancellationToken ct = default);
}