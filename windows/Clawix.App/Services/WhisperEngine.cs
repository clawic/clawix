using Microsoft.Extensions.Logging;
using Whisper.net;

namespace Clawix.App.Services;

/// <summary>
/// Whisper.net wrapper. Loads a ggml model from
/// <c>%LOCALAPPDATA%\Clawix\models\</c>. The model is NOT shipped with
/// the MSIX (size); the user downloads it from Settings -> Dictation.
/// </summary>
public sealed class WhisperEngine : IDisposable
{
    private readonly string _modelPath;
    private readonly ILogger<WhisperEngine> _logger;
    private WhisperFactory? _factory;

    public WhisperEngine(string modelName, ILogger<WhisperEngine> logger)
    {
        _logger = logger;
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        _modelPath = Path.Combine(local, "Clawix", "models", $"ggml-{modelName}.bin");
    }

    public bool ModelInstalled => File.Exists(_modelPath);

    public async Task<string> TranscribeAsync(string wavPath, string? language = null, CancellationToken ct = default)
    {
        if (!ModelInstalled)
            throw new FileNotFoundException("Whisper model not installed.", _modelPath);

        _factory ??= WhisperFactory.FromPath(_modelPath);
        await using var processor = _factory.CreateBuilder()
            .WithLanguage(language ?? "auto")
            .Build();

        var transcript = new System.Text.StringBuilder();
        await using var stream = File.OpenRead(wavPath);
        await foreach (var seg in processor.ProcessAsync(stream, ct))
        {
            transcript.Append(seg.Text);
        }
        return transcript.ToString().Trim();
    }

    public void Dispose() => _factory?.Dispose();
}
