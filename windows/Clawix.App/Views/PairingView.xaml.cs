using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using QRCoder;

namespace Clawix.App.Views;

public sealed partial class PairingView : UserControl
{
    public PairingView()
    {
        InitializeComponent();
        Loaded += (_, _) => Refresh();
    }

    public void Refresh()
    {
        var pairing = App.Services.Pairing;
        ShortCodeText.Text = pairing.ShortCode;
        var qrJson = pairing.QrPayload();
        using var gen = new QRCodeGenerator();
        var data = gen.CreateQrCode(qrJson, QRCodeGenerator.ECCLevel.Q);
        var png = new PngByteQRCode(data).GetGraphic(20);
        var bitmap = new BitmapImage();
        using var ms = new MemoryStream(png);
        bitmap.SetSource(ms.AsRandomAccessStream());
        QrImage.Source = bitmap;
    }
}
