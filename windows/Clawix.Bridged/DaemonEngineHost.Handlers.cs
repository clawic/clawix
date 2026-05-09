using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;

namespace Clawix.Bridged;

public sealed partial class DaemonEngineHost
{
    public async Task HandleSendPromptAsync(string chatId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/prompt", new { chatId, text, attachments }, ct);
    }

    public async Task HandleNewChatAsync(string chatId, string text, IReadOnlyList<WireAttachment> attachments, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/start", new { chatId, text, attachments }, ct);
    }

    public async Task HandleInterruptTurnAsync(string chatId, CancellationToken ct)
    {
        await _backend.NotifyAsync("thread/interrupt", new { chatId }, ct);
    }

    public async Task<IReadOnlyList<WireMessage>> HandleOpenChatAsync(string chatId, int? limit, CancellationToken ct)
    {
        var res = await _backend.CallAsync("thread/messages", new { chatId, limit }, ct);
        return JsonSerializer.Deserialize<List<WireMessage>>(res.GetRawText(), BridgeCoder.Options) ?? [];
    }

    public async Task<(IReadOnlyList<WireMessage> Messages, bool HasMore)> HandleLoadOlderMessagesAsync(string chatId, string beforeMessageId, int limit, CancellationToken ct)
    {
        var res = await _backend.CallAsync("thread/messagesPage", new { chatId, beforeMessageId, limit }, ct);
        var msgs = res.TryGetProperty("messages", out var m)
            ? JsonSerializer.Deserialize<List<WireMessage>>(m.GetRawText(), BridgeCoder.Options) ?? []
            : new List<WireMessage>();
        var hasMore = res.TryGetProperty("hasMore", out var h) && h.GetBoolean();
        return (msgs, hasMore);
    }

    public Task HandleEditPromptAsync(string chatId, string messageId, string text, CancellationToken ct)
        => _backend.NotifyAsync("thread/editPrompt", new { chatId, messageId, text }, ct);

    public Task HandleArchiveAsync(string chatId, bool archived, CancellationToken ct)
        => _backend.NotifyAsync(archived ? "thread/archive" : "thread/unarchive", new { chatId }, ct);

    public Task HandlePinAsync(string chatId, bool pinned, CancellationToken ct)
        => _backend.NotifyAsync(pinned ? "thread/pin" : "thread/unpin", new { chatId }, ct);

    public Task HandleRenameAsync(string chatId, string title, CancellationToken ct)
        => _backend.NotifyAsync("thread/name/set", new { chatId, title }, ct);

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
