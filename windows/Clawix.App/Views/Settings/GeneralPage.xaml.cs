using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class GeneralPage : Page
{
    public GeneralPage()
    {
        InitializeComponent();
        StartAtLogin.IsOn = App.Services.AutoStart.IsEnabled;
        StartAtLogin.Toggled += (_, _) =>
        {
            if (StartAtLogin.IsOn)
            {
                var exe = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "Clawix", "clawix-bridged.exe");
                App.Services.AutoStart.Enable(exe);
            }
            else App.Services.AutoStart.Disable();
        };
    }

    private void RevealConfig_Click(object sender, RoutedEventArgs e)
    {
        var path = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Clawix");
        App.Services.Shell.Open(path);
    }

    private async void Reset_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new ConfirmationDialog { XamlRoot = XamlRoot };
        dlg.Configure("Reset preferences", "All Clawix preferences will be deleted. The vault is NOT affected.");
        var r = await dlg.ShowAsync();
        if (r == ContentDialogResult.Primary)
        {
            // Phase 4.x: clear settings.json and re-launch.
        }
    }
}
