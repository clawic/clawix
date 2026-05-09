using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.Extensions.Logging;

namespace Clawix.Bridged;

/// <summary>
/// Writes <c>%USERPROFILE%\.clawix\state\bridge-status.json</c> every
/// 2 seconds so the GUI and the npm CLI can detect the daemon is alive.
/// Schema is bit-identical to the macOS heartbeat.
/// </summary>
public sealed class Heartbeat : IAsyncDisposable
{
    private readonly Func<HeartbeatState> _stateProvider;
    private readonly ILogger<Heartbeat> _logger;
    private CancellationTokenSource? _cts;
    private Task? _loop;

    public Heartbeat(Func<HeartbeatState> stateProvider, ILogger<Heartbeat> logger)
    {
        _stateProvider = stateProvider;
        _logger = logger;
    }

    public Task StartAsync(CancellationToken ct = default)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _loop = Task.Run(() => RunAsync(_cts.Token), _cts.Token);
        return Task.CompletedTask;
    }

    private async Task RunAsync(CancellationToken ct)
    {
        Paths.EnsureDirectories();
        while (!ct.IsCancellationRequested)
        {
            try
            {
                Write(_stateProvider());
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "heartbeat write failed");
            }
            try { await Task.Delay(TimeSpan.FromSeconds(2), ct); }
            catch (OperationCanceledException) { break; }
        }
    }

    private static void Write(HeartbeatState state)
    {
        var json = JsonSerializer.Serialize(state, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = true,
        });
        var path = Paths.BridgeStatusPath;
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, json);
        File.Move(tmp, path, overwrite: true);
    }

    public async ValueTask DisposeAsync()
    {
        _cts?.Cancel();
        if (_loop is not null) try { await _loop; } catch { }
        _cts?.Dispose();
    }
}

public sealed record HeartbeatState
{
    public required string Version { get; init; }
    public int Pid { get; init; } = Environment.ProcessId;
    public required int Port { get; init; }
    public DateTimeOffset? BoundAt { get; init; }
    public DateTimeOffset LastHeartbeatAt { get; init; } = DateTimeOffset.UtcNow;
    public int PeerCount { get; init; }
    public required string State { get; init; }
    public int ChatCount { get; init; }
    public string? LastError { get; init; }
}
