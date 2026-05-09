using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class BrowserView : UserControl
{
    public BrowserView() { InitializeComponent(); }
    public void Navigate(Uri uri) => Web.Source = uri;
}
