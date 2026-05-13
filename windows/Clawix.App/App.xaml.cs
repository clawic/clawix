using Clawix.App.Services;
using Microsoft.Extensions.Logging;
using Microsoft.UI.Xaml;

namespace Clawix.App;

public partial class App : Application
{
    public static AppServices Services { get; private set; } = null!;
    public static Window? MainAppWindow { get; private set; }

    public App()
    {
        InitializeComponent();
        UnhandledException += (_, e) =>
        {
            Services?.Logger.LogError(e.Exception, "unhandled exception");
        };
    }

    protected override async void OnLaunched(LaunchActivatedEventArgs args)
    {
        Services = AppServices.Build();
        await EnsureDaemonRunningAsync();

        var probe = Services.Bridge.Probe();
        if (probe.Alive)
        {
            try { await Services.State.EnsureConnectedAsync(Services.Pairing.Bearer, default); }
            catch (Exception ex) { Services.Logger.LogError(ex, "initial bridge connect failed"); }
        }

        MainAppWindow = new MainWindow();
        MainAppWindow.Activate();
    }

    private static Task EnsureDaemonRunningAsync()
    {
        try
        {
            var probe = Services.Bridge.Probe();
            if (probe.Alive) return Task.CompletedTask;

            var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var bridged = Path.Combine(local, "Clawix", "clawix-bridge.exe");
            if (!File.Exists(bridged))
            {
                Services.Logger.LogWarning("clawix-bridge.exe not installed; user must run `clawix install` first.");
                return Task.CompletedTask;
            }
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = bridged,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = System.Diagnostics.ProcessWindowStyle.Hidden,
            });
        }
        catch (Exception ex) { Services.Logger.LogWarning(ex, "could not auto-start daemon"); }
        return Task.CompletedTask;
    }
}
