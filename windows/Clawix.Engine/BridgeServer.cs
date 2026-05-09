using System.Net;
using System.Net.WebSockets;
using Clawix.Core;
using Clawix.Engine.Discovery;
using Clawix.Engine.Pairing;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Clawix.Engine;

/// <summary>
/// Bridge WebSocket server. Loopback only by default (127.0.0.1:7777),
/// matches the Swift NWListener server in
/// <c>packages/ClawixEngine/BridgeServer.swift</c>. Each accepted
/// connection becomes a <see cref="BridgeSession"/>.
/// </summary>
public sealed class BridgeServer : IAsyncDisposable
{
    private readonly IEngineHost _host;
    private readonly PairingService _pairing;
    private readonly BonjourPublisher? _bonjour;
    private readonly ILogger<BridgeServer> _logger;
    private readonly IPAddress _bindAddress;
    private readonly ushort _port;
    private IHost? _aspHost;

    public BridgeServer(
        IEngineHost host,
        PairingService pairing,
        ILogger<BridgeServer> logger,
        IPAddress? bindAddress = null,
        ushort? port = null,
        BonjourPublisher? bonjour = null)
    {
        _host = host;
        _pairing = pairing;
        _logger = logger;
        _bindAddress = bindAddress ?? IPAddress.Loopback;
        _port = port ?? pairing.Port;
        _bonjour = bonjour;
    }

    public async Task StartAsync(CancellationToken ct = default)
    {
        var builder = Host.CreateDefaultBuilder()
            .ConfigureWebHostDefaults(web =>
            {
                web.ConfigureKestrel(opts => opts.Listen(_bindAddress, _port));
                web.Configure(app =>
                {
                    app.UseWebSockets(new WebSocketOptions
                    {
                        KeepAliveInterval = TimeSpan.FromSeconds(15),
                    });

                    app.Use(async (context, next) =>
                    {
                        if (!context.WebSockets.IsWebSocketRequest)
                        {
                            context.Response.StatusCode = (int)HttpStatusCode.UpgradeRequired;
                            return;
                        }
                        var ws = await context.WebSockets.AcceptWebSocketAsync();
                        var session = new BridgeSession(ws, _host, _pairing, _logger);
                        await session.RunAsync(context.RequestAborted);
                    });
                });
            });

        _aspHost = builder.Build();
        await _aspHost.StartAsync(ct);
        _logger.LogInformation("BridgeServer listening on {Addr}:{Port}", _bindAddress, _port);

        if (_bonjour is not null)
            await _bonjour.PublishAsync(_pairing.BonjourServiceName, _port, ct);
    }

    public async Task StopAsync(CancellationToken ct = default)
    {
        if (_bonjour is not null) await _bonjour.UnpublishAsync(ct);
        if (_aspHost is not null) await _aspHost.StopAsync(ct);
    }

    public async ValueTask DisposeAsync()
    {
        if (_aspHost is not null) _aspHost.Dispose();
        if (_bonjour is not null) await _bonjour.DisposeAsync();
        _aspHost = null;
    }
}
