namespace Clawix.Engine.Pairing;

/// <summary>
/// Persistence backend for the bearer + short code. Lets the same
/// <see cref="PairingService"/> work with file storage in production
/// and in-memory storage in tests.
/// </summary>
public interface IPairingStore
{
    string? GetBearer();
    void SetBearer(string value);
    string? GetShortCode();
    void SetShortCode(string value);
}
