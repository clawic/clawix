using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class ConfirmationDialog : ContentDialog
{
    public ConfirmationDialog() { InitializeComponent(); }
    public void Configure(string title, string message)
    {
        Title = title;
        MessageText.Text = message;
    }
}
