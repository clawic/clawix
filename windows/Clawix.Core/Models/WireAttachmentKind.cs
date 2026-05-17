using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

[JsonConverter(typeof(BridgeEnumJsonConverter<WireAttachmentKind>))]
public enum WireAttachmentKind
{
    [EnumMember(Value = "image")] Image,
    [EnumMember(Value = "audio")] Audio,
}
