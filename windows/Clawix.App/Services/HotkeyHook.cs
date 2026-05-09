using System.Runtime.InteropServices;

namespace Clawix.App.Services;

/// <summary>
/// Win32 SetWindowSubclass hook that turns WM_HOTKEY messages into
/// callbacks on <see cref="GlobalHotkeyService"/>. Owns the registration
/// lifecycle: each Register hits <c>RegisterHotKey</c>, Dispose
/// unregisters all of them.
/// </summary>
public sealed class HotkeyHook : IDisposable
{
    private const int WM_HOTKEY = 0x0312;

    private readonly IntPtr _hwnd;
    private readonly GlobalHotkeyService _svc;
    private readonly SUBCLASSPROC _proc;
    private readonly IntPtr _procPtr;

    public HotkeyHook(IntPtr hwnd, GlobalHotkeyService svc)
    {
        _hwnd = hwnd;
        _svc = svc;
        _proc = SubclassProc;
        _procPtr = Marshal.GetFunctionPointerForDelegate(_proc);
        SetWindowSubclass(hwnd, _proc, IntPtr.Zero, IntPtr.Zero);
        _svc.HotkeyRegistered += OnRegistered;
        _svc.HotkeyUnregistered += OnUnregistered;
    }

    private void OnRegistered(int id, uint mods, uint vk)
    {
        GlobalHotkeyService.RegisterHotKey(_hwnd, id, mods, vk);
    }

    private void OnUnregistered(int id)
    {
        GlobalHotkeyService.UnregisterHotKey(_hwnd, id);
    }

    private IntPtr SubclassProc(IntPtr hwnd, uint uMsg, IntPtr wParam, IntPtr lParam, IntPtr uIdSubclass, IntPtr dwRefData)
    {
        if (uMsg == WM_HOTKEY)
        {
            _svc.Trigger(wParam.ToInt32());
            return IntPtr.Zero;
        }
        return DefSubclassProc(hwnd, uMsg, wParam, lParam);
    }

    public void Dispose()
    {
        _svc.HotkeyRegistered -= OnRegistered;
        _svc.HotkeyUnregistered -= OnUnregistered;
        RemoveWindowSubclass(_hwnd, _proc, IntPtr.Zero);
        _svc.Dispose();
    }

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    private delegate IntPtr SUBCLASSPROC(IntPtr hwnd, uint uMsg, IntPtr wParam, IntPtr lParam, IntPtr uIdSubclass, IntPtr dwRefData);

    [DllImport("comctl32.dll", CharSet = CharSet.Auto)]
    private static extern bool SetWindowSubclass(IntPtr hWnd, SUBCLASSPROC pfnSubclass, IntPtr uIdSubclass, IntPtr dwRefData);

    [DllImport("comctl32.dll", CharSet = CharSet.Auto)]
    private static extern bool RemoveWindowSubclass(IntPtr hWnd, SUBCLASSPROC pfnSubclass, IntPtr uIdSubclass);

    [DllImport("comctl32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr DefSubclassProc(IntPtr hWnd, uint uMsg, IntPtr wParam, IntPtr lParam);
}
