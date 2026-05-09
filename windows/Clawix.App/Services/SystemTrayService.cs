using H.NotifyIcon;
using H.NotifyIcon.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Services;

/// <summary>
/// Notification area icon. Shows the daemon status and a context menu
/// with "Open Clawix", "Pair iPhone", "Quit".
/// </summary>
public sealed class SystemTrayService : IDisposable
{
    private TaskbarIcon? _icon;

    public bool Visible => _icon?.Visibility == Visibility.Visible;

    public event Action? OpenRequested;
    public event Action? PairRequested;
    public event Action? QuitRequested;

    public void Show()
    {
        if (_icon is not null) { _icon.Visibility = Visibility.Visible; return; }
        var menu = new MenuFlyout();
        menu.Items.Add(NewItem("Open Clawix", () => OpenRequested?.Invoke()));
        menu.Items.Add(NewItem("Pair iPhone", () => PairRequested?.Invoke()));
        menu.Items.Add(new MenuFlyoutSeparator());
        menu.Items.Add(NewItem("Quit", () => QuitRequested?.Invoke()));

        _icon = new TaskbarIcon
        {
            ToolTipText = "Clawix",
            ContextFlyout = menu,
        };
        _icon.LeftClickCommand = new ActionCommand(() => OpenRequested?.Invoke());
    }

    public void Hide()
    {
        if (_icon is not null) _icon.Visibility = Visibility.Collapsed;
    }

    public void Dispose()
    {
        _icon?.Dispose();
        _icon = null;
    }

    private static MenuFlyoutItem NewItem(string label, Action action)
    {
        var item = new MenuFlyoutItem { Text = label };
        item.Click += (_, _) => action();
        return item;
    }

    private sealed class ActionCommand : System.Windows.Input.ICommand
    {
        private readonly Action _action;
        public ActionCommand(Action a) { _action = a; }
        public bool CanExecute(object? parameter) => true;
        public void Execute(object? parameter) => _action();
        public event EventHandler? CanExecuteChanged;
    }
}
