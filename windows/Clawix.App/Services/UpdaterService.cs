using Microsoft.Extensions.Logging;
using NetSparkleUpdater;
using NetSparkleUpdater.Enums;
using NetSparkleUpdater.SignatureVerifiers;

namespace Clawix.App.Services;

/// <summary>
/// Sparkle equivalent for Windows. Reads the same <c>appcast.xml</c>
/// the macOS Sparkle uses but filters by
/// <c>sparkle:os="windows"</c>. EdDSA signing key is shared with the
/// macOS pipeline.
/// </summary>
public sealed class UpdaterService
{
    private readonly ILogger<UpdaterService> _logger;
    private SparkleUpdater? _sparkle;

    public UpdaterService(ILogger<UpdaterService> logger) { _logger = logger; }

    public void Initialize(string appcastUrl, string edPublicKey)
    {
        _sparkle = new SparkleUpdater(appcastUrl, new Ed25519Checker(SecurityMode.Strict, edPublicKey))
        {
            UIFactory = null,
            CheckServerFileName = false,
        };
        _sparkle.StartLoop(true, true, TimeSpan.FromHours(6));
    }

    public async Task<UpdateInfo?> CheckAsync()
    {
        if (_sparkle is null) return null;
        return await _sparkle.CheckForUpdatesQuietly();
    }
}
