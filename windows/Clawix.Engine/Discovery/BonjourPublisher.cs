using Makaretu.Dns;

namespace Clawix.Engine.Discovery;

/// <summary>
/// Publishes the bridge over mDNS as <c>_clawix-bridge._tcp</c> so the
/// iPhone can discover the daemon by Bonjour. Pure C#: no dependency
/// on Apple Bonjour Service for Windows (which is unmaintained).
/// </summary>
public sealed class BonjourPublisher : IAsyncDisposable
{
    private const string ServiceType = "_clawix-bridge._tcp";

    private readonly ServiceDiscovery _sd;
    private readonly MulticastService _mdns;
    private ServiceProfile? _profile;

    public BonjourPublisher()
    {
        _mdns = new MulticastService();
        _sd = new ServiceDiscovery(_mdns);
    }

    public Task PublishAsync(string instanceName, ushort port, CancellationToken ct = default)
    {
        var profile = new ServiceProfile(instanceName, ServiceType, port);
        _profile = profile;
        _sd.Advertise(profile);
        _mdns.Start();
        return Task.CompletedTask;
    }

    public Task UnpublishAsync(CancellationToken ct = default)
    {
        if (_profile is not null)
        {
            try { _sd.Unadvertise(_profile); } catch { /* tolerate */ }
            _profile = null;
        }
        return Task.CompletedTask;
    }

    public ValueTask DisposeAsync()
    {
        try { _mdns.Stop(); } catch { }
        _sd.Dispose();
        _mdns.Dispose();
        return ValueTask.CompletedTask;
    }
}
