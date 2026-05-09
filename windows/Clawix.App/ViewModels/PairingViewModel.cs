using CommunityToolkit.Mvvm.ComponentModel;

namespace Clawix.App.ViewModels;

public sealed partial class PairingViewModel : ObservableObject
{
    [ObservableProperty]
    private string _shortCode = string.Empty;

    [ObservableProperty]
    private string _qrJson = string.Empty;

    public PairingViewModel()
    {
        Refresh();
    }

    public void Refresh()
    {
        var p = App.Services.Pairing;
        ShortCode = p.ShortCode;
        QrJson = p.QrPayload();
    }
}
