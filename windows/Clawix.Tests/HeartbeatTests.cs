using System.Text.Json;
using Clawix.Bridged;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

namespace Clawix.Tests;

public sealed class HeartbeatTests
{
    [Fact]
    public async Task Heartbeat_WritesJsonInUserProfile()
    {
        // Use a private profile dir so we don't clobber the real heartbeat.
        var tmp = Path.Combine(Path.GetTempPath(), $"clawix-hb-{Guid.NewGuid():N}");
        Directory.CreateDirectory(tmp);
        var prevHome = Environment.GetEnvironmentVariable("USERPROFILE");
        try
        {
            Environment.SetEnvironmentVariable("USERPROFILE", tmp);
            await using var hb = new Heartbeat(() => new HeartbeatState
            {
                Version = "0.0.0",
                Port = 7777,
                State = "ready",
                ChatCount = 0,
            }, NullLogger<Heartbeat>.Instance);
            await hb.StartAsync();
            // Allow one tick.
            await Task.Delay(2200);
            var p = Path.Combine(tmp, ".clawix", "state", "bridge-status.json");
            Assert.True(File.Exists(p));
            using var doc = JsonDocument.Parse(File.ReadAllText(p));
            Assert.Equal("ready", doc.RootElement.GetProperty("state").GetString());
            Assert.Equal(7777, doc.RootElement.GetProperty("port").GetInt32());
        }
        finally
        {
            Environment.SetEnvironmentVariable("USERPROFILE", prevHome);
            try { Directory.Delete(tmp, recursive: true); } catch { }
        }
    }
}
