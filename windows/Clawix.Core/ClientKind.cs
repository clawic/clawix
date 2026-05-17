using System.Runtime.Serialization;
using System.Text.Json.Serialization;

namespace Clawix.Core;

[JsonConverter(typeof(BridgeEnumJsonConverter<ClientKind>))]
public enum ClientKind
{
    [EnumMember(Value = "companion")] Companion,
    [EnumMember(Value = "desktop")] Desktop,
}
