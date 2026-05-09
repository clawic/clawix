using System.Security.Cryptography;

namespace Clawix.Secrets.Crypto;

/// <summary>
/// ChaCha20-Poly1305 AEAD wrapper. Matches the Swift
/// <c>SecretsCrypto</c> usage of CryptoKit's ChaCha20-Poly1305:
/// 12-byte nonce, 16-byte tag concatenated to the ciphertext.
/// </summary>
public static class Aead
{
    public const int NonceLength = 12;
    public const int TagLength = 16;
    public const int KeyLength = 32;

    public static byte[] Encrypt(ReadOnlySpan<byte> key, ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> plaintext, ReadOnlySpan<byte> aad = default)
    {
        if (key.Length != KeyLength) throw new ArgumentException("key must be 32 bytes");
        if (nonce.Length != NonceLength) throw new ArgumentException("nonce must be 12 bytes");
        using var chacha = new ChaCha20Poly1305(key.ToArray());
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[TagLength];
        chacha.Encrypt(nonce, plaintext, ciphertext, tag, aad);
        var result = new byte[ciphertext.Length + TagLength];
        Buffer.BlockCopy(ciphertext, 0, result, 0, ciphertext.Length);
        Buffer.BlockCopy(tag, 0, result, ciphertext.Length, TagLength);
        return result;
    }

    public static byte[] Decrypt(ReadOnlySpan<byte> key, ReadOnlySpan<byte> nonce, ReadOnlySpan<byte> ciphertextAndTag, ReadOnlySpan<byte> aad = default)
    {
        if (key.Length != KeyLength) throw new ArgumentException("key must be 32 bytes");
        if (nonce.Length != NonceLength) throw new ArgumentException("nonce must be 12 bytes");
        if (ciphertextAndTag.Length < TagLength) throw new CryptographicException("ciphertext too short");
        using var chacha = new ChaCha20Poly1305(key.ToArray());
        var ctLen = ciphertextAndTag.Length - TagLength;
        var ciphertext = ciphertextAndTag[..ctLen];
        var tag = ciphertextAndTag[ctLen..];
        var plaintext = new byte[ctLen];
        chacha.Decrypt(nonce, ciphertext, tag, plaintext, aad);
        return plaintext;
    }

    public static byte[] RandomBytes(int length)
    {
        var b = new byte[length];
        RandomNumberGenerator.Fill(b);
        return b;
    }
}
