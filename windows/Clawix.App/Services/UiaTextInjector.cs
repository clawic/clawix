using FlaUI.Core;
using FlaUI.Core.AutomationElements;
using FlaUI.UIA3;

namespace Clawix.App.Services;

/// <summary>
/// AXUIElement equivalent. Reads the currently selected text and
/// (optionally) replaces it with a transcript. Used by Dictation Power
/// Mode and QuickAsk selection sniffer.
/// </summary>
public sealed class UiaTextInjector : IDisposable
{
    private readonly UIA3Automation _automation = new();

    public string? GetSelectedText()
    {
        try
        {
            var focused = _automation.FocusedElement();
            if (focused?.Patterns.Text.IsSupported != true) return null;
            var sel = focused.Patterns.Text.Pattern.GetSelection();
            if (sel is null || sel.Length == 0) return null;
            return string.Join(string.Empty, sel.Select(r => r.GetText(int.MaxValue)));
        }
        catch { return null; }
    }

    public bool ReplaceSelection(string newText)
    {
        try
        {
            var focused = _automation.FocusedElement();
            if (focused is null) return false;
            if (focused.Patterns.Value.IsSupported)
            {
                focused.Patterns.Value.Pattern.SetValue(newText);
                return true;
            }
            // Fallback: type the new text via SendInput.
            FlaUI.Core.Input.Keyboard.Type(newText);
            return true;
        }
        catch { return false; }
    }

    public void Dispose() => _automation.Dispose();
}
