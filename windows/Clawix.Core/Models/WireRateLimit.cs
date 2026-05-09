namespace Clawix.Core.Models;

public sealed record WireRateLimitWindow
{
    public required int UsedPercent { get; init; }

    public long? ResetsAt { get; init; }

    public long? WindowDurationMins { get; init; }
}

public sealed record WireCreditsSnapshot
{
    public required bool HasCredits { get; init; }

    public required bool Unlimited { get; init; }

    public string? Balance { get; init; }
}

public sealed record WireRateLimitSnapshot
{
    public WireRateLimitWindow? Primary { get; init; }

    public WireRateLimitWindow? Secondary { get; init; }

    public WireCreditsSnapshot? Credits { get; init; }

    public string? LimitId { get; init; }

    public string? LimitName { get; init; }
}
