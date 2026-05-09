using System.Text.Json;

namespace Clawix.Engine.Pairing;

/// <summary>
/// Atomic JSON file at <c>%APPDATA%\Clawix\pairing.json</c>. Survives
/// rebuilds and is shared between GUI and daemon, mirroring the
/// macOS UserDefaults suite <c>clawix.bridge</c>.
/// </summary>
public sealed class FilePairingStore : IPairingStore
{
    private readonly string _path;
    private readonly object _lock = new();

    public FilePairingStore(string? path = null)
    {
        _path = path ?? DefaultPath();
        Directory.CreateDirectory(Path.GetDirectoryName(_path)!);
    }

    public static string DefaultPath()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        return Path.Combine(appData, "Clawix", "pairing.json");
    }

    private sealed record PairingState(string? Bearer, string? ShortCode);

    public string? GetBearer() => Read().Bearer;
    public string? GetShortCode() => Read().ShortCode;

    public void SetBearer(string value) => Mutate(s => s with { Bearer = value });
    public void SetShortCode(string value) => Mutate(s => s with { ShortCode = value });

    private PairingState Read()
    {
        lock (_lock)
        {
            if (!File.Exists(_path)) return new PairingState(null, null);
            try
            {
                var json = File.ReadAllText(_path);
                return JsonSerializer.Deserialize<PairingState>(json) ?? new PairingState(null, null);
            }
            catch
            {
                return new PairingState(null, null);
            }
        }
    }

    private void Mutate(Func<PairingState, PairingState> f)
    {
        lock (_lock)
        {
            var current = Read();
            var next = f(current);
            var tmp = _path + ".tmp";
            File.WriteAllText(tmp, JsonSerializer.Serialize(next, new JsonSerializerOptions { WriteIndented = true }));
            File.Move(tmp, _path, overwrite: true);
        }
    }
}

public sealed class InMemoryPairingStore : IPairingStore
{
    private string? _bearer;
    private string? _shortCode;

    public string? GetBearer() => _bearer;
    public string? GetShortCode() => _shortCode;
    public void SetBearer(string value) => _bearer = value;
    public void SetShortCode(string value) => _shortCode = value;
}
