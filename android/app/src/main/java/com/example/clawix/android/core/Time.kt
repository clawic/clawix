package com.example.clawix.android.core

import kotlinx.datetime.Instant
import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** Type-alias so existing callers can use `Instant` without an explicit
 *  kotlinx-datetime import each time. Internal to the core module. */
typealias Instant = kotlinx.datetime.Instant

/** ISO-8601 string serializer matching Swift's
 *  `JSONEncoder.dateEncodingStrategy = .iso8601`. Swift omits fractional
 *  seconds by default; `Instant.toString()` does the same. Decoder is
 *  tolerant: accepts both with and without fractions, and either `Z` or
 *  numeric offset.
 */
object IsoDateSerializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("kotlinx.datetime.Instant", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant) {
        encoder.encodeString(value.toString())
    }

    override fun deserialize(decoder: Decoder): Instant =
        Instant.parse(decoder.decodeString())
}

/** Optional variant. The default `@Serializable Instant?` field already
 *  handles null at the property level, but we want a tolerant decoder:
 *  some legacy frames sent `""` for absent dates. We map empty strings
 *  to null so the field still decodes. */
object OptionalIsoDateSerializer : KSerializer<Instant?> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("kotlinx.datetime.Instant?", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant?) {
        if (value == null) encoder.encodeString("")
        else encoder.encodeString(value.toString())
    }

    override fun deserialize(decoder: Decoder): Instant? {
        val raw = decoder.decodeString()
        if (raw.isEmpty()) return null
        return Instant.parse(raw)
    }
}
