namespace Clawix.Core.Models;

public sealed record WireAudioRef
{
    public required string Id { get; init; }

    public required string MimeType { get; init; }

    public required int DurationMs { get; init; }
}
