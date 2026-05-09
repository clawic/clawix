using System.Diagnostics;

namespace Clawix.App.Services;

/// <summary>
/// NSWorkspace equivalent. Opens files, URLs, and folders in the
/// default app via <c>ShellExecute</c> semantics.
/// </summary>
public sealed class ShellService
{
    public void Open(string pathOrUrl)
    {
        var psi = new ProcessStartInfo(pathOrUrl) { UseShellExecute = true };
        Process.Start(psi);
    }

    public void RevealInExplorer(string path)
    {
        if (!File.Exists(path) && !Directory.Exists(path)) return;
        Process.Start("explorer.exe", $"/select,\"{path}\"");
    }
}
