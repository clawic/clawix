namespace Clawix.Core.Models;

public sealed record WireMessage
{
    public required string Id { get; init; }

    public required WireRole Role { get; init; }

    public required string Content { get; init; }

    public string ReasoningText { get; init; } = string.Empty;

    public bool StreamingFinished { get; init; } = true;

    public bool IsError { get; init; }

    public required DateTimeOffset Timestamp { get; init; }

    public List<WireTimelineEntry> Timeline { get; init; } = [];

    public WireWorkSummary? WorkSummary { get; init; }

    public WireAudioRef? AudioRef { get; init; }

    public List<WireAttachment> Attachments { get; init; } = [];
}
