using System.Reflection;
using System.Runtime.Serialization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Clawix.Core;

internal sealed class BridgeEnumJsonConverter<TEnum> : JsonConverter<TEnum> where TEnum : struct, Enum
{
    private static readonly IReadOnlyDictionary<string, TEnum> NameToValue = BuildNameToValue();
    private static readonly IReadOnlyDictionary<TEnum, string> ValueToName = BuildValueToName();

    public override TEnum Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        var name = reader.GetString();
        if (name is not null && NameToValue.TryGetValue(name, out var value))
        {
            return value;
        }

        throw new JsonException($"Unknown {typeof(TEnum).Name} value '{name}'");
    }

    public override void Write(Utf8JsonWriter writer, TEnum value, JsonSerializerOptions options)
    {
        if (!ValueToName.TryGetValue(value, out var name))
        {
            throw new JsonException($"Unknown {typeof(TEnum).Name} value '{value}'");
        }

        writer.WriteStringValue(name);
    }

    private static IReadOnlyDictionary<string, TEnum> BuildNameToValue()
    {
        return EnumFields().ToDictionary(static item => item.name, static item => item.value, StringComparer.Ordinal);
    }

    private static IReadOnlyDictionary<TEnum, string> BuildValueToName()
    {
        return EnumFields().ToDictionary(static item => item.value, static item => item.name);
    }

    private static IEnumerable<(string name, TEnum value)> EnumFields()
    {
        foreach (var field in typeof(TEnum).GetFields(BindingFlags.Public | BindingFlags.Static))
        {
            var name = field.GetCustomAttribute<EnumMemberAttribute>()?.Value ?? field.Name;
            var value = (TEnum)field.GetValue(null)!;
            yield return (name, value);
        }
    }
}
