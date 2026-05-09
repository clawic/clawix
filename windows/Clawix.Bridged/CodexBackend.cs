using System.Diagnostics;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Logging;

namespace Clawix.Bridged;

/// <summary>
/// Thin wrapper over the Codex CLI subprocess. Speaks JSON-RPC over
/// stdout/stdin: one JSON object per line. Mirrors the Swift
/// <c>BackendClient</c>.
/// </summary>
public sealed class CodexBackend : IAsyncDisposable
{
    private readonly string _binaryPath;
    private readonly ILogger<CodexBackend> _logger;
    private Process? _process;
    private CancellationTokenSource? _cts;
    private Task? _readerLoop;
    private long _nextRequestId;
    private readonly SemaphoreSlim _writeGate = new(1, 1);
    private readonly Dictionary<long, TaskCompletionSource<JsonElement>> _pending = new();
    private readonly object _pendingLock = new();

    public event Action<string, JsonElement>? Notification;

    public CodexBackend(string binaryPath, ILogger<CodexBackend> logger)
    {
        _binaryPath = binaryPath;
        _logger = logger;
    }

    public bool IsRunning => _process is { HasExited: false };

    public Task StartAsync(CancellationToken ct = default)
    {
        var psi = new ProcessStartInfo
        {
            FileName = _binaryPath,
            Arguments = "rpc",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardInputEncoding = Encoding.UTF8,
        };
        psi.Environment["CODEX_HOME"] = Paths.CodexHome;
        _process = Process.Start(psi) ?? throw new InvalidOperationException("could not spawn codex");
        _cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        _readerLoop = Task.Run(() => ReadLoopAsync(_cts.Token), _cts.Token);
        _ = Task.Run(() => DrainErrAsync(_cts.Token));
        _logger.LogInformation("Codex backend started: {Path} (pid {Pid})", _binaryPath, _process.Id);
        return Task.CompletedTask;
    }

    public async Task<JsonElement> CallAsync(string method, object? @params, CancellationToken ct = default)
    {
        if (_process is null) throw new InvalidOperationException("backend not started");
        var id = Interlocked.Increment(ref _nextRequestId);
        var tcs = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
        lock (_pendingLock) _pending[id] = tcs;

        var payload = new
        {
            jsonrpc = "2.0",
            id,
            method,
            @params,
        };
        var line = JsonSerializer.Serialize(payload);
        await _writeGate.WaitAsync(ct);
        try
        {
            await _process.StandardInput.WriteLineAsync(line.AsMemory(), ct);
            await _process.StandardInput.FlushAsync(ct);
        }
        finally { _writeGate.Release(); }

        using var registration = ct.Register(() => tcs.TrySetCanceled(ct));
        return await tcs.Task;
    }

    public async Task NotifyAsync(string method, object? @params, CancellationToken ct = default)
    {
        if (_process is null) throw new InvalidOperationException("backend not started");
        var payload = new { jsonrpc = "2.0", method, @params };
        var line = JsonSerializer.Serialize(payload);
        await _writeGate.WaitAsync(ct);
        try
        {
            await _process.StandardInput.WriteLineAsync(line.AsMemory(), ct);
            await _process.StandardInput.FlushAsync(ct);
        }
        finally { _writeGate.Release(); }
    }

    private async Task ReadLoopAsync(CancellationToken ct)
    {
        try
        {
            string? line;
            while ((line = await _process!.StandardOutput.ReadLineAsync(ct)) is not null)
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                try { Dispatch(line); }
                catch (Exception ex) { _logger.LogWarning(ex, "bad backend line: {Line}", line); }
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { _logger.LogError(ex, "backend reader crashed"); }
    }

    private void Dispatch(string line)
    {
        using var doc = JsonDocument.Parse(line);
        var root = doc.RootElement;
        if (root.TryGetProperty("id", out var idProp) && idProp.ValueKind == JsonValueKind.Number)
        {
            var id = idProp.GetInt64();
            TaskCompletionSource<JsonElement>? tcs;
            lock (_pendingLock) _pending.Remove(id, out tcs);
            if (tcs is null) return;
            if (root.TryGetProperty("error", out var err))
                tcs.TrySetException(new InvalidOperationException(err.GetRawText()));
            else if (root.TryGetProperty("result", out var res))
                tcs.TrySetResult(res.Clone());
            else
                tcs.TrySetResult(default);
        }
        else if (root.TryGetProperty("method", out var methodProp))
        {
            var method = methodProp.GetString() ?? "";
            var p = root.TryGetProperty("params", out var pp) ? pp.Clone() : default;
            Notification?.Invoke(method, p);
        }
    }

    private async Task DrainErrAsync(CancellationToken ct)
    {
        if (_process is null) return;
        try
        {
            string? line;
            while ((line = await _process.StandardError.ReadLineAsync(ct)) is not null)
                _logger.LogDebug("[codex stderr] {Line}", line);
        }
        catch { /* ignored */ }
    }

    public async ValueTask DisposeAsync()
    {
        try { _cts?.Cancel(); } catch { }
        try
        {
            if (_process is { HasExited: false })
            {
                _process.StandardInput.Close();
                if (!_process.WaitForExit(2000)) _process.Kill(entireProcessTree: true);
            }
        }
        catch { }
        try { if (_readerLoop is not null) await _readerLoop; } catch { }
        _process?.Dispose();
        _cts?.Dispose();
    }
}
