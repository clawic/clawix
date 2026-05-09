using System.Text.Json;
using System.Text.Json.Serialization;

namespace Clawix.Core.Models;

[JsonConverter(typeof(WireTimelineEntryConverter))]
public abstract record WireTimelineEntry
{
    public required string Id { get; init; }

    public sealed record Reasoning : WireTimelineEntry
    {
        public required string Text { get; init; }
    }

    public sealed record Message : WireTimelineEntry
    {
        public required string Text { get; init; }
    }

    public sealed record Tools : WireTimelineEntry
    {
        public required List<WireWorkItem> Items { get; init; }
    }
}

internal sealed class WireTimelineEntryConverter : JsonConverter<WireTimelineEntry>
{
    public override WireTimelineEntry Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var doc = JsonDocument.ParseValue(ref reader);
        var root = doc.RootElement;
        var type = root.GetProperty("type").GetString()
            ?? throw new JsonException("timeline entry missing 'type'");
        var id = root.GetProperty("id").GetString()
            ?? throw new JsonException("timeline entry missing 'id'");

        return type switch
        {
            "reasoning" => new WireTimelineEntry.Reasoning
            {
                Id = id,
                Text = root.GetProperty("text").GetString() ?? string.Empty,
            },
            "message" => new WireTimelineEntry.Message
            {
                Id = id,
                Text = root.GetProperty("text").GetString() ?? string.Empty,
            },
            "tools" => new WireTimelineEntry.Tools
            {
                Id = id,
                Items = JsonSerializer.Deserialize<List<WireWorkItem>>(
                    root.GetProperty("items").GetRawText(), options) ?? [],
            },
            _ => throw new JsonException($"unknown timeline type: {type}"),
        };
    }

    public override void Write(Utf8JsonWriter writer, WireTimelineEntry value, JsonSerializerOptions options)
    {
        writer.WriteStartObject();
        switch (value)
        {
            case WireTimelineEntry.Reasoning r:
                writer.WriteString("type", "reasoning");
                writer.WriteString("id", r.Id);
                writer.WriteString("text", r.Text);
                break;
            case WireTimelineEntry.Message m:
                writer.WriteString("type", "message");
                writer.WriteString("id", m.Id);
                writer.WriteString("text", m.Text);
                break;
            case WireTimelineEntry.Tools t:
                writer.WriteString("type", "tools");
                writer.WriteString("id", t.Id);
                writer.WritePropertyName("items");
                JsonSerializer.Serialize(writer, t.Items, options);
                break;
            default:
                throw new JsonException($"unknown timeline entry: {value.GetType()}");
        }
        writer.WriteEndObject();
    }
}
