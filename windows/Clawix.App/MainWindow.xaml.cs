using Clawix.App.Services;
using Clawix.App.Views;
using Microsoft.UI.Composition.SystemBackdrops;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;
using WinRT.Interop;

namespace Clawix.App;

public sealed partial class MainWindow : Window
{
    private IntPtr _hwnd;
    private HotkeyHook? _hotkeyHook;

    public MainWindow()
    {
        InitializeComponent();
        TrySetMicaBackdrop();
        ExtendsContentIntoTitleBar = true;
        Activated += OnActivated;
        Closed += (_, _) => _hotkeyHook?.Dispose();
        DispatcherQueue.TryEnqueue(BootShellAsync);
    }

    private void OnActivated(object sender, WindowActivatedEventArgs e)
    {
        if (_hwnd != IntPtr.Zero) return;
        _hwnd = WindowNative.GetWindowHandle(this);
        _hotkeyHook = new HotkeyHook(_hwnd, App.Services.Hotkeys);
        App.Services.Hotkeys.Register(GlobalHotkeyService.Modifiers.Ctrl, 0x4B /* K */, OpenQuickAsk);
        App.Services.Hotkeys.Register(GlobalHotkeyService.Modifiers.Ctrl | GlobalHotkeyService.Modifiers.Shift, 0x50 /* P */, OpenCommandPalette);
        WireSystemTray();
    }

    private async void BootShellAsync()
    {
        await Task.Delay(150);
        var bridge = App.Services.Bridge.Probe();
        if (!bridge.Alive)
        {
            Splash.Visibility = Visibility.Collapsed;
            LoginGate.Visibility = Visibility.Visible;
            return;
        }
        Splash.Visibility = Visibility.Collapsed;
        Shell.Visibility = Visibility.Visible;
    }

    private void WireSystemTray()
    {
        var tray = App.Services.Tray;
        tray.OpenRequested += () => DispatcherQueue.TryEnqueue(() => Activate());
        tray.PairRequested += () => DispatcherQueue.TryEnqueue(() =>
        {
            // Phase 4: open Settings -> Pairing.
        });
        tray.QuitRequested += () => DispatcherQueue.TryEnqueue(Close);
        tray.Show();
    }

    private void OpenQuickAsk() => DispatcherQueue.TryEnqueue(QuickAskWindow.ShowOrFocus);
    private void OpenCommandPalette() => DispatcherQueue.TryEnqueue(CommandPaletteWindow.ShowOrFocus);

    private void TrySetMicaBackdrop()
    {
        try
        {
            if (MicaController.IsSupported())
                SystemBackdrop = new MicaBackdrop { Kind = MicaKind.Base };
            else
                SystemBackdrop = new DesktopAcrylicBackdrop();
        }
        catch { /* fallback to default chrome */ }
    }
}
