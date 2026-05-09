using Microsoft.UI.Windowing;

namespace Clawix.App.Services;

/// <summary>
/// NSScreen equivalent. Enumerates monitors with their physical bounds
/// and DPI scale.
/// </summary>
public sealed class ScreenService
{
    public sealed record DisplayInfo(string Id, int X, int Y, int Width, int Height, double DpiScale);

    public IReadOnlyList<DisplayInfo> All()
    {
        var list = new List<DisplayInfo>();
        foreach (var area in DisplayArea.FindAll())
        {
            list.Add(new DisplayInfo(
                Id: area.DisplayId.Value.ToString(),
                X: area.OuterBounds.X,
                Y: area.OuterBounds.Y,
                Width: area.OuterBounds.Width,
                Height: area.OuterBounds.Height,
                DpiScale: 1.0));
        }
        return list;
    }
}
