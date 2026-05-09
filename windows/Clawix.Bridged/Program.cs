using System.Net;
using Clawix.Bridged;
using Clawix.Core;
using Clawix.Engine;
using Clawix.Engine.Discovery;
using Clawix.Engine.Pairing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Serilog;

Paths.EnsureDirectories();

Log.Logger = new LoggerConfiguration()
    .MinimumLevel.Information()
    .WriteTo.Console()
    .WriteTo.File(Path.Combine(Paths.ClawixLogs, "clawix-bridged-.log"),
        rollingInterval: RollingInterval.Day, retainedFileCountLimit: 7)
    .CreateLogger();

var port = ushort.TryParse(Environment.GetEnvironmentVariable("CLAWIX_BRIDGED_PORT"), out var p) ? p : (ushort)7777;
var bonjourDisabled = Environment.GetEnvironmentVariable("CLAWIX_BRIDGED_DISABLE_BONJOUR") == "1";

using var builder = Host.CreateDefaultBuilder(args)
    .UseSerilog()
    .ConfigureServices(services =>
    {
        services.AddSingleton<IPairingStore>(_ => new FilePairingStore());
        services.AddSingleton(sp => new PairingService(sp.GetRequiredService<IPairingStore>(), port));
        services.AddSingleton<BonjourPublisher>(_ => bonjourDisabled ? null! : new BonjourPublisher());
    })
    .Build();

var loggerFactory = builder.Services.GetRequiredService<ILoggerFactory>();
var pairing = builder.Services.GetRequiredService<PairingService>();
var bonjour = bonjourDisabled ? null : builder.Services.GetService<BonjourPublisher>();

var binary = BackendBinaryResolver.Resolve();
if (binary is null)
{
    Log.Error("Codex CLI not found. Install via 'npm install -g codex' or set CLAWIX_BRIDGED_BACKEND_PATH.");
    return 2;
}
Log.Information("Using Codex binary: {Path}", binary);

await using var backend = new CodexBackend(binary, loggerFactory.CreateLogger<CodexBackend>());
await using var host = new DaemonEngineHost(backend, loggerFactory.CreateLogger<DaemonEngineHost>());

var server = new BridgeServer(host, pairing, loggerFactory.CreateLogger<BridgeServer>(),
    bindAddress: IPAddress.Loopback, port: port, bonjour: bonjour);

var heartbeat = new Heartbeat(() => new HeartbeatState
{
    Version = typeof(Program).Assembly.GetName().Version?.ToString() ?? "0.1.0",
    Port = port,
    BoundAt = DateTimeOffset.UtcNow,
    State = host.BridgeStateCurrent.WireTag,
    ChatCount = host.BridgeChatsCurrent.Count,
    LastError = host.BridgeStateCurrent.ErrorMessage,
}, loggerFactory.CreateLogger<Heartbeat>());

var pinned = new PinnedStateWatcher(loggerFactory.CreateLogger<PinnedStateWatcher>());
pinned.Changed += () => _ = host.RefreshChatsAsync(CancellationToken.None);
pinned.Start();

await heartbeat.StartAsync();
await backend.StartAsync();
await host.BootstrapAsync(CancellationToken.None);
await server.StartAsync();

Log.Information("clawix-bridged ready on 127.0.0.1:{Port}", port);
Log.Information("Pairing short code: {Code}", pairing.ShortCode);

var stopSignal = new TaskCompletionSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; stopSignal.TrySetResult(); };
AppDomain.CurrentDomain.ProcessExit += (_, _) => stopSignal.TrySetResult();
await stopSignal.Task;

Log.Information("clawix-bridged shutting down");
await server.StopAsync();
await heartbeat.DisposeAsync();
pinned.Dispose();
return 0;
