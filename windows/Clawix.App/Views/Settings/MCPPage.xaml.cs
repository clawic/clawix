using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class MCPPage : Page
{
    public MCPPage() { InitializeComponent(); }
    private void OpenConfig_Click(object sender, RoutedEventArgs e)
    {
        var p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".codex", "config.toml");
        App.Services.Shell.Open(p);
    }
}
