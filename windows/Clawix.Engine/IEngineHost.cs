using Clawix.Core;
using Clawix.Core.Models;

namespace Clawix.Engine;

/// <summary>
/// Port of <c>packages/ClawixEngine/EngineHost.swift</c>. Anything that
/// can drive a <see cref="BridgeServer"/> implements this: the daemon
/// (<c>Clawix.Bridged</c>) for production, the GUI (<c>Clawix.App</c>)
/// for in-process mode, and a stub for tests. Keeps the bridge
/// transport agnostic of who owns the chats.
/// </summary>
public interface IEngineHost
{
    // ===== State =====

    BridgeRuntimeState BridgeStateCurrent { get; }

    IReadOnlyList<WireChat> BridgeChatsCurrent { get; }

    event Action<BridgeRuntimeState>? BridgeStateChanged;

    event Action<IReadOnlyList<WireChat>>? BridgeChatsChanged;

    event Action<WireChat>? ChatChanged;

    event Action<MessagesEvent>? MessagesChanged;

    // ===== Chat actions =====

    Task HandleSendPromptAsync(string chatId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct);

    Task HandleNewChatAsync(string chatId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct);

    Task HandleInterruptTurnAsync(string chatId, CancellationToken ct);

    Task<IReadOnlyList<WireMessage>> HandleOpenChatAsync(string chatId, int? limit, CancellationToken ct);

    Task<(IReadOnlyList<WireMessage> Messages, bool HasMore)> HandleLoadOlderMessagesAsync(string chatId, string beforeMessageId, int limit, CancellationToken ct);

    Task HandleEditPromptAsync(string chatId, string messageId, string text, CancellationToken ct);

    Task HandleArchiveAsync(string chatId, bool archived, CancellationToken ct);

    Task HandlePinAsync(string chatId, bool pinned, CancellationToken ct);

    Task HandleRenameAsync(string chatId, string title, CancellationToken ct);

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
    public required string ChatId { get; init; }

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
