using Microsoft.Extensions.Logging;
using Microsoft.Win32;

namespace Clawix.App.Services;

/// <summary>
/// SMAppService equivalent. Registers <c>clawix-bridged.exe</c> to
/// auto-start at login under
/// <c>HKCU\Software\Microsoft\Windows\CurrentVersion\Run</c>.
/// Per-user, no admin required, no Windows Service.
/// </summary>
public sealed class AutoStartService
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "ClawixBridge";

    private readonly ILogger<AutoStartService> _logger;

    public AutoStartService(ILogger<AutoStartService> logger) { _logger = logger; }

    public bool IsEnabled
    {
        get
        {
            using var k = Registry.CurrentUser.OpenSubKey(RunKey);
            return k?.GetValue(ValueName) is string;
        }
    }

    public void Enable(string daemonExePath)
    {
        using var k = Registry.CurrentUser.CreateSubKey(RunKey, writable: true)
            ?? throw new InvalidOperationException("could not open Run key");
        k.SetValue(ValueName, $"\"{daemonExePath}\"", RegistryValueKind.String);
        _logger.LogInformation("auto-start enabled: {Path}", daemonExePath);
    }

    public void Disable()
    {
        using var k = Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
        if (k is null) return;
        try { k.DeleteValue(ValueName, throwOnMissingValue: false); } catch { }
    }
}
