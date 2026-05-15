using System.Text.Json;
using Clawix.Engine.Pairing;
using Xunit;

namespace Clawix.Tests;

public sealed class PairingTests
{
    [Fact]
    public void Bearer_PersistsAcrossReads()
    {
        var store = new InMemoryPairingStore();
        var svc = new PairingService(store);
        var b1 = svc.Bearer;
        var b2 = svc.Bearer;
        Assert.Equal(b1, b2);
        Assert.True(b1.Length >= 40);
    }

    [Fact]
    public void Bearer_RotationProducesDifferentValue()
    {
        var svc = new PairingService(new InMemoryPairingStore());
        var b1 = svc.Bearer;
        svc.RotateBearer();
        var b2 = svc.Bearer;
        Assert.NotEqual(b1, b2);
    }

    [Fact]
    public void ShortCode_HasExpectedShape()
    {
        var svc = new PairingService(new InMemoryPairingStore());
        var code = svc.ShortCode;
        Assert.Equal(11, code.Length);
        Assert.Equal('-', code[3]);
        Assert.Equal('-', code[7]);
        foreach (var c in code.Replace("-", ""))
        {
            Assert.Contains(c, "23456789ABCDEFGHJKMNPQRSTUVWXYZ");
        }
    }

    [Fact]
    public void AcceptToken_IsConstantTimeOnLengthMatch()
    {
        var svc = new PairingService(new InMemoryPairingStore());
        Assert.True(svc.AcceptToken(svc.Bearer));
        Assert.False(svc.AcceptToken(new string('x', svc.Bearer.Length)));
        Assert.False(svc.AcceptToken("nope"));
    }

    [Fact]
    public void AcceptShortCode_NormalisesCase_AndStripsHyphens()
    {
        var svc = new PairingService(new InMemoryPairingStore());
        var code = svc.ShortCode;
        Assert.True(svc.AcceptShortCode(code));
        Assert.True(svc.AcceptShortCode(code.Replace("-", "")));
        Assert.True(svc.AcceptShortCode(code.ToLowerInvariant()));
        Assert.False(svc.AcceptShortCode("AAA-BBB-CCC"));
    }

    [Fact]
    public void QrPayload_HasExpectedSchema()
    {
        var svc = new PairingService(new InMemoryPairingStore());
        var json = svc.QrPayload();
        using var doc = JsonDocument.Parse(json);
        var root = doc.RootElement;
        Assert.Equal(1, root.GetProperty("v").GetInt32());
        Assert.Equal((int)svc.Port, root.GetProperty("port").GetInt32());
        Assert.Equal(svc.Bearer, root.GetProperty("token").GetString());
        Assert.Equal(svc.ShortCode, root.GetProperty("shortCode").GetString());
        Assert.True(root.TryGetProperty("host", out _));
        Assert.True(root.TryGetProperty("hostDisplayName", out _));
    }
}
