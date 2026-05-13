using Clawix.Bridged;
using Xunit;

namespace Clawix.Tests;

public sealed class BackendBinaryResolverTests
{
    [Fact]
    public void OverrideEnv_Wins()
    {
        var tmp = Path.Combine(Path.GetTempPath(), $"codex-{Guid.NewGuid():N}.cmd");
        File.WriteAllText(tmp, "@echo dummy");
        try
        {
            Environment.SetEnvironmentVariable("CLAWIX_BRIDGE_BACKEND_PATH", tmp);
            Assert.Equal(tmp, BackendBinaryResolver.Resolve());
        }
        finally
        {
            Environment.SetEnvironmentVariable("CLAWIX_BRIDGE_BACKEND_PATH", null);
            try { File.Delete(tmp); } catch { }
        }
    }

    [Fact]
    public void Candidates_AreNonEmpty()
    {
        var list = BackendBinaryResolver.CandidatePaths().ToList();
        Assert.NotEmpty(list);
        Assert.Contains(list, p => p.EndsWith("codex.cmd", StringComparison.OrdinalIgnoreCase) ||
                                   p.EndsWith("codex.exe", StringComparison.OrdinalIgnoreCase));
    }
}
