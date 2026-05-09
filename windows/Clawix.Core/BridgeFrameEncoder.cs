using System.Text.Json;

namespace Clawix.Core;

internal sealed partial class BridgeFrameConverter
{
    public override void Write(Utf8JsonWriter writer, BridgeFrame value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        writer.WriteNumber("schemaVersion", value.SchemaVersion);
        writer.WriteString("type", value.Body.TypeTag);
        EncodeBody(writer, value.Body, options);
        writer.WriteEndObject();
    }

    private static void EncodeBody(Utf8JsonWriter writer, BridgeBody body, JsonSerializerOptions options)
    {
        switch (body)
        {
            case BridgeBody.Auth a:
                writer.WriteString("token", a.Token);
                if (a.DeviceName is not null) writer.WriteString("deviceName", a.DeviceName);
                if (a.ClientKind is not null)
                {
                    writer.WritePropertyName("clientKind");
                    JsonSerializer.Serialize(writer, a.ClientKind.Value, options);
                }
                break;
            case BridgeBody.ListChats:
                break;
            case BridgeBody.OpenChat o:
                writer.WriteString("chatId", o.ChatId);
                if (o.Limit is not null) writer.WriteNumber("limit", o.Limit.Value);
                break;
            case BridgeBody.LoadOlderMessages l:
                writer.WriteString("chatId", l.ChatId);
                writer.WriteString("beforeMessageId", l.BeforeMessageId);
                writer.WriteNumber("limit", l.Limit);
                break;
            case BridgeBody.SendPrompt s:
                writer.WriteString("chatId", s.ChatId);
                writer.WriteString("text", s.Text);
                if (s.Attachments.Count > 0)
                {
                    writer.WritePropertyName("attachments");
                    JsonSerializer.Serialize(writer, s.Attachments, options);
                }
                break;
            case BridgeBody.NewChat n:
                writer.WriteString("chatId", n.ChatId);
                writer.WriteString("text", n.Text);
                if (n.Attachments.Count > 0)
                {
                    writer.WritePropertyName("attachments");
                    JsonSerializer.Serialize(writer, n.Attachments, options);
                }
                break;
            case BridgeBody.InterruptTurn it:
                writer.WriteString("chatId", it.ChatId);
                break;
            case BridgeBody.AuthOk ao:
                if (ao.MacName is not null) writer.WriteString("macName", ao.MacName);
                break;
            case BridgeBody.AuthFailed af:
                writer.WriteString("reason", af.Reason);
                break;
            case BridgeBody.VersionMismatch vm:
                writer.WriteNumber("serverVersion", vm.ServerVersion);
                break;
            case BridgeBody.ChatsSnapshot cs:
                writer.WritePropertyName("chats");
                JsonSerializer.Serialize(writer, cs.Chats, options);
                break;
            case BridgeBody.ChatUpdated cu:
                writer.WritePropertyName("chat");
                JsonSerializer.Serialize(writer, cu.Chat, options);
                break;
            case BridgeBody.MessagesSnapshot ms:
                writer.WriteString("chatId", ms.ChatId);
                writer.WritePropertyName("messages");
                JsonSerializer.Serialize(writer, ms.Messages, options);
                if (ms.HasMore is not null) writer.WriteBoolean("hasMore", ms.HasMore.Value);
                break;
            case BridgeBody.MessagesPage mp:
                writer.WriteString("chatId", mp.ChatId);
                writer.WritePropertyName("messages");
                JsonSerializer.Serialize(writer, mp.Messages, options);
                writer.WriteBoolean("hasMore", mp.HasMore);
                break;
            case BridgeBody.MessageAppended ma:
                writer.WriteString("chatId", ma.ChatId);
                writer.WritePropertyName("message");
                JsonSerializer.Serialize(writer, ma.Message, options);
                break;
            case BridgeBody.MessageStreaming mst:
                writer.WriteString("chatId", mst.ChatId);
                writer.WriteString("messageId", mst.MessageId);
                writer.WriteString("content", mst.Content);
                writer.WriteString("reasoningText", mst.ReasoningText);
                writer.WriteBoolean("finished", mst.Finished);
                break;
            case BridgeBody.ErrorEvent ee:
                writer.WriteString("code", ee.Code);
                writer.WriteString("message", ee.Message);
                break;
            case BridgeBody.EditPrompt ep:
                writer.WriteString("chatId", ep.ChatId);
                writer.WriteString("messageId", ep.MessageId);
                writer.WriteString("text", ep.Text);
                break;
            case BridgeBody.ArchiveChat ac:
                writer.WriteString("chatId", ac.ChatId);
                break;
            case BridgeBody.UnarchiveChat uac:
                writer.WriteString("chatId", uac.ChatId);
                break;
            case BridgeBody.PinChat pc:
                writer.WriteString("chatId", pc.ChatId);
                break;
            case BridgeBody.UnpinChat upc:
                writer.WriteString("chatId", upc.ChatId);
                break;
            case BridgeBody.RenameChat rc:
                writer.WriteString("chatId", rc.ChatId);
                writer.WriteString("title", rc.Title);
                break;
            case BridgeBody.PairingStart:
            case BridgeBody.ListProjects:
                break;
            case BridgeBody.PairingPayload pp:
                writer.WriteString("qrJson", pp.QrJson);
                writer.WriteString("bearer", pp.Bearer);
                break;
            case BridgeBody.ProjectsSnapshot ps:
                writer.WritePropertyName("projects");
                JsonSerializer.Serialize(writer, ps.Projects, options);
                break;
            case BridgeBody.ReadFile rf:
                writer.WriteString("path", rf.Path);
                break;
            case BridgeBody.FileSnapshot fs:
                writer.WriteString("path", fs.Path);
                if (fs.Content is not null) writer.WriteString("content", fs.Content);
                writer.WriteBoolean("isMarkdown", fs.IsMarkdown);
                if (fs.Error is not null) writer.WriteString("error", fs.Error);
                break;
            case BridgeBody.TranscribeAudio ta:
                writer.WriteString("requestId", ta.RequestId);
                writer.WriteString("audioBase64", ta.AudioBase64);
                writer.WriteString("mimeType", ta.MimeType);
                if (ta.Language is not null) writer.WriteString("language", ta.Language);
                break;
            case BridgeBody.TranscriptionResult tr:
                writer.WriteString("requestId", tr.RequestId);
                writer.WriteString("text", tr.Text);
                if (tr.ErrorMessage is not null) writer.WriteString("errorMessage", tr.ErrorMessage);
                break;
            case BridgeBody.RequestAudio ra:
                writer.WriteString("audioId", ra.AudioId);
                break;
            case BridgeBody.AudioSnapshot asnap:
                writer.WriteString("audioId", asnap.AudioId);
                if (asnap.AudioBase64 is not null) writer.WriteString("audioBase64", asnap.AudioBase64);
                if (asnap.MimeType is not null) writer.WriteString("mimeType", asnap.MimeType);
                if (asnap.ErrorMessage is not null) writer.WriteString("errorMessage", asnap.ErrorMessage);
                break;
            case BridgeBody.RequestGeneratedImage rgi:
                writer.WriteString("path", rgi.Path);
                break;
            case BridgeBody.GeneratedImageSnapshot gis:
                writer.WriteString("path", gis.Path);
                if (gis.DataBase64 is not null) writer.WriteString("dataBase64", gis.DataBase64);
                if (gis.MimeType is not null) writer.WriteString("mimeType", gis.MimeType);
                if (gis.ErrorMessage is not null) writer.WriteString("errorMessage", gis.ErrorMessage);
                break;
            case BridgeBody.BridgeState bs:
                writer.WriteString("state", bs.State);
                writer.WriteNumber("chatCount", bs.ChatCount);
                if (bs.Message is not null) writer.WriteString("message", bs.Message);
                break;
            case BridgeBody.RequestRateLimits:
                break;
            case BridgeBody.RateLimitsSnapshot rls:
                if (rls.Snapshot is not null)
                {
                    writer.WritePropertyName("rateLimits");
                    JsonSerializer.Serialize(writer, rls.Snapshot, options);
                }
                writer.WritePropertyName("rateLimitsByLimitId");
                JsonSerializer.Serialize(writer, rls.ByLimitId, options);
                break;
            case BridgeBody.RateLimitsUpdated rlu:
                if (rlu.Snapshot is not null)
                {
                    writer.WritePropertyName("rateLimits");
                    JsonSerializer.Serialize(writer, rlu.Snapshot, options);
                }
                writer.WritePropertyName("rateLimitsByLimitId");
                JsonSerializer.Serialize(writer, rlu.ByLimitId, options);
                break;
            default:
                throw new JsonException($"unknown body subtype: {body.GetType()}");
        }
    }
}
