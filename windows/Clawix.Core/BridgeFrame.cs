using System.Text.Json.Serialization;

namespace Clawix.Core;

/// <summary>
/// Wire envelope. Flat JSON: { schemaVersion, type, ...payload }.
/// Mirrors <c>BridgeFrame</c> in Swift (packages/ClawixCore/BridgeProtocol.swift).
/// </summary>
[JsonConverter(typeof(BridgeFrameConverter))]
public sealed record BridgeFrame(BridgeBody Body, int SchemaVersion = BridgeConstants.SchemaVersion);

public sealed class BridgeDecodingException : Exception
{
    public BridgeDecodingException(string message) : base(message) { }

    public static BridgeDecodingException UnknownType(string type) => new($"unknown frame type: {type}");
}
