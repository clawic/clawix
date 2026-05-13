using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;

namespace Clawix.Bridged;

public sealed partial class DaemonEngineHost
{
    public async Task HandleSendPromptAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/prompt", new { sessionId, text, attachments }, ct);
    }

    public async Task HandleNewSessionAsync(string sessionId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/start", new { sessionId, text, attachments }, ct);
    }

    public async Task HandleInterruptTurnAsync(string sessionId, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/interrupt", new { sessionId }, ct);
    }

    public async Task<IReadOnlyList<WireMessage>> HandleOpenSessionAsync(string sessionId, int? limit, CancellationToken ct)
    {
        var res = await _backend.CallAsync("thread/messages", new { sessionId, limit }, ct);
        return JsonSerializer.Deserialize<List<WireMessage>>(res.GetRawText(), BridgeCoder.Options) ?? [];
    }

    public async Task<(IReadOnlyList<WireMessage> Messages, bool HasMore)> HandleLoadOlderMessagesAsync(string sessionId, string beforeMessageId, int limit, CancellationToken ct)
    {
        var res = await _backend.CallAsync("thread/messagesPage", new { sessionId, beforeMessageId, limit }, ct);
        var msgs = res.TryGetProperty("messages", out var m)
            ? JsonSerializer.Deserialize<List<WireMessage>>(m.GetRawText(), BridgeCoder.Options) ?? []
            : new List<WireMessage>();
        var hasMore = res.TryGetProperty("hasMore", out var h) && h.GetBoolean();
        return (msgs, hasMore);
    }

    public Task HandleEditPromptAsync(string sessionId, string messageId, string text, CancellationToken ct)
        => _backend.NotifyAsync("thread/editPrompt", new { sessionId, messageId, text }, ct);

    public Task HandleArchiveAsync(string sessionId, bool archived, CancellationToken ct)
        => _backend.NotifyAsync(archived ? "thread/archive" : "thread/unarchive", new { sessionId }, ct);

    public Task HandlePinAsync(string sessionId, bool pinned, CancellationToken ct)
        => _backend.NotifyAsync(pinned ? "thread/pin" : "thread/unpin", new { sessionId }, ct);

    public Task HandleRenameAsync(string sessionId, string title, CancellationToken ct)
        => _backend.NotifyAsync("thread/name/set", new { sessionId, title }, ct);

    public async Task<IReadOnlyList<WireProject>> HandleListProjectsAsync(CancellationToken ct)
    {
        var res = await _backend.CallAsync("project/list", null, ct);
        return JsonSerializer.Deserialize<List<WireProject>>(res.GetRawText(), BridgeCoder.Options) ?? [];
    }

    public Task<(string? Content, bool IsMarkdown, string? Error)> HandleReadFileAsync(string path, CancellationToken ct)
    {
        try
        {
            if (!File.Exists(path)) return Task.FromResult<(string?, bool, string?)>((null, false, "File not found"));
            var text = File.ReadAllText(path);
            var isMd = path.EndsWith(".md", StringComparison.OrdinalIgnoreCase);
            return Task.FromResult<(string?, bool, string?)>((text, isMd, null));
        }
        catch (Exception ex)
        {
            return Task.FromResult<(string?, bool, string?)>((null, false, ex.Message));
        }
    }

    public Task<(string? Text, string? Error)> HandleTranscribeAudioAsync(string audioBase64, string mimeType, string? language, CancellationToken ct)
    {
        return Task.FromResult<(string?, string?)>((null, "Transcription not yet available on Windows"));
    }

    public Task<(string? AudioBase64, string? MimeType, string? Error)> HandleRequestAudioAsync(string audioId, CancellationToken ct)
        => Task.FromResult<(string?, string?, string?)>((null, null, "Audio storage not yet available on Windows"));

    public Task<(string? DataBase64, string? MimeType, string? Error)> HandleRequestGeneratedImageAsync(string path, CancellationToken ct)
    {
        try
        {
            var root = Path.GetFullPath(Paths.CodexGeneratedImages);
            var full = Path.GetFullPath(path);
            if (!full.StartsWith(root, StringComparison.OrdinalIgnoreCase))
                return Task.FromResult<(string?, string?, string?)>((null, null, "denied"));
            if (!File.Exists(full))
                return Task.FromResult<(string?, string?, string?)>((null, null, "File not found"));
            var bytes = File.ReadAllBytes(full);
            var mime = full.EndsWith(".png", StringComparison.OrdinalIgnoreCase) ? "image/png" : "application/octet-stream";
            return Task.FromResult<(string?, string?, string?)>((Convert.ToBase64String(bytes), mime, null));
        }
        catch (Exception ex)
        {
            return Task.FromResult<(string?, string?, string?)>((null, null, ex.Message));
        }
    }
}
