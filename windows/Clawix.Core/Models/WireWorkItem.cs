using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

[JsonConverter(typeof(BridgeEnumJsonConverter<WireWorkItemStatus>))]
public enum WireWorkItemStatus
{
    [EnumMember(Value = "inProgress")] InProgress,
    [EnumMember(Value = "completed")] Completed,
    [EnumMember(Value = "failed")] Failed,
}

public sealed record WireWorkItem
{
    public required string Id { get; init; }

    public required string Kind { get; init; }

    public required WireWorkItemStatus Status { get; init; }

    public string? CommandText { get; init; }

    public List<string>? CommandActions { get; init; }

    public List<string>? Paths { get; init; }

    public string? McpServer { get; init; }

    public string? McpTool { get; init; }

    public string? DynamicToolName { get; init; }

    public string? GeneratedImagePath { get; init; }
}
