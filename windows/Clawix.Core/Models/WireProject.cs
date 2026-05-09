namespace Clawix.Core.Models;

public sealed record WireProject
{
    public required string Id { get; init; }

    public required string Title { get; init; }

    public required string Cwd { get; init; }

    public bool HasGitRepo { get; init; }

    public string? Branch { get; init; }

    public DateTimeOffset? LastUsedAt { get; init; }
}
