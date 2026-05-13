using System.Text.Json;
using Clawix.Core;
using Clawix.Core.Models;
using Clawix.Engine;
using Microsoft.Extensions.Logging;

namespace Clawix.Bridged;

public sealed partial class DaemonEngineHost
{
    private static List<WireChat> ChatSnapshotFromBackend(JsonElement el)
    {
        var list = new List<WireChat>();
        if (el.ValueKind != JsonValueKind.Array) return list;
        foreach (var item in el.EnumerateArray())
        {
            list.Add(new WireChat
            {
                Id = item.TryGetProperty("id", out var id) ? id.GetString() ?? Guid.NewGuid().ToString() : Guid.NewGuid().ToString(),
                Title = item.TryGetProperty("title", out var t) ? (t.GetString() ?? "Untitled") : "Untitled",
                CreatedAt = item.TryGetProperty("createdAt", out var c) && c.ValueKind == JsonValueKind.String
                    ? DateTimeOffset.Parse(c.GetString()!) : DateTimeOffset.UtcNow,
                LastMessagePreview = item.TryGetProperty("preview", out var p) ? p.GetString() : null,
                ThreadId = item.TryGetProperty("threadId", out var th) ? th.GetString() : null,
            });
        }
        return list;
    }

    private void OnBackendNotification(string method, JsonElement @params)
    {
        switch (method)
        {
            case "thread/list/changed":
                _ = RefreshSessionsAsync(CancellationToken.None);
                break;
            case "thread/messageStreaming":
                if (TryReadStreaming(@params, out var ev)) MessagesChanged?.Invoke(ev);
                break;
            case "thread/messageAppended":
                if (TryReadAppended(@params, out var ap)) MessagesChanged?.Invoke(ap);
                break;
            case "account/rateLimits/updated":
                ApplyRateLimits(@params);
                break;
        }
    }

    private static bool TryReadStreaming(JsonElement el, out MessagesEvent ev)
    {
        ev = default!;
        if (!el.TryGetProperty("sessionId", out var cid)) return false;
        ev = new MessagesEvent.Streaming
        {
            SessionId = cid.GetString() ?? "",
            MessageId = el.TryGetProperty("messageId", out var m) ? m.GetString() ?? "" : "",
            Content = el.TryGetProperty("content", out var c) ? c.GetString() ?? "" : "",
            ReasoningText = el.TryGetProperty("reasoningText", out var r) ? r.GetString() ?? "" : "",
            Finished = el.TryGetProperty("finished", out var f) && f.GetBoolean(),
        };
        return true;
    }

    private static bool TryReadAppended(JsonElement el, out MessagesEvent ev)
    {
        ev = default!;
        if (!el.TryGetProperty("sessionId", out var cid)) return false;
        if (!el.TryGetProperty("message", out var msg)) return false;
        var wm = JsonSerializer.Deserialize<WireMessage>(msg.GetRawText(), BridgeCoder.Options);
        if (wm is null) return false;
        ev = new MessagesEvent.Appended { SessionId = cid.GetString() ?? "", Message = wm };
        return true;
    }

    private void ApplyRateLimits(JsonElement el)
    {
        try
        {
            var snapshot = el.TryGetProperty("snapshot", out var s)
                ? JsonSerializer.Deserialize<WireRateLimitSnapshot>(s.GetRawText(), BridgeCoder.Options)
                : null;
            var by = el.TryGetProperty("byLimitId", out var b)
                ? JsonSerializer.Deserialize<Dictionary<string, WireRateLimitSnapshot>>(b.GetRawText(), BridgeCoder.Options)
                : null;
            var pair = (snapshot, (IReadOnlyDictionary<string, WireRateLimitSnapshot>)(by ?? new()));
            lock (_stateLock) _rateLimits = pair;
            RateLimitsChanged?.Invoke(pair);
        }
        catch (Exception ex) { _logger.LogWarning(ex, "rate limits apply failed"); }
    }
}
