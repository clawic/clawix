using System.Text.Json.Serialization;

namespace Clawix.Core;

[JsonConverter(typeof(JsonStringEnumConverter<ClientKind>))]
public enum ClientKind
{
    [JsonStringEnumMemberName("companion")] Companion,
    [JsonStringEnumMemberName("desktop")] Desktop,
}
