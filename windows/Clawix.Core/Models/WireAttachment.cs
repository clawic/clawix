using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

public sealed record WireAttachment
{
    public required string Id { get; init; }

    public WireAttachmentKind Kind { get; init; } = WireAttachmentKind.Image;

    public required string MimeType { get; init; }

    public string? Filename { get; init; }

    public required string DataBase64 { get; init; }

    [JsonConstructor]
    public WireAttachment() { }
}
