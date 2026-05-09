using System.Reflection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class UpdatesPage : Page
{
    public UpdatesPage()
    {
        InitializeComponent();
        var ver = Assembly.GetExecutingAssembly().GetName().Version?.ToString() ?? "0.0.0";
        VersionText.Text = $"Clawix {ver}";
    }
    private async void Check_Click(object sender, RoutedEventArgs e)
    {
        await App.Services.Updater.CheckAsync();
    }
}
