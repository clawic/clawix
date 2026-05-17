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
                writer.WritePropertyName("clientKind");
                JsonSerializer.Serialize(writer, a.ClientKind, options);
                writer.WriteString("clientId", a.ClientId);
                writer.WriteString("installationId", a.InstallationId);
                writer.WriteString("deviceId", a.DeviceId);
                break;
            case BridgeBody.ListSessions:
                break;
            case BridgeBody.OpenSession o:
                writer.WriteString("sessionId", o.SessionId);
                if (o.Limit is not null) writer.WriteNumber("limit", o.Limit.Value);
                break;
            case BridgeBody.LoadOlderMessages l:
                writer.WriteString("sessionId", l.SessionId);
                writer.WriteString("beforeMessageId", l.BeforeMessageId);
                writer.WriteNumber("limit", l.Limit);
                break;
            case BridgeBody.SendMessage s:
                writer.WriteString("sessionId", s.SessionId);
                writer.WriteString("text", s.Text);
                if (s.Attachments.Count > 0)
                {
                    writer.WritePropertyName("attachments");
                    JsonSerializer.Serialize(writer, s.Attachments, options);
                }
                break;
            case BridgeBody.NewSession n:
                writer.WriteString("sessionId", n.SessionId);
                writer.WriteString("text", n.Text);
                if (n.Attachments.Count > 0)
                {
                    writer.WritePropertyName("attachments");
                    JsonSerializer.Serialize(writer, n.Attachments, options);
                }
                break;
            case BridgeBody.InterruptTurn it:
                writer.WriteString("sessionId", it.SessionId);
                break;
            case BridgeBody.AuthOk ao:
                if (ao.HostDisplayName is not null) writer.WriteString("hostDisplayName", ao.HostDisplayName);
                break;
            case BridgeBody.AuthFailed af:
                writer.WriteString("reason", af.Reason);
                break;
            case BridgeBody.VersionMismatch vm:
                writer.WriteNumber("serverVersion", vm.ServerVersion);
                break;
            case BridgeBody.SessionsSnapshot cs:
                writer.WritePropertyName("sessions");
                JsonSerializer.Serialize(writer, cs.Sessions, options);
                break;
            case BridgeBody.SessionUpdated cu:
                writer.WritePropertyName("session");
                JsonSerializer.Serialize(writer, cu.Session, options);
                break;
            case BridgeBody.MessagesSnapshot ms:
                writer.WriteString("sessionId", ms.SessionId);
                writer.WritePropertyName("messages");
                JsonSerializer.Serialize(writer, ms.Messages, options);
                if (ms.HasMore is not null) writer.WriteBoolean("hasMore", ms.HasMore.Value);
                break;
            case BridgeBody.MessagesPage mp:
                writer.WriteString("sessionId", mp.SessionId);
                writer.WritePropertyName("messages");
                JsonSerializer.Serialize(writer, mp.Messages, options);
                writer.WriteBoolean("hasMore", mp.HasMore);
                break;
            case BridgeBody.MessageAppended ma:
                writer.WriteString("sessionId", ma.SessionId);
                writer.WritePropertyName("message");
                JsonSerializer.Serialize(writer, ma.Message, options);
                break;
            case BridgeBody.MessageStreaming mst:
                writer.WriteString("sessionId", mst.SessionId);
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
                writer.WriteString("sessionId", ep.SessionId);
                writer.WriteString("messageId", ep.MessageId);
                writer.WriteString("text", ep.Text);
                break;
            case BridgeBody.ArchiveSession ac:
                writer.WriteString("sessionId", ac.SessionId);
                break;
            case BridgeBody.UnarchiveSession uac:
                writer.WriteString("sessionId", uac.SessionId);
                break;
            case BridgeBody.PinSession pc:
                writer.WriteString("sessionId", pc.SessionId);
                break;
            case BridgeBody.UnpinSession upc:
                writer.WriteString("sessionId", upc.SessionId);
                break;
            case BridgeBody.RenameSession rc:
                writer.WriteString("sessionId", rc.SessionId);
                writer.WriteString("title", rc.Title);
                break;
            case BridgeBody.PairingStart:
            case BridgeBody.ListProjects:
                break;
            case BridgeBody.PairingPayload pp:
                writer.WriteString("qrJson", pp.QrJson);
                writer.WriteString("token", pp.Token);
                writer.WriteString("shortCode", pp.ShortCode);
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
            case BridgeBody.AudioRegister ar:
                writer.WriteString("requestId", ar.RequestId);
                writer.WritePropertyName("request");
                JsonSerializer.Serialize(writer, ar.Request, options);
                break;
            case BridgeBody.AudioAttachTranscript aat:
                writer.WriteString("requestId", aat.RequestId);
                writer.WriteString("audioId", aat.AudioId);
                writer.WritePropertyName("transcript");
                JsonSerializer.Serialize(writer, aat.Transcript, options);
                break;
            case BridgeBody.AudioGet ag:
                writer.WriteString("requestId", ag.RequestId);
                writer.WriteString("audioId", ag.AudioId);
                writer.WriteString("appId", ag.AppId);
                break;
            case BridgeBody.AudioGetBytes agb:
                writer.WriteString("requestId", agb.RequestId);
                writer.WriteString("audioId", agb.AudioId);
                writer.WriteString("appId", agb.AppId);
                break;
            case BridgeBody.AudioList al:
                writer.WriteString("requestId", al.RequestId);
                writer.WritePropertyName("filter");
                JsonSerializer.Serialize(writer, al.Filter, options);
                break;
            case BridgeBody.AudioDelete ad:
                writer.WriteString("requestId", ad.RequestId);
                writer.WriteString("audioId", ad.AudioId);
                writer.WriteString("appId", ad.AppId);
                break;
            case BridgeBody.AudioRegisterResult arr:
                writer.WriteString("requestId", arr.RequestId);
                if (arr.Asset is not null)
                {
                    writer.WritePropertyName("asset");
                    JsonSerializer.Serialize(writer, arr.Asset, options);
                }
                if (arr.ErrorMessage is not null) writer.WriteString("errorMessage", arr.ErrorMessage);
                break;
            case BridgeBody.AudioAttachTranscriptResult aatr:
                writer.WriteString("requestId", aatr.RequestId);
                if (aatr.Transcript is not null)
                {
                    writer.WritePropertyName("transcript");
                    JsonSerializer.Serialize(writer, aatr.Transcript, options);
                }
                if (aatr.ErrorMessage is not null) writer.WriteString("errorMessage", aatr.ErrorMessage);
                break;
            case BridgeBody.AudioGetResult agr:
                writer.WriteString("requestId", agr.RequestId);
                if (agr.Asset is not null)
                {
                    writer.WritePropertyName("asset");
                    JsonSerializer.Serialize(writer, agr.Asset, options);
                }
                if (agr.ErrorMessage is not null) writer.WriteString("errorMessage", agr.ErrorMessage);
                break;
            case BridgeBody.AudioBytesResult abr:
                writer.WriteString("requestId", abr.RequestId);
                if (abr.AudioBase64 is not null) writer.WriteString("audioBase64", abr.AudioBase64);
                if (abr.MimeType is not null) writer.WriteString("mimeType", abr.MimeType);
                if (abr.DurationMs is not null) writer.WriteNumber("durationMs", abr.DurationMs.Value);
                if (abr.ErrorMessage is not null) writer.WriteString("errorMessage", abr.ErrorMessage);
                break;
            case BridgeBody.AudioListResult alr:
                writer.WriteString("requestId", alr.RequestId);
                if (alr.List is not null)
                {
                    writer.WritePropertyName("list");
                    JsonSerializer.Serialize(writer, alr.List, options);
                }
                if (alr.ErrorMessage is not null) writer.WriteString("errorMessage", alr.ErrorMessage);
                break;
            case BridgeBody.AudioDeleteResult adr:
                writer.WriteString("requestId", adr.RequestId);
                writer.WriteBoolean("deleted", adr.Deleted);
                if (adr.ErrorMessage is not null) writer.WriteString("errorMessage", adr.ErrorMessage);
                break;
            default:
                throw new JsonException($"unknown body subtype: {body.GetType()}");
        }
    }
}
