using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine;
using Microsoft.Extensions.Logging;

namespace Clawix.Bridged;

/// <summary>
/// Daemon-side <see cref="IEngineHost"/>. Wraps <see cref="CodexBackend"/>
/// and exposes the session / message surface to the bridge sessions.
/// Mirrors Swift <c>DaemonEngineHost</c> for <c>listSessions</c>,
/// <c>openSession</c>, <c>sendMessage</c>, streaming, and the daemon-owned
/// bridge surface.
/// </summary>
public sealed partial class DaemonEngineHost : IEngineHost, IAsyncDisposable
{
    private readonly CodexBackend _backend;
    private readonly ILogger<DaemonEngineHost> _logger;
    private readonly object _stateLock = new();
    private BridgeRuntimeState _state = new BridgeRuntimeState.Booting();
    private List<WireSession> _sessions = [];
    private (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) _rateLimits = (null, new Dictionary<string, WireRateLimitSnapshot>());

    public DaemonEngineHost(CodexBackend backend, ILogger<DaemonEngineHost> logger)
    {
        _backend = backend;
        _logger = logger;
        _backend.Notification += OnBackendNotification;
    }

    public BridgeRuntimeState BridgeStateCurrent { get { lock (_stateLock) return _state; } }
    public IReadOnlyList<WireSession> BridgeSessionsCurrent { get { lock (_stateLock) return _sessions; } }
    public (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) BridgeRateLimitsCurrent
    {
        get { lock (_stateLock) return _rateLimits; }
    }

    public event Action<BridgeRuntimeState>? BridgeStateChanged;
    public event Action<IReadOnlyList<WireSession>>? BridgeSessionsChanged;
    public event Action<MessagesEvent>? MessagesChanged;
    public event Action<(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId)>? RateLimitsChanged;

    public async Task BootstrapAsync(CancellationToken ct)
    {
        Transition(new BridgeRuntimeState.Syncing());
        try
        {
            await _backend.CallAsync("initialize", new { client = "clawix-bridge-windows" }, ct);
            await RefreshSessionsAsync(ct);
            Transition(new BridgeRuntimeState.Ready());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "bootstrap failed");
            Transition(new BridgeRuntimeState.Error(ex.Message));
        }
    }

    private void Transition(BridgeRuntimeState next)
    {
        lock (_stateLock) _state = next;
        BridgeStateChanged?.Invoke(next);
    }

    public async Task RefreshSessionsAsync(CancellationToken ct)
    {
        var result = await _backend.CallAsync("thread/list", null, ct);
        var sessions = SessionSnapshotFromBackend(result);
        lock (_stateLock) _sessions = sessions;
        BridgeSessionsChanged?.Invoke(sessions);
    }

    public ValueTask DisposeAsync() => _backend.DisposeAsync();
}
