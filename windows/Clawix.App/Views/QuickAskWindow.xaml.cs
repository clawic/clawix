using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;

namespace Clawix.App.Views;

public sealed partial class QuickAskWindow : Window
{
    public QuickAskWindow()
    {
        InitializeComponent();
        Title = "Quick Ask";
        Closed += (_, _) => _instance = null;
    }

    private static QuickAskWindow? _instance;

    public static void ShowOrFocus()
    {
        _instance ??= new QuickAskWindow();
        _instance.Activate();
    }
}
