using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class AddSecretSheet : ContentDialog
{
    public AddSecretSheet() { InitializeComponent(); }
    public string Label => LabelBox.Text;
    public string Value => ValueBox.Password;
}
