using Microsoft.UI.Xaml;

namespace Clawix.App.Views;

public sealed partial class CommandPaletteWindow : Window
{
    private static CommandPaletteWindow? _instance;

    public CommandPaletteWindow()
    {
        InitializeComponent();
        Title = "Command palette";
        Closed += (_, _) => _instance = null;
    }

    public static void ShowOrFocus()
    {
        _instance ??= new CommandPaletteWindow();
        _instance.Activate();
    }
}
