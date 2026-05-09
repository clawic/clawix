using Windows.Media.Capture;
using Windows.Media.MediaProperties;
using Windows.Storage.Streams;

namespace Clawix.App.Services;

/// <summary>
/// QuickAsk camera. Wraps WinRT <c>MediaCapture</c> for a single
/// JPEG frame.
/// </summary>
public sealed class CameraCapture : IAsyncDisposable
{
    private MediaCapture? _media;

    public async Task InitializeAsync()
    {
        _media = new MediaCapture();
        await _media.InitializeAsync();
    }

    public async Task<byte[]> CaptureJpegAsync()
    {
        if (_media is null) throw new InvalidOperationException("call InitializeAsync first");
        using var stream = new InMemoryRandomAccessStream();
        await _media.CapturePhotoToStreamAsync(ImageEncodingProperties.CreateJpeg(), stream);
        var bytes = new byte[stream.Size];
        var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync((uint)stream.Size);
        reader.ReadBytes(bytes);
        return bytes;
    }

    public async ValueTask DisposeAsync()
    {
        if (_media is not null)
        {
            try { await Task.Run(() => _media.Dispose()); } catch { }
            _media = null;
        }
    }
}
