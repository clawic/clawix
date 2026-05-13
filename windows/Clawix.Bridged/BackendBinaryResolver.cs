namespace Clawix.Bridged;

/// <summary>
/// Locate the Codex CLI binary on Windows. Mirrors the Swift
/// <c>BackendBinary.candidatePaths()</c> logic but in Windows-y
/// search paths.
/// </summary>
public static class BackendBinaryResolver
{
    public static string? Resolve()
    {
        var overridePath = Environment.GetEnvironmentVariable("CLAWIX_BRIDGE_BACKEND_PATH");
        if (!string.IsNullOrEmpty(overridePath) && File.Exists(overridePath)) return overridePath;

        foreach (var candidate in CandidatePaths())
        {
            if (File.Exists(candidate)) return candidate;
        }

        var fromPath = ResolveFromPath();
        return fromPath;
    }

    public static IEnumerable<string> CandidatePaths()
    {
        var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

        // npm global install (default Windows location)
        yield return Path.Combine(appData, "npm", "codex.cmd");
        yield return Path.Combine(appData, "npm", "codex.exe");

        // pnpm global
        yield return Path.Combine(localAppData, "pnpm", "codex.cmd");

        // nvm-windows
        var nvmRoot = Path.Combine(localAppData, "nvm");
        if (Directory.Exists(nvmRoot))
        {
            foreach (var ver in Directory.EnumerateDirectories(nvmRoot, "v*").OrderDescending())
            {
                yield return Path.Combine(ver, "codex.cmd");
                yield return Path.Combine(ver, "codex.exe");
            }
        }

        // volta
        yield return Path.Combine(localAppData, "Volta", "bin", "codex.exe");
    }

    private static string? ResolveFromPath()
    {
        var path = Environment.GetEnvironmentVariable("PATH");
        if (string.IsNullOrEmpty(path)) return null;
        var exts = (Environment.GetEnvironmentVariable("PATHEXT") ?? ".COM;.EXE;.BAT;.CMD")
            .Split(';', StringSplitOptions.RemoveEmptyEntries);
        foreach (var dir in path.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            foreach (var ext in exts)
            {
                var candidate = Path.Combine(dir, "codex" + ext);
                if (File.Exists(candidate)) return candidate;
            }
        }
        return null;
    }
}
