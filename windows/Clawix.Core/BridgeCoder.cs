using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Clawix.Core;

/// <summary>
/// Shared JSON serializer options matching the Swift Codable defaults.
/// camelCase property naming, ISO-8601 dates with timezone, no escaping
/// of safe characters in strings (matches Swift's <c>withoutEscapingSlashes</c>).
/// </summary>
public static class BridgeCoder
{
    public static readonly JsonSerializerOptions Options = BuildOptions();

    private static JsonSerializerOptions BuildOptions()
    {
        var opts = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DictionaryKeyPolicy = null,
            DefaultIgnoreCondition = JsonIgnoreCondition.Never,
            Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        };
        return opts;
    }

    public static string Encode(BridgeFrame frame) => JsonSerializer.Serialize(frame, Options);

    public static byte[] EncodeBytes(BridgeFrame frame) => JsonSerializer.SerializeToUtf8Bytes(frame, Options);

    public static BridgeFrame Decode(string json) =>
        JsonSerializer.Deserialize<BridgeFrame>(json, Options)
        ?? throw new JsonException("frame decoded as null");

    public static BridgeFrame Decode(ReadOnlySpan<byte> json) =>
        JsonSerializer.Deserialize<BridgeFrame>(json, Options)
        ?? throw new JsonException("frame decoded as null");
}
