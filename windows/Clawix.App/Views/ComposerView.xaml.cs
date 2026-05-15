using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class ComposerView : UserControl
{
    public ComposerView()
    {
        InitializeComponent();
    }

    private async void Send_Click(object sender, RoutedEventArgs e)
    {
        var text = InputBox.Text.Trim();
        if (string.IsNullOrEmpty(text)) return;
        InputBox.Text = string.Empty;
        await App.Services.State.SendMessageAsync(text);
    }

    private void Attach_Click(object sender, RoutedEventArgs e)
    {
        // Phase 4: photo picker -> add WireAttachment to draft.
    }
}
