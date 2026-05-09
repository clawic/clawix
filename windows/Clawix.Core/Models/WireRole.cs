using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

[JsonConverter(typeof(JsonStringEnumConverter<WireRole>))]
public enum WireRole
{
    [JsonStringEnumMemberName("user")] User,
    [JsonStringEnumMemberName("assistant")] Assistant,
}
