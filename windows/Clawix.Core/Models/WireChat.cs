namespace Clawix.Core.Models;

public sealed record WireChat
{
    public required string Id { get; init; }

    public required string Title { get; init; }

    public required DateTimeOffset CreatedAt { get; init; }

    public bool IsPinned { get; init; }

    public bool IsArchived { get; init; }

    public bool HasActiveTurn { get; init; }

    public DateTimeOffset? LastMessageAt { get; init; }

    public string? LastMessagePreview { get; init; }

    public string? Branch { get; init; }

    public string? Cwd { get; init; }

    public bool LastTurnInterrupted { get; init; }

    public string? ThreadId { get; init; }
}
