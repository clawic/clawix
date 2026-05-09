using System.Text;
using Clawix.Secrets.Crypto;
using Clawix.Secrets.Models;
using Clawix.Secrets.Persistence;
using Microsoft.Data.Sqlite;

namespace Clawix.Secrets.Vault;

/// <summary>
/// High-level vault API. Holds the master key (derived from the user's
/// passphrase via Argon2id) in memory while unlocked, wraps each
/// secret's per-item AEAD key under the master key.
/// </summary>
public sealed class Vault : IDisposable
{
    private readonly Database _db;
    private byte[]? _masterKey;

    public Vault(string path) { _db = new Database(path); }

    public bool IsUnlocked => _masterKey is not null;

    public void Unlock(string passphrase, byte[] salt)
    {
        _masterKey = KeyDerivation.DeriveKey(passphrase, salt);
    }

    public void Lock()
    {
        if (_masterKey is not null) Array.Clear(_masterKey);
        _masterKey = null;
    }

    public void Add(string label, SecretKind kind, string value)
    {
        if (_masterKey is null) throw new InvalidOperationException("vault locked");
        var itemKey = Aead.RandomBytes(Aead.KeyLength);
        var nonce = Aead.RandomBytes(Aead.NonceLength);
        var wrapped = Aead.Encrypt(itemKey, nonce, Encoding.UTF8.GetBytes(value));
        var keyNonce = Aead.RandomBytes(Aead.NonceLength);
        var wrappedKey = Aead.Encrypt(_masterKey, keyNonce, itemKey);
        Array.Clear(itemKey);

        using var cmd = _db.Connection.CreateCommand();
        cmd.CommandText = "INSERT INTO secret (id,label,kind,createdAt,wrappedValue,nonce,wrappedKey) VALUES (@id,@label,@kind,@createdAt,@wv,@n,@wk)";
        cmd.Parameters.AddWithValue("@id", Guid.NewGuid().ToString());
        cmd.Parameters.AddWithValue("@label", label);
        cmd.Parameters.AddWithValue("@kind", kind.ToString());
        cmd.Parameters.AddWithValue("@createdAt", DateTimeOffset.UtcNow.ToString("O"));
        cmd.Parameters.AddWithValue("@wv", wrapped);
        cmd.Parameters.AddWithValue("@n", nonce);
        cmd.Parameters.AddWithValue("@wk", wrappedKey);
        cmd.ExecuteNonQuery();
    }

    public IReadOnlyList<Secret> List()
    {
        var list = new List<Secret>();
        using var cmd = _db.Connection.CreateCommand();
        cmd.CommandText = "SELECT id,label,kind,createdAt,wrappedValue,nonce,wrappedKey FROM secret ORDER BY label";
        using var r = cmd.ExecuteReader();
        while (r.Read())
        {
            list.Add(new Secret
            {
                Id = r.GetString(0),
                Label = r.GetString(1),
                Kind = Enum.Parse<SecretKind>(r.GetString(2)),
                CreatedAt = DateTimeOffset.Parse(r.GetString(3)),
                WrappedValue = (byte[])r.GetValue(4),
                Nonce = (byte[])r.GetValue(5),
                WrappedKey = (byte[])r.GetValue(6),
            });
        }
        return list;
    }

    public string Reveal(Secret secret)
    {
        if (_masterKey is null) throw new InvalidOperationException("vault locked");
        // Each secret wraps its own AEAD key under the master key.
        var keyNonce = secret.WrappedKey.AsSpan(0, Aead.NonceLength);
        // Layout: [nonce(12)][ciphertext+tag] when wrapping the item key.
        // To keep the stored shape simple we always store nonce inline at the
        // start of WrappedKey.
        var keyCipher = secret.WrappedKey.AsSpan(Aead.NonceLength);
        var itemKey = Aead.Decrypt(_masterKey, keyNonce, keyCipher);
        try
        {
            var plain = Aead.Decrypt(itemKey, secret.Nonce, secret.WrappedValue);
            return Encoding.UTF8.GetString(plain);
        }
        finally { Array.Clear(itemKey); }
    }

    public void Dispose()
    {
        Lock();
        _db.Dispose();
    }
}
