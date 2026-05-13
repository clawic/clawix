using System.Text.Json;
using System.Text.Json.Serialization;
using Clawix.Core.Models;

namespace Clawix.Core;

/// <summary>
/// Custom converter for <see cref="BridgeFrame"/>. Flat JSON shape on the
/// wire (no <c>payload</c> envelope). Field name casing matches Swift
/// Codable defaults (camelCase).
/// </summary>
internal sealed partial class BridgeFrameConverter : JsonConverter<BridgeFrame>
{
    public override BridgeFrame Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var root = doc.RootElement;

        if (!root.TryGetProperty("schemaVersion", out var schemaProp))
            throw new JsonException("frame missing 'schemaVersion'");
        var schema = schemaProp.GetInt32();

        if (!root.TryGetProperty("type", out var typeProp))
            throw new JsonException("frame missing 'type'");
        var type = typeProp.GetString() ?? throw new JsonException("frame 'type' is null");

        var body = DecodeBody(root, type, options);
        return new BridgeFrame(body, schema);
    }

    private static BridgeBody DecodeBody(JsonElement root, string type, JsonSerializerOptions options)
    {
        T? Get<T>(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null
            ? JsonSerializer.Deserialize<T>(p.GetRawText(), options)
            : default;

        T GetReq<T>(string name) => root.TryGetProperty(name, out var p)
            ? JsonSerializer.Deserialize<T>(p.GetRawText(), options) ?? throw new JsonException($"missing required field '{name}'")
            : throw new JsonException($"missing required field '{name}'");

        string GetStr(string name) => root.GetProperty(name).GetString() ?? throw new JsonException($"missing required string '{name}'");
        int GetInt(string name) => root.GetProperty(name).GetInt32();
        bool GetBool(string name) => root.GetProperty(name).GetBoolean();

        string? GetStrOpt(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null ? p.GetString() : null;
        int? GetIntOpt(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null ? p.GetInt32() : null;
        bool? GetBoolOpt(string name) => root.TryGetProperty(name, out var p) && p.ValueKind != JsonValueKind.Null ? p.GetBoolean() : null;

        IReadOnlyList<WireAttachment> GetAttachments() => root.TryGetProperty("attachments", out var p) && p.ValueKind == JsonValueKind.Array
            ? JsonSerializer.Deserialize<List<WireAttachment>>(p.GetRawText(), options) ?? []
            : [];

        return type switch
        {
            "auth" => new BridgeBody.Auth(
                GetStr("token"),
                GetStrOpt("deviceName"),
                Get<ClientKind?>("clientKind")),

            "listSessions" => new BridgeBody.ListSessions(),
            "openSession" => new BridgeBody.OpenSession(GetStr("sessionId"), GetIntOpt("limit")),

            "loadOlderMessages" => new BridgeBody.LoadOlderMessages(
                GetStr("sessionId"),
                GetStr("beforeMessageId"),
                GetInt("limit")),

            "sendPrompt" => new BridgeBody.SendPrompt(GetStr("sessionId"), GetStr("text"), GetAttachments()),
            "newSession" => new BridgeBody.NewSession(GetStr("sessionId"), GetStr("text"), GetAttachments()),
            "interruptTurn" => new BridgeBody.InterruptTurn(GetStr("sessionId")),
            "authOk" => new BridgeBody.AuthOk(GetStrOpt("macName")),
            "authFailed" => new BridgeBody.AuthFailed(GetStr("reason")),
            "versionMismatch" => new BridgeBody.VersionMismatch(GetInt("serverVersion")),
            "sessionsSnapshot" => new BridgeBody.SessionsSnapshot(GetReq<List<WireChat>>("sessions")),
            "chatUpdated" => new BridgeBody.ChatUpdated(GetReq<WireChat>("chat")),

            "messagesSnapshot" => new BridgeBody.MessagesSnapshot(
                GetStr("sessionId"),
                GetReq<List<WireMessage>>("messages"),
                GetBoolOpt("hasMore")),

            "messagesPage" => new BridgeBody.MessagesPage(
                GetStr("sessionId"),
                GetReq<List<WireMessage>>("messages"),
                GetBool("hasMore")),

            "messageAppended" => new BridgeBody.MessageAppended(GetStr("sessionId"), GetReq<WireMessage>("message")),

            "messageStreaming" => new BridgeBody.MessageStreaming(
                GetStr("sessionId"),
                GetStr("messageId"),
                GetStr("content"),
                GetStr("reasoningText"),
                GetBool("finished")),

            "errorEvent" => new BridgeBody.ErrorEvent(GetStr("code"), GetStr("message")),
            "editPrompt" => new BridgeBody.EditPrompt(GetStr("sessionId"), GetStr("messageId"), GetStr("text")),
            "archiveSession" => new BridgeBody.ArchiveSession(GetStr("sessionId")),
            "unarchiveSession" => new BridgeBody.UnarchiveSession(GetStr("sessionId")),
            "pinSession" => new BridgeBody.PinSession(GetStr("sessionId")),
            "unpinSession" => new BridgeBody.UnpinSession(GetStr("sessionId")),
            "renameSession" => new BridgeBody.RenameSession(GetStr("sessionId"), GetStr("title")),
            "pairingStart" => new BridgeBody.PairingStart(),
            "listProjects" => new BridgeBody.ListProjects(),
            "pairingPayload" => new BridgeBody.PairingPayload(GetStr("qrJson"), GetStr("bearer")),
            "projectsSnapshot" => new BridgeBody.ProjectsSnapshot(GetReq<List<WireProject>>("projects")),
            "readFile" => new BridgeBody.ReadFile(GetStr("path")),

            "fileSnapshot" => new BridgeBody.FileSnapshot(
                GetStr("path"),
                GetStrOpt("content"),
                GetBoolOpt("isMarkdown") ?? false,
                GetStrOpt("error")),

            "transcribeAudio" => new BridgeBody.TranscribeAudio(
                GetStr("requestId"),
                GetStr("audioBase64"),
                GetStr("mimeType"),
                GetStrOpt("language")),

            "transcriptionResult" => new BridgeBody.TranscriptionResult(
                GetStr("requestId"),
                GetStr("text"),
                GetStrOpt("errorMessage")),

            "requestAudio" => new BridgeBody.RequestAudio(GetStr("audioId")),

            "audioSnapshot" => new BridgeBody.AudioSnapshot(
                GetStr("audioId"),
                GetStrOpt("audioBase64"),
                GetStrOpt("mimeType"),
                GetStrOpt("errorMessage")),

            "requestGeneratedImage" => new BridgeBody.RequestGeneratedImage(GetStr("path")),

            "generatedImageSnapshot" => new BridgeBody.GeneratedImageSnapshot(
                GetStr("path"),
                GetStrOpt("dataBase64"),
                GetStrOpt("mimeType"),
                GetStrOpt("errorMessage")),

            "bridgeState" => new BridgeBody.BridgeState(
                GetStr("state"),
                GetInt("chatCount"),
                GetStrOpt("message")),

            "requestRateLimits" => new BridgeBody.RequestRateLimits(),

            "rateLimitsSnapshot" => new BridgeBody.RateLimitsSnapshot(
                Get<WireRateLimitSnapshot>("rateLimits"),
                Get<Dictionary<string, WireRateLimitSnapshot>>("rateLimitsByLimitId") ?? new Dictionary<string, WireRateLimitSnapshot>()),

            "rateLimitsUpdated" => new BridgeBody.RateLimitsUpdated(
                Get<WireRateLimitSnapshot>("rateLimits"),
                Get<Dictionary<string, WireRateLimitSnapshot>>("rateLimitsByLimitId") ?? new Dictionary<string, WireRateLimitSnapshot>()),

            _ => throw BridgeDecodingException.UnknownType(type),
        };
    }
}
