using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace Clawix.Engine.Pairing;

/// <summary>
/// Port of <c>packages/ClawixEngine/PairingService.swift</c>. Holds the
/// stable bearer the iPhone presents on <c>auth</c>, generates the QR
/// payload identical to the macOS app, and resolves the LAN + Tailscale
/// IPv4 addresses to advertise.
/// </summary>
public sealed class PairingService
{
    private const string ShortCodeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

    private readonly IPairingStore _store;
    private readonly object _lock = new();

    public ushort Port { get; }

    public PairingService(IPairingStore store, ushort port = 7777)
    {
        _store = store;
        Port = port;
    }

    /// <summary>
    /// 32-byte token, base64url-encoded. Generated on first use, cached
    /// in the store, and reused on every relaunch so a paired iPhone
    /// keeps working across daemon rebuilds.
    /// </summary>
    public string Bearer
    {
        get
        {
            lock (_lock)
            {
                var cached = _store.GetBearer();
                if (!string.IsNullOrEmpty(cached)) return cached;
                var fresh = GenerateBearer();
                _store.SetBearer(fresh);
                return fresh;
            }
        }
    }

    public void RotateBearer()
    {
        lock (_lock) _store.SetBearer(GenerateBearer());
    }

    /// <summary>
    /// 9-character short code in <c>XXX-XXX-XXX</c> form. Persisted in
    /// the same store as the bearer so daemon and GUI agree.
    /// </summary>
    public string ShortCode
    {
        get
        {
            lock (_lock)
            {
                var cached = _store.GetShortCode();
                if (!string.IsNullOrEmpty(cached)) return cached;
                var fresh = GenerateShortCode();
                _store.SetShortCode(fresh);
                return fresh;
            }
        }
    }

    public void RotateShortCode()
    {
        lock (_lock) _store.SetShortCode(GenerateShortCode());
    }

    /// <summary>
    /// Constant-time-ish bearer comparison. Length first, then byte
    /// compare. Mirrors <c>acceptToken</c> in Swift.
    /// </summary>
    public bool AcceptToken(string candidate)
    {
        var truth = Bearer;
        var a = Encoding.UTF8.GetBytes(candidate);
        var b = Encoding.UTF8.GetBytes(truth);
        return CryptographicOperations.FixedTimeEquals(a, b);
    }

    public bool AcceptShortCode(string candidate)
    {
        var normalised = candidate.ToUpperInvariant().Replace("-", "");
        var truth = ShortCode.Replace("-", "");
        var a = Encoding.UTF8.GetBytes(normalised);
        var b = Encoding.UTF8.GetBytes(truth);
        return CryptographicOperations.FixedTimeEquals(a, b);
    }

    /// <summary>
    /// Bonjour instance name. Stable per machine, what the iPhone uses
    /// to recognise this PC across IP changes. Falls back to "Clawix"
    /// if the hostname is empty.
    /// </summary>
    public string BonjourServiceName
    {
        get
        {
            var name = Environment.MachineName;
            return string.IsNullOrEmpty(name) ? "Clawix" : name;
        }
    }

    /// <summary>
    /// JSON encoded in the QR. Bit-identical shape to Swift
    /// <c>qrPayload()</c>. Keys serialised in sorted order so a hash of
    /// the payload is stable across implementations.
    /// </summary>
    public string QrPayload()
    {
        var host = CurrentLanIPv4() ?? "0.0.0.0";
        var dict = new SortedDictionary<string, JsonNode?>(StringComparer.Ordinal)
        {
            ["v"] = 1,
            ["host"] = host,
            ["port"] = (int)Port,
            ["token"] = Bearer,
            ["shortCode"] = ShortCode,
            ["macName"] = BonjourServiceName,
        };
        var ts = CurrentTailscaleIPv4();
        if (!string.IsNullOrEmpty(ts)) dict["tailscaleHost"] = ts;

        var obj = new JsonObject();
        foreach (var (k, v) in dict) obj[k] = v;
        return obj.ToJsonString(new JsonSerializerOptions { WriteIndented = false });
    }

    // ===== bytes / codes =====

    private static string GenerateBearer()
    {
        Span<byte> bytes = stackalloc byte[32];
        RandomNumberGenerator.Fill(bytes);
        return Base64UrlEncode(bytes);
    }

    private static string GenerateShortCode()
    {
        Span<byte> bytes = stackalloc byte[9];
        RandomNumberGenerator.Fill(bytes);
        var chars = new char[9];
        for (int i = 0; i < 9; i++) chars[i] = ShortCodeAlphabet[bytes[i] % ShortCodeAlphabet.Length];
        return $"{chars[0]}{chars[1]}{chars[2]}-{chars[3]}{chars[4]}{chars[5]}-{chars[6]}{chars[7]}{chars[8]}";
    }

    private static string Base64UrlEncode(ReadOnlySpan<byte> bytes)
    {
        var s = Convert.ToBase64String(bytes);
        return s.Replace('+', '-').Replace('/', '_').TrimEnd('=');
    }

    // ===== network =====

    /// <summary>
    /// First non-loopback IPv4 of an "up" Ethernet/Wi-Fi adapter that is
    /// not the Tailscale CGNAT range. Returns null when no interface is
    /// usable (so the QR surfaces 0.0.0.0 and the iPhone fails visibly).
    /// </summary>
    public static string? CurrentLanIPv4()
    {
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            if (nic.NetworkInterfaceType is NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel)
                continue;
            if (nic.NetworkInterfaceType is not (NetworkInterfaceType.Ethernet
                or NetworkInterfaceType.GigabitEthernet
                or NetworkInterfaceType.FastEthernetT
                or NetworkInterfaceType.FastEthernetFx
                or NetworkInterfaceType.Wireless80211))
                continue;

            foreach (var addr in nic.GetIPProperties().UnicastAddresses)
            {
                if (addr.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                var s = addr.Address.ToString();
                if (s.StartsWith("127.", StringComparison.Ordinal)) continue;
                if (s.StartsWith("169.254.", StringComparison.Ordinal)) continue;
                if (IsTailscaleCgNat(addr.Address)) continue;
                return s;
            }
        }
        return null;
    }

    /// <summary>
    /// First IPv4 in the Tailscale CGNAT range (<c>100.64.0.0/10</c>).
    /// Tailscale on Windows assigns this to a virtual adapter; we don't
    /// shell out to the <c>tailscale</c> CLI because it isn't always in
    /// PATH. Returns null when Tailscale isn't running.
    /// </summary>
    public static string? CurrentTailscaleIPv4()
    {
        foreach (var nic in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (nic.OperationalStatus != OperationalStatus.Up) continue;
            foreach (var addr in nic.GetIPProperties().UnicastAddresses)
            {
                if (addr.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                if (IsTailscaleCgNat(addr.Address)) return addr.Address.ToString();
            }
        }
        return null;
    }

    private static bool IsTailscaleCgNat(IPAddress addr)
    {
        var bytes = addr.GetAddressBytes();
        return bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127;
    }
}
