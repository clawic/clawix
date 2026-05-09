using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class MarkdownDocumentView : UserControl
{
    public MarkdownDocumentView() { InitializeComponent(); }
    public void RenderMarkdown(string md)
    {
        // Phase 4: Markdig parsing -> RichTextBlock paragraphs.
        Body.Blocks.Clear();
        var p = new Microsoft.UI.Xaml.Documents.Paragraph();
        p.Inlines.Add(new Microsoft.UI.Xaml.Documents.Run { Text = md });
        Body.Blocks.Add(p);
    }
}
