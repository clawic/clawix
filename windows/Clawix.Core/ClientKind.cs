using System.Text.Json.Serialization;

namespace Clawix.Core;

[JsonConverter(typeof(JsonStringEnumConverter<ClientKind>))]
public enum ClientKind
{
    [JsonStringEnumMemberName("ios")] Ios,
    [JsonStringEnumMemberName("desktop")] Desktop,
}
