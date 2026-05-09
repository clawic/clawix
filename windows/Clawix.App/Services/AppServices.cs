using Clawix.Engine.Pairing;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Serilog;
using Serilog.Extensions.Logging;

namespace Clawix.App.Services;

/// <summary>
/// Process-wide service container. Constructed once on app launch and
/// exposed via <c>App.Services</c>. Replaces dependency injection for
/// the simple cases; ViewModels read from here directly.
/// </summary>
public sealed class AppServices
{
    public required ILoggerFactory LoggerFactory { get; init; }
    public required ILogger<AppServices> Logger { get; init; }
    public required Preferences Preferences { get; init; }
    public required CredentialStore Credentials { get; init; }
    public required AppState State { get; init; }
    public required BackgroundBridgeService Bridge { get; init; }
    public required PairingService Pairing { get; init; }
    public required ShellService Shell { get; init; }
    public required ClipboardService Clipboard { get; init; }
    public required GlobalHotkeyService Hotkeys { get; init; }
    public required ScreenService Screens { get; init; }
    public required SystemTrayService Tray { get; init; }
    public required AutoStartService AutoStart { get; init; }
    public required UpdaterService Updater { get; init; }

    public static AppServices Build()
    {
        var logsDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Clawix", "logs");
        Directory.CreateDirectory(logsDir);
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Information()
            .WriteTo.Console()
            .WriteTo.File(Path.Combine(logsDir, "clawix-app-.log"),
                rollingInterval: RollingInterval.Day, retainedFileCountLimit: 7)
            .CreateLogger();
        var loggerFactory = new SerilogLoggerFactory(Log.Logger);

        var prefs = new Preferences();
        var credentials = new CredentialStore();
        var pairingStore = new FilePairingStore();
        var pairing = new PairingService(pairingStore);
        var bridge = new BackgroundBridgeService(loggerFactory.CreateLogger<BackgroundBridgeService>());
        var state = new AppState(bridge, loggerFactory.CreateLogger<AppState>());

        return new AppServices
        {
            LoggerFactory = loggerFactory,
            Logger = loggerFactory.CreateLogger<AppServices>(),
            Preferences = prefs,
            Credentials = credentials,
            Pairing = pairing,
            Bridge = bridge,
            State = state,
            Shell = new ShellService(),
            Clipboard = new ClipboardService(),
            Hotkeys = new GlobalHotkeyService(loggerFactory.CreateLogger<GlobalHotkeyService>()),
            Screens = new ScreenService(),
            Tray = new SystemTrayService(),
            AutoStart = new AutoStartService(loggerFactory.CreateLogger<AutoStartService>()),
            Updater = new UpdaterService(loggerFactory.CreateLogger<UpdaterService>()),
        };
    }
}

internal static class LoggerExtensions
{
    public static void LogError(this ILogger? logger, Exception ex, string message)
    {
        if (logger is null) return;
        Microsoft.Extensions.Logging.LoggerExtensions.LogError(logger, ex, message);
    }
}
