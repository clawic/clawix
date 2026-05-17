using System.Text.Json;
using Clawix.Core;
using Xunit;

namespace Clawix.Tests;

public sealed class BridgeFixtureParityTests
{
    [Fact]
    public void SwiftBridgeFixtures_DecodeAndRoundTrip()
    {
        var root = Path.Combine(AppContext.BaseDirectory, "Fixtures");
        var files = Directory.GetFiles(root, "*.json").OrderBy(static f => f).ToArray();

        Assert.True(files.Length >= 50, $"expected Swift bridge fixtures in {root}");

        var types = new HashSet<string>(StringComparer.Ordinal);
        foreach (var file in files)
        {
            var json = File.ReadAllText(file);
            using var doc = JsonDocument.Parse(json);
            var type = doc.RootElement.GetProperty("type").GetString();
            Assert.False(string.IsNullOrWhiteSpace(type), $"{file} is missing type");
            types.Add(type!);

            var frame = BridgeCoder.Decode(json);
            Assert.Equal(BridgeConstants.SchemaVersion, frame.SchemaVersion);

            var encoded = BridgeCoder.Encode(frame);
            var roundTrip = BridgeCoder.Decode(encoded);
            Assert.Equal(encoded, BridgeCoder.Encode(roundTrip));
        }

        foreach (var required in new[]
        {
            "auth",
            "sendMessage",
            "pairingPayload",
            "rateLimitsSnapshot",
            "audioRegister",
            "audioAttachTranscript",
            "audioGet",
            "audioGetBytes",
            "audioList",
            "audioDelete",
            "audioRegisterResult",
            "audioAttachTranscriptResult",
            "audioGetResult",
            "audioBytesResult",
            "audioListResult",
            "audioDeleteResult",
        })
        {
            Assert.Contains(required, types);
        }
    }
}
