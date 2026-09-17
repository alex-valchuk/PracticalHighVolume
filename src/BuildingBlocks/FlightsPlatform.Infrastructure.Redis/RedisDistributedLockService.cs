using FlightsPlatform.Application.Abstractions;
using Microsoft.Extensions.Logging;
using StackExchange.Redis;

namespace FlightsPlatform.Infrastructure.Redis;

internal sealed class RedisDistributedLockService : IDistributedLockService
{
    /// <summary>
    /// Atomically releases the lock only if we still own it.
    /// Prevents deleting a lock that has already expired and been
    /// re-acquired by someone else.
    /// </summary>
    private const string ReleaseScript = @"
        if redis.call('GET', KEYS[1]) == ARGV[1] then
            return redis.call('DEL', KEYS[1])
        else
            return 0
        end";

    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<RedisDistributedLockService> _logger;

    public RedisDistributedLockService(
        IConnectionMultiplexer redis,
        ILogger<RedisDistributedLockService> logger)
    {
        _redis = redis;
        _logger = logger;
    }

    public async Task<IAsyncDisposable?> TryAcquireAsync(
        string key,
        TimeSpan ttl,
        CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(key))
            throw new ArgumentException("Lock key is required.", nameof(key));

        if (ttl <= TimeSpan.Zero)
            throw new ArgumentException("Lock TTL must be positive.", nameof(ttl));

        var token = Guid.NewGuid().ToString("N");
        var db = _redis.GetDatabase();

        try
        {
            var acquired = await db.StringSetAsync(
                key,
                token,
                ttl,
                When.NotExists);

            if (!acquired)
            {
                _logger.LogDebug("Lock NOT acquired for key {Key}", key);
                return null;
            }

            _logger.LogDebug("Lock acquired for key {Key} with ttl {Ttl}", key, ttl);
            return new LockHandle(db, key, token, _logger);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Redis lock acquisition failed for key {Key}", key);
            return null;
        }
    }

    private sealed class LockHandle : IAsyncDisposable
    {
        private readonly IDatabase _db;
        private readonly string _key;
        private readonly string _token;
        private readonly ILogger _logger;
        private bool _disposed;

        public LockHandle(IDatabase db, string key, string token, ILogger logger)
        {
            _db = db;
            _key = key;
            _token = token;
            _logger = logger;
        }

        public async ValueTask DisposeAsync()
        {
            if (_disposed) return;
            _disposed = true;

            try
            {
                var result = await _db.ScriptEvaluateAsync(
                    ReleaseScript,
                    new RedisKey[] { _key },
                    new RedisValue[] { _token });

                if ((long)result == 1)
                {
                    _logger.LogDebug("Lock released for key {Key}", _key);
                }
                else
                {
                    _logger.LogWarning(
                        "Lock for key {Key} was not released (already expired or re-acquired)",
                        _key);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to release lock for key {Key}", _key);
            }
        }
    }
}