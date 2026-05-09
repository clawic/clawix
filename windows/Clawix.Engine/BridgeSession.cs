using System.Net.WebSockets;
using System.Text;
using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine.Pairing;
using Microsoft.Extensions.Logging;

namespace Clawix.Engine;

/// <summary>
/// One paired WebSocket connection. Lifecycle: read auth -> answer ok
/// or fail -> dispatch incoming frames against the host until the
/// socket closes. Mirrors <c>BridgeSession.swift</c>.
/// </summary>
public sealed class BridgeSession
{
    private readonly WebSocket _socket;
    private readonly IEngineHost _host;
    private readonly PairingService _pairing;
    private readonly ILogger _logger;
    private readonly SemaphoreSlim _sendGate = new(1, 1);
    private bool _authenticated;
    private ClientKind _clientKind = ClientKind.Ios;
    private readonly HashSet<string> _subscribedChatIds = new(StringComparer.Ordinal);

    public BridgeSession(WebSocket socket, IEngineHost host, PairingService pairing, ILogger logger)
    {
        _socket = socket;
        _host = host;
        _pairing = pairing;
        _logger = logger;
    }

    public async Task RunAsync(CancellationToken ct)
    {
        try
        {
            while (_socket.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                var frame = await ReadFrameAsync(ct);
                if (frame is null) break;
                if (frame.SchemaVersion != BridgeConstants.SchemaVersion)
                {
                    await SendAsync(new BridgeFrame(new BridgeBody.VersionMismatch(BridgeConstants.SchemaVersion)), ct);
                    break;
                }
                if (!_authenticated)
                {
                    await HandleAuthAsync(frame, ct);
                    continue;
                }
                await DispatchAsync(frame, ct);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "session terminated abnormally");
        }
        finally
        {
            try { await _socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None); }
            catch { }
        }
    }

    private async Task HandleAuthAsync(BridgeFrame frame, CancellationToken ct)
    {
        if (frame.Body is not BridgeBody.Auth auth)
        {
            await _socket.CloseAsync((WebSocketCloseStatus)1008, "auth required", ct);
            return;
        }
        if (!_pairing.AcceptToken(auth.Token))
        {
            await SendAsync(new BridgeFrame(new BridgeBody.AuthFailed("invalid token")), ct);
            await _socket.CloseAsync((WebSocketCloseStatus)1008, "bad token", ct);
            return;
        }
        _authenticated = true;
        _clientKind = auth.ClientKind ?? ClientKind.Ios;
        await SendAsync(new BridgeFrame(new BridgeBody.AuthOk(_pairing.BonjourServiceName)), ct);
        var state = _host.BridgeStateCurrent;
        await SendAsync(new BridgeFrame(new BridgeBody.BridgeState(
            state.WireTag, _host.BridgeChatsCurrent.Count, state.ErrorMessage)), ct);
    }

    private async Task DispatchAsync(BridgeFrame frame, CancellationToken ct)
    {
        switch (frame.Body)
        {
            case BridgeBody.ListChats:
                await SendAsync(new BridgeFrame(new BridgeBody.ChatsSnapshot(_host.BridgeChatsCurrent)), ct);
                break;

            case BridgeBody.OpenChat oc:
                _subscribedChatIds.Add(oc.ChatId);
                var msgs = await _host.HandleOpenChatAsync(oc.ChatId, oc.Limit, ct);
                await SendAsync(new BridgeFrame(new BridgeBody.MessagesSnapshot(oc.ChatId, msgs, oc.Limit is null ? null : msgs.Count >= oc.Limit)), ct);
                break;

            case BridgeBody.LoadOlderMessages lom:
                var page = await _host.HandleLoadOlderMessagesAsync(lom.ChatId, lom.BeforeMessageId, lom.Limit, ct);
                await SendAsync(new BridgeFrame(new BridgeBody.MessagesPage(lom.ChatId, page.Messages, page.HasMore)), ct);
                break;

            case BridgeBody.SendPrompt sp:
                await _host.HandleSendPromptAsync(sp.ChatId, sp.Text, sp.Attachments, ct);
                break;

            case BridgeBody.NewChat nc:
                await _host.HandleNewChatAsync(nc.ChatId, nc.Text, nc.Attachments, ct);
                break;

            case BridgeBody.InterruptTurn it:
                await _host.HandleInterruptTurnAsync(it.ChatId, ct);
                break;

            case BridgeBody.EditPrompt ep when _clientKind == ClientKind.Desktop:
                await _host.HandleEditPromptAsync(ep.ChatId, ep.MessageId, ep.Text, ct);
                break;

            case BridgeBody.ArchiveChat ac when _clientKind == ClientKind.Desktop:
                await _host.HandleArchiveAsync(ac.ChatId, true, ct); break;
            case BridgeBody.UnarchiveChat uac when _clientKind == ClientKind.Desktop:
                await _host.HandleArchiveAsync(uac.ChatId, false, ct); break;
            case BridgeBody.PinChat pc when _clientKind == ClientKind.Desktop:
                await _host.HandlePinAsync(pc.ChatId, true, ct); break;
            case BridgeBody.UnpinChat upc when _clientKind == ClientKind.Desktop:
                await _host.HandlePinAsync(upc.ChatId, false, ct); break;

            case BridgeBody.RenameChat rc when _clientKind == ClientKind.Desktop:
                await _host.HandleRenameAsync(rc.ChatId, rc.Title, ct); break;

            case BridgeBody.PairingStart when _clientKind == ClientKind.Desktop:
                await SendAsync(new BridgeFrame(new BridgeBody.PairingPayload(_pairing.QrPayload(), _pairing.Bearer)), ct);
                break;

            case BridgeBody.ListProjects when _clientKind == ClientKind.Desktop:
                var projects = await _host.HandleListProjectsAsync(ct);
                await SendAsync(new BridgeFrame(new BridgeBody.ProjectsSnapshot(projects)), ct);
                break;

            case BridgeBody.ReadFile rf when _clientKind == ClientKind.Desktop:
                var file = await _host.HandleReadFileAsync(rf.Path, ct);
                await SendAsync(new BridgeFrame(new BridgeBody.FileSnapshot(rf.Path, file.Content, file.IsMarkdown, file.Error)), ct);
                break;

            case BridgeBody.TranscribeAudio ta:
                var t = await _host.HandleTranscribeAudioAsync(ta.AudioBase64, ta.MimeType, ta.Language, ct);
                await SendAsync(new BridgeFrame(new BridgeBody.TranscriptionResult(ta.RequestId, t.Text ?? string.Empty, t.Error)), ct);
                break;

            case BridgeBody.RequestAudio ra:
                var a = await _host.HandleRequestAudioAsync(ra.AudioId, ct);
                await SendAsync(new BridgeFrame(new BridgeBody.AudioSnapshot(ra.AudioId, a.AudioBase64, a.MimeType, a.Error)), ct);
                break;

            case BridgeBody.RequestGeneratedImage rgi:
                var g = await _host.HandleRequestGeneratedImageAsync(rgi.Path, ct);
                await SendAsync(new BridgeFrame(new BridgeBody.GeneratedImageSnapshot(rgi.Path, g.DataBase64, g.MimeType, g.Error)), ct);
                break;

            case BridgeBody.RequestRateLimits when _clientKind == ClientKind.Desktop:
                var rl = _host.BridgeRateLimitsCurrent;
                await SendAsync(new BridgeFrame(new BridgeBody.RateLimitsSnapshot(rl.Snapshot, rl.ByLimitId)), ct);
                break;

            default:
                _logger.LogDebug("ignoring frame {Type} for clientKind {Kind}", frame.Body.TypeTag, _clientKind);
                break;
        }
    }

    private async Task<BridgeFrame?> ReadFrameAsync(CancellationToken ct)
    {
        var buffer = new byte[16 * 1024];
        using var ms = new MemoryStream();
        WebSocketReceiveResult? result;
        do
        {
            result = await _socket.ReceiveAsync(new ArraySegment<byte>(buffer), ct);
            if (result.MessageType == WebSocketMessageType.Close) return null;
            ms.Write(buffer, 0, result.Count);
        } while (!result.EndOfMessage);

        if (result.MessageType != WebSocketMessageType.Text) return null;
        var json = Encoding.UTF8.GetString(ms.ToArray());
        return BridgeCoder.Decode(json);
    }

    public async Task SendAsync(BridgeFrame frame, CancellationToken ct)
    {
        var bytes = BridgeCoder.EncodeBytes(frame);
        await _sendGate.WaitAsync(ct);
        try
        {
            await _socket.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, endOfMessage: true, ct);
        }
        finally
        {
            _sendGate.Release();
        }
    }
}
