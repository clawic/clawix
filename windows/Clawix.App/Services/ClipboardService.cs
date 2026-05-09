using Windows.ApplicationModel.DataTransfer;

namespace Clawix.App.Services;

/// <summary>
/// NSPasteboard equivalent. Wraps WinRT <c>Clipboard</c>.
/// </summary>
public sealed class ClipboardService
{
    public string? GetText()
    {
        try
        {
            var view = Clipboard.GetContent();
            if (view.Contains(StandardDataFormats.Text))
                return view.GetTextAsync().AsTask().GetAwaiter().GetResult();
        }
        catch { }
        return null;
    }

    public void SetText(string text)
    {
        var pkg = new DataPackage();
        pkg.SetText(text);
        Clipboard.SetContent(pkg);
    }
}
