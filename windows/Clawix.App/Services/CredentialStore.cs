using Windows.Security.Credentials;

namespace Clawix.App.Services;

/// <summary>
/// Keychain-equivalent. Wraps the Windows <c>PasswordVault</c> (not the
/// older <c>cmdkey</c> Credential Manager). Used for the secrets vault
/// master key, enhancement API tokens, etc.
/// </summary>
public sealed class CredentialStore
{
    private const string ResourceName = "Clawix";
    private readonly PasswordVault _vault = new();

    public string? Read(string key)
    {
        try
        {
            var cred = _vault.Retrieve(ResourceName, key);
            cred.RetrievePassword();
            return cred.Password;
        }
        catch
        {
            return null;
        }
    }

    public void Write(string key, string secret)
    {
        Delete(key);
        _vault.Add(new PasswordCredential(ResourceName, key, secret));
    }

    public void Delete(string key)
    {
        try
        {
            var cred = _vault.Retrieve(ResourceName, key);
            _vault.Remove(cred);
        }
        catch { /* ignore: nothing to delete */ }
    }
}
