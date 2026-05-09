using System.Runtime.InteropServices;
using Microsoft.Extensions.Logging;

namespace Clawix.App.Services;

/// <summary>
/// Wraps Win32 <c>RegisterHotKey</c> / <c>UnregisterHotKey</c>. Bindings
/// are stored here; <see cref="HotkeyHook"/> owns the WM_HOTKEY
/// dispatch loop bound to <c>MainWindow</c>.
/// </summary>
public sealed class GlobalHotkeyService : IDisposable
{
    private readonly ILogger<GlobalHotkeyService> _logger;
    private readonly Dictionary<int, Action> _bindings = new();
    private int _nextId = 9000;

    public event Action<int, uint, uint>? HotkeyRegistered;
    public event Action<int>? HotkeyUnregistered;

    public GlobalHotkeyService(ILogger<GlobalHotkeyService> logger) { _logger = logger; }

    [Flags]
    public enum Modifiers : uint { None = 0, Alt = 1, Ctrl = 2, Shift = 4, Win = 8 }

    public int Register(Modifiers mods, uint vk, Action handler)
    {
        var id = Interlocked.Increment(ref _nextId);
        _bindings[id] = handler;
        HotkeyRegistered?.Invoke(id, (uint)mods, vk);
        return id;
    }

    public void Trigger(int id)
    {
        if (_bindings.TryGetValue(id, out var h))
        {
            try { h(); } catch (Exception ex) { _logger.LogWarning(ex, "hotkey handler threw"); }
        }
    }

    public void Unregister(int id)
    {
        if (_bindings.Remove(id)) HotkeyUnregistered?.Invoke(id);
    }

    public void Dispose()
    {
        foreach (var id in _bindings.Keys.ToList()) HotkeyUnregistered?.Invoke(id);
        _bindings.Clear();
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint mods, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
