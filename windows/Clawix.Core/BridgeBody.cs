using Clawix.Core.Models;

namespace Clawix.Core;

/// <summary>
/// Discriminated union of all wire frame bodies. One subtype per frame
/// type. Mirrors the <c>BridgeBody</c> Swift enum frame-for-frame.
/// </summary>
public abstract record BridgeBody
{
    public abstract string TypeTag { get; }

    // ===== Outbound (iPhone -> Mac) =====

    public sealed record Auth(
        string Token,
        string? DeviceName,
        ClientKind ClientKind,
        string ClientId,
        string InstallationId,
        string DeviceId
    ) : BridgeBody
    {
        public override string TypeTag => "auth";
    }

    public sealed record ListSessions : BridgeBody
    {
        public override string TypeTag => "listSessions";
    }

    public sealed record OpenSession(string SessionId, int? Limit) : BridgeBody
    {
        public override string TypeTag => "openSession";
    }

    public sealed record LoadOlderMessages(string SessionId, string BeforeMessageId, int Limit) : BridgeBody
    {
        public override string TypeTag => "loadOlderMessages";
    }

    public sealed record SendMessage(string SessionId, string Text, IReadOnlyList<WireAttachment> Attachments) : BridgeBody
    {
        public override string TypeTag => "sendMessage";
    }

    public sealed record NewSession(string SessionId, string Text, IReadOnlyList<WireAttachment> Attachments) : BridgeBody
    {
        public override string TypeTag => "newSession";
    }

    public sealed record InterruptTurn(string SessionId) : BridgeBody
    {
        public override string TypeTag => "interruptTurn";
    }

    // ===== Inbound (Mac -> iPhone) =====

    public sealed record AuthOk(string? HostDisplayName) : BridgeBody
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

    public sealed record SessionsSnapshot(IReadOnlyList<WireSession> Sessions) : BridgeBody
    {
        public override string TypeTag => "sessionsSnapshot";
    }

    public sealed record SessionUpdated(WireSession Session) : BridgeBody
    {
        public override string TypeTag => "sessionUpdated";
    }

    public sealed record MessagesSnapshot(string SessionId, IReadOnlyList<WireMessage> Messages, bool? HasMore) : BridgeBody
    {
        public override string TypeTag => "messagesSnapshot";
    }

    public sealed record MessagesPage(string SessionId, IReadOnlyList<WireMessage> Messages, bool HasMore) : BridgeBody
    {
        public override string TypeTag => "messagesPage";
    }

    public sealed record MessageAppended(string SessionId, WireMessage Message) : BridgeBody
    {
        public override string TypeTag => "messageAppended";
    }

    public sealed record MessageStreaming(string SessionId, string MessageId, string Content, string ReasoningText, bool Finished) : BridgeBody
    {
        public override string TypeTag => "messageStreaming";
    }

    public sealed record ErrorEvent(string Code, string Message) : BridgeBody
    {
        public override string TypeTag => "errorEvent";
    }

    // ===== desktop-capable outbound (client -> daemon) =====

    public sealed record EditPrompt(string SessionId, string MessageId, string Text) : BridgeBody
    {
        public override string TypeTag => "editPrompt";
    }

    public sealed record ArchiveSession(string SessionId) : BridgeBody
    {
        public override string TypeTag => "archiveSession";
    }

    public sealed record UnarchiveSession(string SessionId) : BridgeBody
    {
        public override string TypeTag => "unarchiveSession";
    }

    public sealed record PinSession(string SessionId) : BridgeBody
    {
        public override string TypeTag => "pinSession";
    }

    public sealed record UnpinSession(string SessionId) : BridgeBody
    {
        public override string TypeTag => "unpinSession";
    }

    public sealed record RenameSession(string SessionId, string Title) : BridgeBody
    {
        public override string TypeTag => "renameSession";
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

    // ===== desktop-capable inbound (daemon -> client) =====

    public sealed record PairingPayload(string QrJson, string Token, string ShortCode) : BridgeBody
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

    // ===== voice =====

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

    // ===== generated images =====

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

    // ===== rate limits =====

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
