using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class FileViewerPanel : UserControl
{
    public FileViewerPanel()
    {
        InitializeComponent();
    }

    public void ShowFile(string path, string? content, bool isMarkdown, string? error)
    {
        if (error is not null) { ContentText.Text = $"[error] {error}"; return; }
        ContentText.Text = content ?? string.Empty;
    }
}
