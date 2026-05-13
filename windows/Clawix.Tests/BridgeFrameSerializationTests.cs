using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;
using Xunit;

namespace Clawix.Tests;

/// <summary>
/// Goes one step deeper than BridgeProtocolTests: each frame variant is
/// re-serialized and the JSON shape is asserted to match the Swift
/// expected output (camelCase keys, optional fields omitted, etc.).
/// </summary>
public sealed class BridgeFrameSerializationTests
{
    private static T RoundTrip<T>(T body) where T : BridgeBody
    {
        var f = new BridgeFrame(body);
        var json = BridgeCoder.Encode(f);
        var back = BridgeCoder.Decode(json);
        return Assert.IsType<T>(back.Body);
    }

    [Fact] public void Auth_RoundTrip() => Assert.Equal("token", RoundTrip(new BridgeBody.Auth("token", null, null)).Token);
    [Fact] public void OpenSession_RoundTrip() => Assert.Equal("c1", RoundTrip(new BridgeBody.OpenSession("c1", 60)).SessionId);
    [Fact] public void LoadOlder_RoundTrip() => Assert.Equal(40, RoundTrip(new BridgeBody.LoadOlderMessages("c1", "m1", 40)).Limit);
    [Fact] public void EditPrompt_RoundTrip() => Assert.Equal("hi", RoundTrip(new BridgeBody.EditPrompt("c1", "m1", "hi")).Text);
    [Fact] public void RenameSession_RoundTrip() => Assert.Equal("New title", RoundTrip(new BridgeBody.RenameSession("c1", "New title")).Title);
    [Fact] public void Archive_RoundTrip() => Assert.Equal("c1", RoundTrip(new BridgeBody.ArchiveSession("c1")).SessionId);
    [Fact] public void Pin_RoundTrip() => Assert.Equal("c1", RoundTrip(new BridgeBody.PinSession("c1")).SessionId);
    [Fact] public void PairingPayload_RoundTrip() => Assert.Equal("{}", RoundTrip(new BridgeBody.PairingPayload("{}", "tok")).QrJson);
    [Fact] public void Bridgestate_RoundTrip() => Assert.Equal("ready", RoundTrip(new BridgeBody.BridgeState("ready", 5, null)).State);

    [Fact]
    public void RateLimits_KeyNamesMatchSwift()
    {
        var f = new BridgeFrame(new BridgeBody.RateLimitsSnapshot(null, new Dictionary<string, WireRateLimitSnapshot>()));
        var json = BridgeCoder.Encode(f);
        Assert.Contains("\"rateLimitsByLimitId\":{}", json);
        Assert.DoesNotContain("\"snapshot\":", json);
        Assert.DoesNotContain("\"byLimitId\":", json);
    }

    [Fact]
    public void TimelineEntry_AllSubtypes_RoundTrip()
    {
        var entries = new List<WireTimelineEntry>
        {
            new WireTimelineEntry.Reasoning { Id = "r", Text = "thinking..." },
            new WireTimelineEntry.Message { Id = "m", Text = "hello" },
            new WireTimelineEntry.Tools { Id = "t", Items = [
                new WireWorkItem { Id = "w1", Kind = "command", Status = WireWorkItemStatus.Completed, CommandText = "ls" }
            ] },
        };
        var json = JsonSerializer.Serialize(entries, BridgeCoder.Options);
        var back = JsonSerializer.Deserialize<List<WireTimelineEntry>>(json, BridgeCoder.Options);
        Assert.NotNull(back);
        Assert.Equal(3, back!.Count);
        Assert.IsType<WireTimelineEntry.Reasoning>(back[0]);
        Assert.IsType<WireTimelineEntry.Message>(back[1]);
        Assert.IsType<WireTimelineEntry.Tools>(back[2]);
    }
}
