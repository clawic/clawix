using Clawix.Engine.Pairing;
using Xunit;

namespace Clawix.Tests;

public sealed class FilePairingStoreTests
{
    [Fact]
    public void RoundTripPersistsAcrossInstances()
    {
        var path = Path.Combine(Path.GetTempPath(), $"pairing-{Guid.NewGuid():N}.json");
        try
        {
            var s1 = new FilePairingStore(path);
            s1.SetBearer("token-abc");
            s1.SetShortCode("XXX-YYY-ZZZ");

            var s2 = new FilePairingStore(path);
            Assert.Equal("token-abc", s2.GetBearer());
            Assert.Equal("XXX-YYY-ZZZ", s2.GetShortCode());
        }
        finally { try { File.Delete(path); } catch { } }
    }

    [Fact]
    public void TolerantToCorruption()
    {
        var path = Path.Combine(Path.GetTempPath(), $"pairing-{Guid.NewGuid():N}.json");
        try
        {
            File.WriteAllText(path, "this is not json {{{{");
            var s = new FilePairingStore(path);
            Assert.Null(s.GetBearer());
            s.SetBearer("recovered");
            Assert.Equal("recovered", new FilePairingStore(path).GetBearer());
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
