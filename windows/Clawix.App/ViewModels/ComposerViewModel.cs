using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;

namespace Clawix.App.ViewModels;

public sealed partial class ComposerViewModel : ObservableObject
{
    [ObservableProperty]
    private string _draft = string.Empty;

    [ObservableProperty]
    private bool _busy;

    [RelayCommand]
    private async Task SendAsync()
    {
        var text = (Draft ?? string.Empty).Trim();
        if (string.IsNullOrEmpty(text) || Busy) return;
        Busy = true;
        try
        {
            await App.Services.State.SendPromptAsync(text);
            Draft = string.Empty;
        }
        finally { Busy = false; }
    }

    [RelayCommand]
    private void Attach()
    {
        // Open photo picker -> attach. Phase 4.
    }
}
