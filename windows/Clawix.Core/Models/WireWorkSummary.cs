namespace Clawix.Core.Models;

public sealed record WireWorkSummary
{
    public required DateTimeOffset StartedAt { get; init; }

    public DateTimeOffset? EndedAt { get; init; }

    public required List<WireWorkItem> Items { get; init; }
}
