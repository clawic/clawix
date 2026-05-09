using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine;
using Microsoft.Extensions.Logging;

namespace Clawix.Bridged;

/// <summary>
/// Daemon-side <see cref="IEngineHost"/>. Wraps <see cref="CodexBackend"/>
/// and exposes the chat / message surface to the bridge sessions.
/// Mirrors Swift <c>DaemonEngineHost</c>. Phase 2 brings up enough of
/// this to round-trip <c>listChats</c>, <c>openChat</c>, <c>sendPrompt</c>
/// and streaming; the rest of the surface lives behind incremental
/// implementations as the daemon catches up to the macOS counterpart.
/// </summary>
public sealed partial class DaemonEngineHost : IEngineHost, IAsyncDisposable
{
    private readonly CodexBackend _backend;
    private readonly ILogger<DaemonEngineHost> _logger;
    private readonly object _stateLock = new();
    private BridgeRuntimeState _state = new BridgeRuntimeState.Booting();
    private List<WireChat> _chats = [];
    private (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) _rateLimits = (null, new Dictionary<string, WireRateLimitSnapshot>());

    public DaemonEngineHost(CodexBackend backend, ILogger<DaemonEngineHost> logger)
    {
        _backend = backend;
        _logger = logger;
        _backend.Notification += OnBackendNotification;
    }

    public BridgeRuntimeState BridgeStateCurrent { get { lock (_stateLock) return _state; } }
    public IReadOnlyList<WireChat> BridgeChatsCurrent { get { lock (_stateLock) return _chats; } }
    public (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) BridgeRateLimitsCurrent
    {
        get { lock (_stateLock) return _rateLimits; }
    }

    public event Action<BridgeRuntimeState>? BridgeStateChanged;
    public event Action<IReadOnlyList<WireChat>>? BridgeChatsChanged;
    public event Action<WireChat>? ChatChanged;
    public event Action<MessagesEvent>? MessagesChanged;
    public event Action<(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId)>? RateLimitsChanged;

    public async Task BootstrapAsync(CancellationToken ct)
    {
        Transition(new BridgeRuntimeState.Syncing());
        try
        {
            await _backend.CallAsync("initialize", new { client = "clawix-bridged-windows" }, ct);
            await RefreshChatsAsync(ct);
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

    public async Task RefreshChatsAsync(CancellationToken ct)
    {
        var result = await _backend.CallAsync("thread/list", null, ct);
        var chats = ChatSnapshotFromBackend(result);
        lock (_stateLock) _chats = chats;
        BridgeChatsChanged?.Invoke(chats);
    }

    public ValueTask DisposeAsync() => _backend.DisposeAsync();
}
