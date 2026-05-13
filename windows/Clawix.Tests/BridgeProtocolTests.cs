using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;
using Xunit;

namespace Clawix.Tests;

public sealed class BridgeProtocolTests
{
    [Fact]
    public void SchemaVersion_Matches_Swift()
    {
        Assert.Equal(5, BridgeConstants.SchemaVersion);
        Assert.Equal(60, BridgeConstants.InitialPageLimit);
        Assert.Equal(40, BridgeConstants.OlderPageLimit);
    }

    [Fact]
    public void Auth_Frame_RoundTrip()
    {
        var frame = new BridgeFrame(new BridgeBody.Auth("token-abc", "iPhone 15", ClientKind.Ios));
        var json = BridgeCoder.Encode(frame);
        Assert.Contains("\"schemaVersion\":5", json);
        Assert.Contains("\"type\":\"auth\"", json);
        Assert.Contains("\"token\":\"token-abc\"", json);
        Assert.Contains("\"deviceName\":\"iPhone 15\"", json);
        Assert.Contains("\"clientKind\":\"ios\"", json);

        var decoded = BridgeCoder.Decode(json);
        Assert.Equal(frame, decoded);
    }

    [Fact]
    public void Auth_Frame_OmitsOptionalFields()
    {
        var frame = new BridgeFrame(new BridgeBody.Auth("t", null, null));
        var json = BridgeCoder.Encode(frame);
        Assert.DoesNotContain("\"deviceName\"", json);
        Assert.DoesNotContain("\"clientKind\"", json);
        var decoded = BridgeCoder.Decode(json);
        Assert.Equal(frame, decoded);
    }

    [Fact]
    public void ListSessions_HasNoPayload()
    {
        var frame = new BridgeFrame(new BridgeBody.ListSessions());
        var json = BridgeCoder.Encode(frame);
        Assert.Equal("{\"schemaVersion\":5,\"type\":\"listSessions\"}", json);
        var decoded = BridgeCoder.Decode(json);
        Assert.IsType<BridgeBody.ListSessions>(decoded.Body);
    }

    [Fact]
    public void OpenSession_OmitsLimitWhenNull()
    {
        var noLimit = new BridgeFrame(new BridgeBody.OpenSession("chat-1", null));
        var jsonA = BridgeCoder.Encode(noLimit);
        Assert.DoesNotContain("\"limit\"", jsonA);

        var withLimit = new BridgeFrame(new BridgeBody.OpenSession("chat-1", 60));
        var jsonB = BridgeCoder.Encode(withLimit);
        Assert.Contains("\"limit\":60", jsonB);
    }

    [Fact]
    public void SendPrompt_OmitsAttachmentsWhenEmpty()
    {
        var frame = new BridgeFrame(new BridgeBody.SendPrompt("c", "hi", []));
        var json = BridgeCoder.Encode(frame);
        Assert.DoesNotContain("\"attachments\"", json);

        var att = new WireAttachment { Id = "a1", MimeType = "image/png", Filename = "p.png", DataBase64 = "AAAA" };
        var withAtt = new BridgeFrame(new BridgeBody.SendPrompt("c", "hi", [att]));
        var jsonB = BridgeCoder.Encode(withAtt);
        Assert.Contains("\"attachments\"", jsonB);
        var decoded = BridgeCoder.Decode(jsonB);
        Assert.Equal(withAtt, decoded);
    }

    [Fact]
    public void SessionsSnapshot_RoundTrip()
    {
        var chat = new WireChat
        {
            Id = "id-1",
            Title = "Hello",
            CreatedAt = DateTimeOffset.Parse("2026-05-09T10:00:00Z"),
            HasActiveTurn = true,
            LastMessagePreview = "ping",
        };
        var frame = new BridgeFrame(new BridgeBody.SessionsSnapshot([chat]));
        var json = BridgeCoder.Encode(frame);
        var decoded = BridgeCoder.Decode(json);
        Assert.IsType<BridgeBody.SessionsSnapshot>(decoded.Body);
        Assert.Equal(frame, decoded);
    }

    [Fact]
    public void RateLimitsSnapshot_UsesRateLimitsKey()
    {
        var snapshot = new WireRateLimitSnapshot
        {
            Primary = new WireRateLimitWindow { UsedPercent = 30, ResetsAt = 1700000000, WindowDurationMins = 60 },
            LimitId = "codex",
        };
        var frame = new BridgeFrame(new BridgeBody.RateLimitsSnapshot(snapshot, new Dictionary<string, WireRateLimitSnapshot>()));
        var json = BridgeCoder.Encode(frame);
        Assert.Contains("\"rateLimits\"", json);
        Assert.Contains("\"rateLimitsByLimitId\"", json);
        Assert.DoesNotContain("\"snapshot\"", json);
        var decoded = BridgeCoder.Decode(json);
        Assert.Equal(frame, decoded);
    }

    [Fact]
    public void Unknown_Type_Throws()
    {
        var json = "{\"schemaVersion\":5,\"type\":\"someUnknownThing\",\"sessionId\":\"x\"}";
        Assert.ThrowsAny<Exception>(() => BridgeCoder.Decode(json));
    }

    [Theory]
    [InlineData("listSessions")]
    [InlineData("pairingStart")]
    [InlineData("listProjects")]
    [InlineData("requestRateLimits")]
    public void EmptyBodies_RoundTrip(string typeTag)
    {
        var json = $"{{\"schemaVersion\":5,\"type\":\"{typeTag}\"}}";
        var decoded = BridgeCoder.Decode(json);
        Assert.Equal(typeTag, decoded.Body.TypeTag);
    }

    [Fact]
    public void MessageStreaming_PreservesAllFields()
    {
        var frame = new BridgeFrame(new BridgeBody.MessageStreaming("c", "m", "hello", "thinking", false));
        var json = BridgeCoder.Encode(frame);
        var decoded = BridgeCoder.Decode(json);
        Assert.Equal(frame, decoded);
    }

    [Fact]
    public void MessagesSnapshot_HasMoreOptional()
    {
        var msg = new WireMessage { Id = "m", Role = WireRole.User, Content = "hi", Timestamp = DateTimeOffset.UtcNow };
        var noHasMore = new BridgeFrame(new BridgeBody.MessagesSnapshot("c", [msg], null));
        var jsonA = BridgeCoder.Encode(noHasMore);
        Assert.DoesNotContain("\"hasMore\"", jsonA);

        var withHasMore = new BridgeFrame(new BridgeBody.MessagesSnapshot("c", [msg], true));
        var jsonB = BridgeCoder.Encode(withHasMore);
        Assert.Contains("\"hasMore\":true", jsonB);
    }

    [Fact]
    public void TimelineEntry_Tools_Subtype_RoundTrip()
    {
        var item = new WireWorkItem
        {
            Id = "w1",
            Kind = "command",
            Status = WireWorkItemStatus.Completed,
            CommandText = "ls",
            CommandActions = ["read"],
        };
        var entry = new WireTimelineEntry.Tools { Id = "t1", Items = [item] };
        var msg = new WireMessage
        {
            Id = "m",
            Role = WireRole.Assistant,
            Content = "done",
            Timestamp = DateTimeOffset.UtcNow,
            Timeline = [entry],
        };
        var frame = new BridgeFrame(new BridgeBody.MessageAppended("c", msg));
        var json = BridgeCoder.Encode(frame);
        Assert.Contains("\"type\":\"tools\"", json);
        var decoded = BridgeCoder.Decode(json);
        Assert.Equal(frame, decoded);
    }
}
