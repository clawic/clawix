using Clawix.Core.Models;

namespace Clawix.Core;

/// <summary>
/// Discriminated union of all wire frame bodies. One subtype per frame
/// type. Mirrors the <c>BridgeBody</c> Swift enum frame-for-frame.
/// </summary>
public abstract record BridgeBody
{
    public abstract string TypeTag { get; }

    // ===== v1 outbound (iPhone -> Mac) =====

    public sealed record Auth(string Token, string? DeviceName, ClientKind? ClientKind) : BridgeBody
    {
        public override string TypeTag => "auth";
    }

    public sealed record ListChats : BridgeBody
    {
        public override string TypeTag => "listChats";
    }

    public sealed record OpenChat(string ChatId, int? Limit) : BridgeBody
    {
        public override string TypeTag => "openChat";
    }

    public sealed record LoadOlderMessages(string ChatId, string BeforeMessageId, int Limit) : BridgeBody
    {
        public override string TypeTag => "loadOlderMessages";
    }

    public sealed record SendPrompt(string ChatId, string Text, IReadOnlyList<WireAttachment> Attachments) : BridgeBody
    {
        public override string TypeTag => "sendPrompt";
    }

    public sealed record NewChat(string ChatId, string Text, IReadOnlyList<WireAttachment> Attachments) : BridgeBody
    {
        public override string TypeTag => "newChat";
    }

    public sealed record InterruptTurn(string ChatId) : BridgeBody
    {
        public override string TypeTag => "interruptTurn";
    }

    // ===== v1 inbound (Mac -> iPhone) =====

    public sealed record AuthOk(string? MacName) : BridgeBody
    {
        public override string TypeTag => "authOk";
    }

    public sealed record AuthFailed(string Reason) : BridgeBody
    {
        public override string TypeTag => "authFailed";
    }

    public sealed record VersionMismatch(int ServerVersion) : BridgeBody
    {
        public override string TypeTag => "versionMismatch";
    }

    public sealed record ChatsSnapshot(IReadOnlyList<WireChat> Chats) : BridgeBody
    {
        public override string TypeTag => "chatsSnapshot";
    }

    public sealed record ChatUpdated(WireChat Chat) : BridgeBody
    {
        public override string TypeTag => "chatUpdated";
    }

    public sealed record MessagesSnapshot(string ChatId, IReadOnlyList<WireMessage> Messages, bool? HasMore) : BridgeBody
    {
        public override string TypeTag => "messagesSnapshot";
    }

    public sealed record MessagesPage(string ChatId, IReadOnlyList<WireMessage> Messages, bool HasMore) : BridgeBody
    {
        public override string TypeTag => "messagesPage";
    }

    public sealed record MessageAppended(string ChatId, WireMessage Message) : BridgeBody
    {
        public override string TypeTag => "messageAppended";
    }

    public sealed record MessageStreaming(string ChatId, string MessageId, string Content, string ReasoningText, bool Finished) : BridgeBody
    {
        public override string TypeTag => "messageStreaming";
    }

    public sealed record ErrorEvent(string Code, string Message) : BridgeBody
    {
        public override string TypeTag => "errorEvent";
    }

    // ===== v2 outbound (desktop client -> daemon) =====

    public sealed record EditPrompt(string ChatId, string MessageId, string Text) : BridgeBody
    {
        public override string TypeTag => "editPrompt";
    }

    public sealed record ArchiveChat(string ChatId) : BridgeBody
    {
        public override string TypeTag => "archiveChat";
    }

    public sealed record UnarchiveChat(string ChatId) : BridgeBody
    {
        public override string TypeTag => "unarchiveChat";
    }

    public sealed record PinChat(string ChatId) : BridgeBody
    {
        public override string TypeTag => "pinChat";
    }

    public sealed record UnpinChat(string ChatId) : BridgeBody
    {
        public override string TypeTag => "unpinChat";
    }

    public sealed record RenameChat(string ChatId, string Title) : BridgeBody
    {
        public override string TypeTag => "renameChat";
    }

    public sealed record PairingStart : BridgeBody
    {
        public override string TypeTag => "pairingStart";
    }

    public sealed record ListProjects : BridgeBody
    {
        public override string TypeTag => "listProjects";
    }

    public sealed record ReadFile(string Path) : BridgeBody
    {
        public override string TypeTag => "readFile";
    }

    // ===== v2 inbound (daemon -> desktop client) =====

    public sealed record PairingPayload(string QrJson, string Bearer) : BridgeBody
    {
        public override string TypeTag => "pairingPayload";
    }

    public sealed record ProjectsSnapshot(IReadOnlyList<WireProject> Projects) : BridgeBody
    {
        public override string TypeTag => "projectsSnapshot";
    }

    public sealed record FileSnapshot(string Path, string? Content, bool IsMarkdown, string? Error) : BridgeBody
    {
        public override string TypeTag => "fileSnapshot";
    }

    // ===== v3 voice =====

    public sealed record TranscribeAudio(string RequestId, string AudioBase64, string MimeType, string? Language) : BridgeBody
    {
        public override string TypeTag => "transcribeAudio";
    }

    public sealed record TranscriptionResult(string RequestId, string Text, string? ErrorMessage) : BridgeBody
    {
        public override string TypeTag => "transcriptionResult";
    }

    public sealed record RequestAudio(string AudioId) : BridgeBody
    {
        public override string TypeTag => "requestAudio";
    }

    public sealed record AudioSnapshot(string AudioId, string? AudioBase64, string? MimeType, string? ErrorMessage) : BridgeBody
    {
        public override string TypeTag => "audioSnapshot";
    }

    // ===== v4 generated images =====

    public sealed record RequestGeneratedImage(string Path) : BridgeBody
    {
        public override string TypeTag => "requestGeneratedImage";
    }

    public sealed record GeneratedImageSnapshot(string Path, string? DataBase64, string? MimeType, string? ErrorMessage) : BridgeBody
    {
        public override string TypeTag => "generatedImageSnapshot";
    }

    // ===== bootstrap =====

    public sealed record BridgeState(string State, int ChatCount, string? Message) : BridgeBody
    {
        public override string TypeTag => "bridgeState";
    }

    // ===== v5 rate limits =====

    public sealed record RequestRateLimits : BridgeBody
    {
        public override string TypeTag => "requestRateLimits";
    }

    public sealed record RateLimitsSnapshot(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) : BridgeBody
    {
        public override string TypeTag => "rateLimitsSnapshot";
    }

    public sealed record RateLimitsUpdated(WireRateLimitSnapshot? Snapshot, IReadOnlyDictionary<string, WireRateLimitSnapshot> ByLimitId) : BridgeBody
    {
        public override string TypeTag => "rateLimitsUpdated";
    }
}
