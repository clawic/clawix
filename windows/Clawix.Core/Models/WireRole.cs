using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

[JsonConverter(typeof(BridgeEnumJsonConverter<WireRole>))]
public enum WireRole
{
    [EnumMember(Value = "user")] User,
    [EnumMember(Value = "assistant")] Assistant,
}
