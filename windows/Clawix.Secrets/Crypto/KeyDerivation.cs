using System.Text;
using Konscious.Security.Cryptography;

namespace Clawix.Secrets.Crypto;

/// <summary>
/// Argon2id KDF. Parameters chosen to match the Swift
/// <c>SecretsCrypto/Argon2.swift</c>: 64 MiB memory, 3 iterations,
/// 4 lanes, 32-byte output. Mirrors RFC 9106 recommendation.
/// </summary>
public static class KeyDerivation
{
    public const int Memory = 64 * 1024;     // 64 MiB
    public const int Iterations = 3;
    public const int Lanes = 4;
    public const int OutputLength = 32;

    public static byte[] DeriveKey(string password, ReadOnlySpan<byte> salt)
    {
        var argon2 = new Argon2id(Encoding.UTF8.GetBytes(password))
        {
            Salt = salt.ToArray(),
            DegreeOfParallelism = Lanes,
            Iterations = Iterations,
            MemorySize = Memory,
        };
        return argon2.GetBytes(OutputLength);
    }
}
