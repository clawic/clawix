package com.example.clawix.android.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

object BridgeFrameSerializer : KSerializer<BridgeFrame> {
    override val descriptor: SerialDescriptor = buildClassSerialDescriptor("BridgeFrame")

    override fun serialize(encoder: Encoder, value: BridgeFrame) {
        require(encoder is JsonEncoder) { "BridgeFrameSerializer requires a JSON encoder" }
        val obj = buildJsonObject {
            put("schemaVersion", value.schemaVersion)
            put("type", value.body.typeTag)
            encodePayload(value.body, this)
        }
        encoder.encodeJsonElement(obj)
    }

    override fun deserialize(decoder: Decoder): BridgeFrame {
        require(decoder is JsonDecoder) { "BridgeFrameSerializer requires a JSON decoder" }
        val obj = decoder.decodeJsonElement().jsonObject
        val schemaVersion = obj["schemaVersion"]?.jsonPrimitive?.content?.toInt()
            ?: error("BridgeFrame missing schemaVersion")
        val type = obj["type"]?.jsonPrimitive?.content
            ?: error("BridgeFrame missing type")
        val body = decodePayload(type, obj)
        return BridgeFrame(schemaVersion, body)
    }
}
