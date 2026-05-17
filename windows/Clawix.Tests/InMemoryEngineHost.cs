using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine;

namespace Clawix.Tests;

/// <summary>
/// Trivial <see cref="IEngineHost"/> for tests that don't want to spawn
/// a real Codex subprocess. Lets us exercise BridgeServer + BridgeSession
/// against a known set of sessions and a hand-pushed message stream.
/// </summary>
public sealed class InMemoryEngineHost : IEngineHost
{
    private BridgeRuntimeState _state = new BridgeRuntimeState.Ready();
    private List<WireSession> _sessions = new();

    public BridgeRuntimeState BridgeStateCurrent => _state;
    public IReadOnlyList<WireSession> BridgeSessionsCurrent => _sessions;
    public (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) BridgeRateLimitsCurrent
        => (null, new Dictionary<string, WireRateLimitSnapshot>());

    public event Action<BridgeRuntimeState>? BridgeStateChanged { add { } remove { } }
    public event Action<IReadOnlyList<WireSession>>? BridgeSessionsChanged;
    public event Action<MessagesEvent>? MessagesChanged { add { } remove { } }
    public event Action<(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId)>? RateLimitsChanged { add { } remove { } }

    public void SetSessions(IEnumerable<WireSession> sessions)
    {
        _sessions = sessions.ToList();
        BridgeSessionsChanged?.Invoke(_sessions);
    }

    public Task HandleSendMessageAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct) => Task.CompletedTask;
    public Task HandleNewSessionAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct) => Task.CompletedTask;
    public Task HandleInterruptTurnAsync(string sessionId, CancellationToken ct) => Task.CompletedTask;
    public Task<IReadOnlyList<WireMessage>> HandleOpenSessionAsync(string sessionId, int? limit, CancellationToken ct)
        => Task.FromResult<IReadOnlyList<WireMessage>>(Array.Empty<WireMessage>());
    public Task<(IReadOnlyList<WireMessage> Messages, bool HasMore)> HandleLoadOlderMessagesAsync(string sessionId, string beforeMessageId, int limit, CancellationToken ct)
        => Task.FromResult<(IReadOnlyList<WireMessage>, bool)>((Array.Empty<WireMessage>(), false));
    public Task HandleEditPromptAsync(string sessionId, string messageId, string text, CancellationToken ct) => Task.CompletedTask;
    public Task HandleArchiveAsync(string sessionId, bool archived, CancellationToken ct) => Task.CompletedTask;
    public Task HandlePinAsync(string sessionId, bool pinned, CancellationToken ct) => Task.CompletedTask;
    public Task HandleRenameAsync(string sessionId, string title, CancellationToken ct) => Task.CompletedTask;
    public Task<IReadOnlyList<WireProject>> HandleListProjectsAsync(CancellationToken ct)
        => Task.FromResult<IReadOnlyList<WireProject>>(Array.Empty<WireProject>());
    public Task<(string? Content, bool IsMarkdown, string? Error)> HandleReadFileAsync(string path, CancellationToken ct)
        => Task.FromResult<(string?, bool, string?)>((null, false, "stub"));
    public Task<(string? Text, string? Error)> HandleTranscribeAudioAsync(string audioBase64, string mimeType, string? language, CancellationToken ct)
        => Task.FromResult<(string?, string?)>(("hello", null));
    public Task<(string? AudioBase64, string? MimeType, string? Error)> HandleRequestAudioAsync(string audioId, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>((null, null, "stub"));
    public Task<(string? DataBase64, string? MimeType, string? Error)> HandleRequestGeneratedImageAsync(string path, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>((null, null, "stub"));
}
