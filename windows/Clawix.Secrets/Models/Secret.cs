namespace Clawix.Secrets.Models;

public enum SecretKind
{
    ApiKey,
    Token,
    Generic,
}

public sealed record Secret
{
    public required string Id { get; init; }
    public required string Label { get; init; }
    public required SecretKind Kind { get; init; }
    public required DateTimeOffset CreatedAt { get; init; }
    public required byte[] WrappedValue { get; init; }
    public required byte[] Nonce { get; init; }
    public required byte[] WrappedKey { get; init; }
}
