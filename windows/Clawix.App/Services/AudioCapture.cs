using NAudio.Wave;

namespace Clawix.App.Services;

/// <summary>
/// AVAudioEngine equivalent. Captures 16-bit PCM at 16 kHz mono into a
/// WAV file for Whisper. Caller owns the lifecycle (Start/Stop).
/// </summary>
public sealed class AudioCapture : IDisposable
{
    private WasapiCapture? _capture;
    private WaveFileWriter? _writer;
    private string? _outputPath;

    public bool IsRecording => _capture is not null;

    public string Start()
    {
        if (_capture is not null) throw new InvalidOperationException("already recording");
        _outputPath = Path.Combine(Path.GetTempPath(), $"clawix-rec-{Guid.NewGuid():N}.wav");
        _capture = new WasapiCapture
        {
            WaveFormat = new WaveFormat(16000, 16, 1),
        };
        _writer = new WaveFileWriter(_outputPath, _capture.WaveFormat);
        _capture.DataAvailable += (_, e) => _writer?.Write(e.Buffer, 0, e.BytesRecorded);
        _capture.RecordingStopped += (_, _) =>
        {
            _writer?.Dispose();
            _writer = null;
        };
        _capture.StartRecording();
        return _outputPath;
    }

    public string? Stop()
    {
        if (_capture is null) return null;
        _capture.StopRecording();
        _capture.Dispose();
        _capture = null;
        var p = _outputPath;
        _outputPath = null;
        return p;
    }

    public void Dispose()
    {
        try { Stop(); } catch { }
        _writer?.Dispose();
        _capture?.Dispose();
    }
}
