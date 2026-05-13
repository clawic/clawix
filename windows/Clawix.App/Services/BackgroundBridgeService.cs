using System.Diagnostics;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Clawix.App.Services;

/// <summary>
/// Detects whether <c>clawix-bridge.exe</c> is alive by reading the
/// heartbeat file at <c>%USERPROFILE%\.clawix\state\bridge-status.json</c>.
/// Mirrors macOS <c>BackgroundBridgeService</c>.
/// </summary>
public sealed class BackgroundBridgeService
{
    private readonly string _heartbeatPath;
    private readonly ILogger<BackgroundBridgeService> _logger;

    public BackgroundBridgeService(ILogger<BackgroundBridgeService> logger)
    {
        _logger = logger;
        var profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        _heartbeatPath = Path.Combine(profile, ".clawix", "state", "bridge-status.json");
    }

    public sealed record Status(bool Alive, int? Port, int? Pid, string? State, int? ChatCount);

    public Status Probe()
    {
        try
        {
            if (!File.Exists(_heartbeatPath)) return new Status(false, null, null, null, null);
            var fi = new FileInfo(_heartbeatPath);
            if (DateTimeOffset.UtcNow - fi.LastWriteTimeUtc > TimeSpan.FromSeconds(60))
                return new Status(false, null, null, null, null);

            using var doc = JsonDocument.Parse(File.ReadAllText(_heartbeatPath));
            var root = doc.RootElement;
            int? pid = root.TryGetProperty("pid", out var pidEl) ? pidEl.GetInt32() : null;
            int? port = root.TryGetProperty("port", out var portEl) ? portEl.GetInt32() : null;
            string? state = root.TryGetProperty("state", out var stEl) ? stEl.GetString() : null;
            int? chats = root.TryGetProperty("chatCount", out var ccEl) ? ccEl.GetInt32() : null;

            if (pid is null || !ProcessAlive(pid.Value)) return new Status(false, null, null, null, null);
            return new Status(true, port, pid, state, chats);
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "heartbeat probe failed");
            return new Status(false, null, null, null, null);
        }
    }

    private static bool ProcessAlive(int pid)
    {
        try { return Process.GetProcessById(pid).Id == pid; }
        catch { return false; }
    }
}
