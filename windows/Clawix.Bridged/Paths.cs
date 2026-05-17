namespace Clawix.Bridged;

public static class Paths
{
    public static string UserProfile => EnvPath("CLAWIX_USER_PROFILE", Environment.SpecialFolder.UserProfile);
    public static string AppData => EnvPath("CLAWIX_APP_DATA", Environment.SpecialFolder.ApplicationData);
    public static string LocalAppData => EnvPath("CLAWIX_LOCAL_APP_DATA", Environment.SpecialFolder.LocalApplicationData);

    public static string ClawixState => Path.Combine(UserProfile, ".clawix", "state");
    public static string BridgeStatusPath => Path.Combine(ClawixState, "bridge-status.json");

    public static string CodexHome
    {
        get
        {
            var overrideHome = Environment.GetEnvironmentVariable("CLAWIX_BACKEND_HOME");
            return string.IsNullOrEmpty(overrideHome) ? Path.Combine(UserProfile, ".codex") : overrideHome;
        }
    }

    public static string CodexGlobalState => Path.Combine(CodexHome, ".codex-global-state.json");
    public static string CodexSessions => Path.Combine(CodexHome, "sessions");
    public static string CodexGeneratedImages => Path.Combine(CodexHome, "generated_images");

    public static string ClawixAppData => Path.Combine(AppData, "Clawix");
    public static string ClawixLocalAppData => Path.Combine(LocalAppData, "Clawix");
    public static string ClawixLogs => Path.Combine(ClawixLocalAppData, "logs");

    public static void EnsureDirectories()
    {
        Directory.CreateDirectory(ClawixState);
        Directory.CreateDirectory(ClawixAppData);
        Directory.CreateDirectory(ClawixLocalAppData);
        Directory.CreateDirectory(ClawixLogs);
    }

    private static string EnvPath(string name, Environment.SpecialFolder fallback)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value) ? Environment.GetFolderPath(fallback) : value;
    }
}
