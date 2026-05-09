using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

[JsonConverter(typeof(JsonStringEnumConverter<WireAttachmentKind>))]
public enum WireAttachmentKind
{
    [JsonStringEnumMemberName("image")] Image,
    [JsonStringEnumMemberName("audio")] Audio,
}
