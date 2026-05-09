using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class ImagePreviewOverlay : UserControl
{
    public ImagePreviewOverlay() { InitializeComponent(); }
    private void Close_Click(object sender, RoutedEventArgs e) => Visibility = Visibility.Collapsed;
}
