using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

[JsonConverter(typeof(BridgeEnumJsonConverter<WireAudioKind>))]
public enum WireAudioKind
{
    [EnumMember(Value = "user_message")] UserMessage,
    [EnumMember(Value = "dictation")] Dictation,
    [EnumMember(Value = "agent_tts")] AgentTts,
}

[JsonConverter(typeof(BridgeEnumJsonConverter<WireAudioOriginActor>))]
public enum WireAudioOriginActor
{
    [EnumMember(Value = "user")] User,
    [EnumMember(Value = "agent")] Agent,
}

[JsonConverter(typeof(BridgeEnumJsonConverter<WireAudioTranscriptRole>))]
public enum WireAudioTranscriptRole
{
    [EnumMember(Value = "transcription")] Transcription,
    [EnumMember(Value = "synthesis_source")] SynthesisSource,
}

public sealed record WireAudioTranscript
{
    public required string Id { get; init; }
    public required string AudioId { get; init; }
    public required WireAudioTranscriptRole Role { get; init; }
    public required string Text { get; init; }
    public string? Provider { get; init; }
    public string? Language { get; init; }
    public required long CreatedAt { get; init; }
    public required bool IsPrimary { get; init; }
}

public sealed record WireAudioAsset
{
    public required string Id { get; init; }
    public required WireAudioKind Kind { get; init; }
    public required string AppId { get; init; }
    public required WireAudioOriginActor OriginActor { get; init; }
    public required string MimeType { get; init; }
    public required string BytesRelPath { get; init; }
    public required int DurationMs { get; init; }
    public required long CreatedAt { get; init; }
    public string? DeviceId { get; init; }
    public string? SessionId { get; init; }
    public string? ThreadId { get; init; }
    public string? LinkedMessageId { get; init; }
    public string? MetadataJson { get; init; }
}

public sealed record WireAudioAssetWithTranscripts
{
    public required WireAudioAsset Asset { get; init; }
    public IReadOnlyList<WireAudioTranscript> Transcripts { get; init; } = [];
}

public sealed record WireAudioRegisterTranscript
{
    public required string Text { get; init; }
    public WireAudioTranscriptRole? Role { get; init; }
    public string? Provider { get; init; }
    public string? Language { get; init; }
}

public sealed record WireAudioRegisterRequest
{
    public string? Id { get; init; }
    public required WireAudioKind Kind { get; init; }
    public required string AppId { get; init; }
    public required WireAudioOriginActor OriginActor { get; init; }
    public required string MimeType { get; init; }
    public required string BytesBase64 { get; init; }
    public required int DurationMs { get; init; }
    public string? DeviceId { get; init; }
    public string? SessionId { get; init; }
    public string? ThreadId { get; init; }
    public string? LinkedMessageId { get; init; }
    public string? MetadataJson { get; init; }
    public WireAudioRegisterTranscript? Transcript { get; init; }
}

public sealed record WireAudioAttachTranscriptInput
{
    public required string Text { get; init; }
    public required WireAudioTranscriptRole Role { get; init; }
    public string? Provider { get; init; }
    public string? Language { get; init; }
    public bool? MarkAsPrimary { get; init; }
}

public sealed record WireAudioListFilter
{
    public required string AppId { get; init; }
    public WireAudioKind? Kind { get; init; }
    public WireAudioOriginActor? OriginActor { get; init; }
    public string? DeviceId { get; init; }
    public string? SessionId { get; init; }
    public string? ThreadId { get; init; }
    public string? LinkedMessageId { get; init; }
    public long? FromCreatedAt { get; init; }
    public long? ToCreatedAt { get; init; }
    public int? Limit { get; init; }
    public int? Offset { get; init; }
}

public sealed record WireAudioListResult
{
    public IReadOnlyList<WireAudioAssetWithTranscripts> Items { get; init; } = [];
    public required int Total { get; init; }
}
