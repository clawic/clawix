using Microsoft.Windows.ApplicationModel.Resources;

namespace Clawix.App.Services;

/// <summary>
/// Localized strings accessor. Wraps the WindowsAppSDK
/// <c>ResourceLoader</c> so view-models can do
/// <c>Loc.Get("Sidebar.NewSession")</c>.
/// </summary>
public static class Loc
{
    private static readonly ResourceLoader _loader = new();

    public static string Get(string key)
    {
        try { return _loader.GetString(key.Replace('.', '/')); }
        catch { return key; }
    }
}
