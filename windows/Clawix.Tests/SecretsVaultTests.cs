using Clawix.Secrets.Crypto;
using Clawix.Secrets.Models;
using Clawix.Secrets.Vault;
using Xunit;

namespace Clawix.Tests;

public sealed class SecretsVaultTests
{
    [Fact]
    public void Aead_RoundTrip()
    {
        var key = Aead.RandomBytes(Aead.KeyLength);
        var nonce = Aead.RandomBytes(Aead.NonceLength);
        var plaintext = "hello"u8.ToArray();
        var sealed_ = Aead.Encrypt(key, nonce, plaintext);
        var open = Aead.Decrypt(key, nonce, sealed_);
        Assert.Equal(plaintext, open);
    }

    [Fact]
    public void Aead_TamperedTagFails()
    {
        var key = Aead.RandomBytes(Aead.KeyLength);
        var nonce = Aead.RandomBytes(Aead.NonceLength);
        var sealed_ = Aead.Encrypt(key, nonce, "secret"u8.ToArray());
        sealed_[^1] ^= 0xFF;
        Assert.ThrowsAny<System.Security.Cryptography.CryptographicException>(
            () => Aead.Decrypt(key, nonce, sealed_));
    }

    [Fact]
    public void KeyDerivation_DeterministicWithSameSalt()
    {
        var salt = Aead.RandomBytes(16);
        var k1 = KeyDerivation.DeriveKey("correct horse battery staple", salt);
        var k2 = KeyDerivation.DeriveKey("correct horse battery staple", salt);
        Assert.Equal(k1, k2);
        Assert.NotEqual(k1, KeyDerivation.DeriveKey("other passphrase", salt));
    }

    [Fact]
    public void Vault_AddListLifecycle()
    {
        var path = Path.Combine(Path.GetTempPath(), $"vault-{Guid.NewGuid():N}.sqlite");
        try
        {
            using var v = new Vault(path);
            v.Unlock("hunter2", System.Text.Encoding.UTF8.GetBytes("test-salt-16-byt"));
            Assert.True(v.IsUnlocked);

            v.Add("OPENAI_API_KEY", SecretKind.ApiKey, "sk-xxxxx");
            v.Add("FOO", SecretKind.Generic, "bar");

            var listed = v.List();
            Assert.Equal(2, listed.Count);
            Assert.Contains(listed, s => s.Label == "OPENAI_API_KEY" && s.Kind == SecretKind.ApiKey);
        }
        finally { try { File.Delete(path); } catch { } }
    }
}
