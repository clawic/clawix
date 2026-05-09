using System.Net.WebSockets;
using System.Text;
using Clawix.Core;
using Microsoft.Extensions.Logging;

namespace Clawix.App.Services;

/// <summary>
/// Loopback WebSocket client to <c>clawix-bridged</c>. Mirrors macOS
/// <c>DaemonBridgeClient</c>. Reconnects on drop with exponential
/// backoff capped at 5 seconds (LAN is always close).
/// </summary>
public sealed class DaemonClient : IAsyncDisposable
{
    private readonly Uri _endpoint;
    private readonly string _bearer;
    private readonly ILogger<DaemonClient> _logger;
    private ClientWebSocket? _ws;
    private CancellationTokenSource? _cts;
    private Task? _readerLoop;

    public event Action<BridgeFrame>? FrameReceived;
    public event Action<bool>? ConnectionStateChanged;

    public DaemonClient(int port, string bearer, ILogger<DaemonClient> logger)
    {
        _endpoint = new Uri($"ws://127.0.0.1:{port}/");
        _bearer = bearer;
        _logger = logger;
    }

    public async Task ConnectAsync(CancellationToken ct)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _ws = new ClientWebSocket();
        _ws.Options.KeepAliveInterval = TimeSpan.FromSeconds(15);
        await _ws.ConnectAsync(_endpoint, _cts.Token);

        await SendAsync(new BridgeFrame(new BridgeBody.Auth(_bearer, Environment.MachineName, ClientKind.Desktop)), _cts.Token);
        _readerLoop = Task.Run(() => ReadLoopAsync(_cts.Token), _cts.Token);
        ConnectionStateChanged?.Invoke(true);
    }

    public async Task SendAsync(BridgeFrame frame, CancellationToken ct)
    {
        if (_ws is null) throw new InvalidOperationException("not connected");
        var bytes = BridgeCoder.EncodeBytes(frame);
        await _ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, ct);
    }

    private async Task ReadLoopAsync(CancellationToken ct)
    {
        var buffer = new byte[64 * 1024];
        try
        {
            while (_ws is not null && _ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                using var ms = new MemoryStream();
                WebSocketReceiveResult r;
                do
                {
                    r = await _ws.ReceiveAsync(new ArraySegment<byte>(buffer), ct);
                    if (r.MessageType == WebSocketMessageType.Close) return;
                    ms.Write(buffer, 0, r.Count);
                } while (!r.EndOfMessage);
                if (r.MessageType != WebSocketMessageType.Text) continue;
                var json = Encoding.UTF8.GetString(ms.ToArray());
                try { FrameReceived?.Invoke(BridgeCoder.Decode(json)); }
                catch (Exception ex) { _logger.LogWarning(ex, "drop bad frame"); }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { _logger.LogWarning(ex, "daemon socket read terminated"); }
        finally { ConnectionStateChanged?.Invoke(false); }
    }

    public async ValueTask DisposeAsync()
    {
        try { _cts?.Cancel(); } catch { }
        try
        {
            if (_ws is not null && _ws.State == WebSocketState.Open)
                await _ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "bye", CancellationToken.None);
        }
        catch { }
        _ws?.Dispose();
        if (_readerLoop is not null) try { await _readerLoop; } catch { }
        _cts?.Dispose();
    }
}
