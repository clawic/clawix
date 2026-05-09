using Microsoft.Extensions.Logging;

namespace Clawix.Bridged;

/// <summary>
/// FileSystemWatcher over <c>%USERPROFILE%\.codex\.codex-global-state.json</c>.
/// Mirrors the Swift <c>installPinnedStateWatcher</c> in <c>main.swift</c>.
/// Fires <see cref="Changed"/> with debouncing so a burst of writes
/// from Codex doesn't trigger 10 republish cycles.
/// </summary>
public sealed class PinnedStateWatcher : IDisposable
{
    private readonly FileSystemWatcher _fsw;
    private readonly ILogger<PinnedStateWatcher> _logger;
    private readonly System.Timers.Timer _debounce;

    public event Action? Changed;

    public PinnedStateWatcher(ILogger<PinnedStateWatcher> logger)
    {
        _logger = logger;
        Directory.CreateDirectory(Paths.CodexHome);
        _fsw = new FileSystemWatcher(Paths.CodexHome)
        {
            Filter = ".codex-global-state.json",
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.CreationTime | NotifyFilters.Size,
            EnableRaisingEvents = false,
        };
        _fsw.Changed += (_, __) => _debounce.Stop() ;
        _fsw.Created += (_, __) => _debounce.Stop();
        _fsw.Renamed += (_, __) => _debounce.Stop();

        _debounce = new System.Timers.Timer(250) { AutoReset = false };
        _debounce.Elapsed += (_, __) =>
        {
            try { Changed?.Invoke(); }
            catch (Exception ex) { _logger.LogWarning(ex, "pinned-state subscriber threw"); }
        };

        void Bump(object? _, FileSystemEventArgs __) { _debounce.Stop(); _debounce.Start(); }
        _fsw.Changed += Bump;
        _fsw.Created += Bump;
        _fsw.Renamed += (_, e) => { _debounce.Stop(); _debounce.Start(); };
    }

    public void Start() => _fsw.EnableRaisingEvents = true;

    public void Dispose()
    {
        _fsw.EnableRaisingEvents = false;
        _fsw.Dispose();
        _debounce.Dispose();
    }
}
