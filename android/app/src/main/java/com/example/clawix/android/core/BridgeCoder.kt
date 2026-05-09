package com.example.clawix.android.core

import kotlinx.serialization.json.Json

/**
 * Singleton JSON instance with the same toggles `BridgeCoder` uses on
 * iOS:
 *   - dates are ISO-8601 strings (we encode/decode them manually via
 *     `IsoDateSerializer`)
 *   - extra unknown fields are tolerated so older clients can talk to
 *     newer daemons gracefully
 *   - `encodeDefaults = false` so optional nullables that hold their
 *     default (`null`/`false`/`""`) don't bloat outbound frames. iOS uses
 *     `encodeIfPresent` for the same effect.
 *   - lenient parsing because some daemon code paths used to emit
 *     numeric strings inside int fields (we tolerate them while phasing
 *     out)
 */
object BridgeJson {
    val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = false
        coerceInputValues = true
        prettyPrint = false
        explicitNulls = false
    }

    fun <T> encodeToString(serializer: kotlinx.serialization.KSerializer<T>, value: T): String =
        json.encodeToString(serializer, value)

    fun <T> decodeFromString(serializer: kotlinx.serialization.KSerializer<T>, raw: String): T =
        json.decodeFromString(serializer, raw)

    fun <T> encodeToJsonElement(serializer: kotlinx.serialization.KSerializer<T>, value: T): kotlinx.serialization.json.JsonElement =
        json.encodeToJsonElement(serializer, value)

    fun <T> decodeFromJsonElement(serializer: kotlinx.serialization.KSerializer<T>, element: kotlinx.serialization.json.JsonElement): T =
        json.decodeFromJsonElement(serializer, element)
}

object BridgeCoder {
    fun encode(frame: BridgeFrame): String =
        BridgeJson.encodeToString(BridgeFrameSerializer, frame)

    fun decode(raw: String): BridgeFrame =
        BridgeJson.decodeFromString(BridgeFrameSerializer, raw)
}
