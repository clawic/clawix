using Clawix.Core;
using Clawix.Core.Models;

namespace Clawix.Engine;

/// <summary>
/// Port of <c>packages/ClawixEngine/EngineHost.swift</c>. Anything that
/// can drive a <see cref="BridgeServer"/> implements this: the daemon
/// (<c>Clawix.Bridged</c>) for production, the GUI (<c>Clawix.App</c>)
/// for in-process mode, and a stub for tests. Keeps the bridge
/// transport agnostic of who owns the sessions.
/// </summary>
public interface IEngineHost
{
    // ===== State =====

    BridgeRuntimeState BridgeStateCurrent { get; }

    IReadOnlyList<WireSession> BridgeSessionsCurrent { get; }

    event Action<BridgeRuntimeState>? BridgeStateChanged;

    event Action<IReadOnlyList<WireSession>>? BridgeSessionsChanged;

    event Action<WireSession>? ChatChanged;

    event Action<MessagesEvent>? MessagesChanged;

    // ===== Session actions =====

    Task HandleSendMessageAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct);

    Task HandleNewSessionAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct);

    Task HandleInterruptTurnAsync(string sessionId, CancellationToken ct);

    Task<IReadOnlyList<WireMessage>> HandleOpenSessionAsync(string sessionId, int? limit, CancellationToken ct);

    Task<(IReadOnlyList<WireMessage> Messages, bool HasMore)> HandleLoadOlderMessagesAsync(string sessionId, string beforeMessageId, int limit, CancellationToken ct);

    Task HandleEditPromptAsync(string sessionId, string messageId, string text, CancellationToken ct);

    Task HandleArchiveAsync(string sessionId, bool archived, CancellationToken ct);

    Task HandlePinAsync(string sessionId, bool pinned, CancellationToken ct);

    Task HandleRenameAsync(string sessionId, string title, CancellationToken ct);

    // ===== Projects + files =====

    Task<IReadOnlyList<WireProject>> HandleListProjectsAsync(CancellationToken ct);

    Task<(string? Content, bool IsMarkdown, string? Error)> HandleReadFileAsync(string path, CancellationToken ct);

    // ===== Audio + images =====

    Task<(string? Text, string? Error)> HandleTranscribeAudioAsync(string audioBase64, string mimeType, string? language, CancellationToken ct);

    Task<(string? AudioBase64, string? MimeType, string? Error)> HandleRequestAudioAsync(string audioId, CancellationToken ct);

    Task<(string? DataBase64, string? MimeType, string? Error)> HandleRequestGeneratedImageAsync(string path, CancellationToken ct);

    // ===== Rate limits =====

    (WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) BridgeRateLimitsCurrent { get; }

    event Action<(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId)>? RateLimitsChanged;
}

/// <summary>
/// Pushed by <see cref="IEngineHost.MessagesChanged"/>. The session
/// translates these into the right <c>messageAppended</c> /
/// <c>messageStreaming</c> / <c>messagesSnapshot</c> wire frames.
/// </summary>
public abstract record MessagesEvent
{
    public required string SessionId { get; init; }

    public sealed record Snapshot : MessagesEvent
    {
        public required IReadOnlyList<WireMessage> Messages { get; init; }
        public bool? HasMore { get; init; }
    }

    public sealed record Appended : MessagesEvent
    {
        public required WireMessage Message { get; init; }
    }

    public sealed record Streaming : MessagesEvent
    {
        public required string MessageId { get; init; }
        public required string Content { get; init; }
        public required string ReasoningText { get; init; }
        public required bool Finished { get; init; }
    }
}
