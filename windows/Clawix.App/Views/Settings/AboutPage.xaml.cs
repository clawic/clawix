using System.Reflection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class AboutPage : Page
{
    public AboutPage()
    {
        InitializeComponent();
        var ver = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";
        VersionText.Text = $"Version {ver}";
    }

    private void OpenLogs_Click(object sender, RoutedEventArgs e)
    {
        var p = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Clawix", "logs");
        App.Services.Shell.Open(p);
    }
}
