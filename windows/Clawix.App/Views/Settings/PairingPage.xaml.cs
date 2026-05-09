using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views.Settings;

public sealed partial class PairingPage : Page
{
    public PairingPage() { InitializeComponent(); }

    private void Rotate_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Pairing.RotateBearer();
        App.Services.Pairing.RotateShortCode();
    }

    private void CopyQr_Click(object sender, RoutedEventArgs e)
    {
        App.Services.Clipboard.SetText(App.Services.Pairing.QrPayload());
    }
}
