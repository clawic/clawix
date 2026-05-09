using Microsoft.Data.Sqlite;

namespace Clawix.Secrets.Persistence;

/// <summary>
/// SQLite-backed vault store. Schema is binary-compatible with the
/// macOS GRDB store so vault files can be moved Mac &lt;-&gt; Windows.
/// </summary>
public sealed class Database : IDisposable
{
    private readonly SqliteConnection _conn;

    public Database(string path)
    {
        var dir = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
        _conn = new SqliteConnection($"Data Source={path};Mode=ReadWriteCreate;Pooling=False");
        _conn.Open();
        Migrate();
    }

    private void Migrate()
    {
        using var cmd = _conn.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS secret (
                id TEXT PRIMARY KEY,
                label TEXT NOT NULL,
                kind TEXT NOT NULL,
                createdAt TEXT NOT NULL,
                wrappedValue BLOB NOT NULL,
                nonce BLOB NOT NULL,
                wrappedKey BLOB NOT NULL
            );
            CREATE TABLE IF NOT EXISTS vault_meta (
                key TEXT PRIMARY KEY,
                value BLOB NOT NULL
            );
        """;
        cmd.ExecuteNonQuery();
    }

    public SqliteConnection Connection => _conn;

    public void Dispose() => _conn.Dispose();
}
