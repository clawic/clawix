using Clawix.Core.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace Clawix.App.Views;

public sealed partial class RateLimitsWidget : UserControl
{
    public RateLimitsWidget()
    {
        InitializeComponent();
        Loaded += (_, _) =>
        {
            // Initial render. Real updates flow from rateLimitsSnapshot
            // / rateLimitsUpdated frames once the daemon pushes them.
            Render(null, null);
        };
    }

    public void Render(WireRateLimitWindow? primary, WireRateLimitWindow? secondary)
    {
        if (primary is not null)
        {
            PrimaryBar.Value = primary.UsedPercent;
            PrimaryText.Text = $"{primary.UsedPercent}%";
        }
        if (secondary is not null)
        {
            SecondaryBar.Value = secondary.UsedPercent;
            SecondaryText.Text = $"{secondary.UsedPercent}%";
        }
    }

    public void RenderCredits(WireCreditsSnapshot? credits)
    {
        if (credits is null) { CreditsText.Visibility = Visibility.Collapsed; return; }
        CreditsText.Visibility = Visibility.Visible;
        CreditsText.Text = credits.Unlimited ? "Credits: unlimited" : $"Credits: {credits.Balance ?? "0"}";
    }
}
