package com.example.clawix.android

import com.example.clawix.android.core.BridgeBody
import com.example.clawix.android.core.BridgeCoder
import com.example.clawix.android.core.BridgeFrame
import com.example.clawix.android.core.BridgeJson
import com.example.clawix.android.core.BRIDGE_SCHEMA_VERSION
import com.example.clawix.android.core.ClientKind
import com.example.clawix.android.core.PairingPayload
import com.example.clawix.android.core.WireAttachment
import com.example.clawix.android.core.WireAttachmentKind
import com.example.clawix.android.core.WireSession
import com.example.clawix.android.core.WireMessage
import com.example.clawix.android.core.WireRole
import com.example.clawix.android.core.WireTimelineEntry
import com.example.clawix.android.core.WireWorkItem
import com.example.clawix.android.core.WireWorkItemStatus
import com.example.clawix.android.bridge.Credentials
import kotlinx.datetime.Instant
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Round-trip tests for every BridgeBody variant. Each test:
 *   1. encodes a Kotlin value to JSON
 *   2. decodes the JSON back
 *   3. checks structural equality
 *   4. for the inline-shape sanity test, also asserts the JSON has the
 *      flat envelope (`{ "schemaVersion": N, "type": "...", ...flat }`)
 */
class BridgeFrameRoundtripTest {

    private val parser = Json { isLenient = true; ignoreUnknownKeys = true }

    private fun roundtrip(body: BridgeBody) {
        val frame = BridgeFrame(body = body)
        val raw = BridgeCoder.encode(frame)
        val decoded = BridgeCoder.decode(raw)
        assertEquals("schemaVersion mismatch", BRIDGE_SCHEMA_VERSION, decoded.schemaVersion)
        assertEquals("body mismatch on $body", body, decoded.body)
    }

    private fun assertFlatEnvelope(raw: String, expectedType: String, expectedFlatKey: String) {
        val obj = parser.parseToJsonElement(raw).jsonObject
        assertEquals(BRIDGE_SCHEMA_VERSION, obj["schemaVersion"]?.jsonPrimitive?.content?.toInt())
        assertEquals(expectedType, obj["type"]?.jsonPrimitive?.content)
        assertNotNull("expected $expectedFlatKey at top level (no payload nesting)", obj[expectedFlatKey])
    }

    @Test fun auth_flat_envelope() {
        val raw = BridgeCoder.encode(
            BridgeFrame(body = BridgeBody.Auth("tok", "iPhone", ClientKind.COMPANION, "client-android", "install-android", "device-android"))
        )
        assertFlatEnvelope(raw, "auth", "token")
        assertTrue(raw.contains("\"deviceName\":\"iPhone\""))
        assertTrue(raw.contains("\"clientKind\":\"companion\""))
        assertTrue(raw.contains("\"clientId\":\"client-android\""))
        assertTrue(raw.contains("\"installationId\":\"install-android\""))
        assertTrue(raw.contains("\"deviceId\":\"device-android\""))
    }

    @Test fun roundtrip_outbound_v1() {
        roundtrip(BridgeBody.Auth("tok", "iPhone", ClientKind.COMPANION, "client-android", "install-android", "device-android"))
        roundtrip(BridgeBody.ListSessions)
        roundtrip(BridgeBody.OpenSession("chat-1", null))
        roundtrip(BridgeBody.OpenSession("chat-1", 60))
        roundtrip(BridgeBody.LoadOlderMessages("chat-1", "msg-x", 40))
        roundtrip(BridgeBody.SendMessage("chat-1", "hello", emptyList()))
        roundtrip(
            BridgeBody.SendMessage(
                "chat-1",
                "with image",
                listOf(WireAttachment("a-1", WireAttachmentKind.image, "image/jpeg", "x.jpg", "AAA="))
            )
        )
        roundtrip(BridgeBody.NewSession("c-x", "kick off", emptyList()))
        roundtrip(BridgeBody.InterruptTurn("chat-1"))
    }

    @Test fun roundtrip_inbound_v1() {
        roundtrip(BridgeBody.AuthOk("Studio Mac"))
        roundtrip(BridgeBody.AuthOk(null))
        roundtrip(BridgeBody.AuthFailed("bad token"))
        roundtrip(BridgeBody.VersionMismatch(99))
        roundtrip(
            BridgeBody.SessionsSnapshot(
                listOf(
                    WireSession(
                        id = "c-1",
                        title = "test",
                        createdAt = Instant.parse("2026-05-01T12:00:00Z"),
                    )
                )
            )
        )
        val msg = WireMessage(
            id = "m-1",
            role = WireRole.user,
            content = "hi",
            timestamp = Instant.parse("2026-05-01T12:00:00Z"),
        )
        roundtrip(BridgeBody.MessageAppended("c-1", msg))
        roundtrip(BridgeBody.MessageStreaming("c-1", "m-2", "partial", "thinking", false))
        roundtrip(BridgeBody.MessageStreaming("c-1", "m-2", "complete", "", true))
        roundtrip(BridgeBody.ErrorEvent("E_NET", "WebSocket closed"))
        roundtrip(
            BridgeBody.PairingPayload(
                """{"v":1,"host":"127.0.0.1","port":24080,"token":"tok","shortCode":"ABC-234-XYZ"}""",
                "tok",
                "ABC-234-XYZ",
            )
        )
        roundtrip(
            BridgeBody.MessagesSnapshot("c-1", listOf(msg), hasMore = false)
        )
        roundtrip(
            BridgeBody.MessagesPage("c-1", listOf(msg), hasMore = true)
        )
    }

    @Test fun roundtrip_session_management_v1() {
        roundtrip(BridgeBody.ArchiveSession("c-1"))
        roundtrip(BridgeBody.UnarchiveSession("c-1"))
        roundtrip(BridgeBody.PinSession("c-1"))
        roundtrip(BridgeBody.UnpinSession("c-1"))
        roundtrip(BridgeBody.RenameSession("c-1", "New title"))
        roundtrip(BridgeBody.RenameSession("c-1", ""))
    }

    @Test fun roundtrip_voice_v1() {
        roundtrip(BridgeBody.TranscribeAudio("req-1", "AAA=", "audio/m4a", "en"))
        roundtrip(BridgeBody.TranscribeAudio("req-1", "AAA=", "audio/m4a", null))
        roundtrip(BridgeBody.TranscriptionResult("req-1", "hello world", null))
        roundtrip(BridgeBody.TranscriptionResult("req-1", "", "decoder error"))
        roundtrip(BridgeBody.RequestAudio("a-1"))
        roundtrip(BridgeBody.AudioSnapshot("a-1", "AAA=", "audio/m4a", null))
        roundtrip(BridgeBody.AudioSnapshot("a-1", null, null, "not found"))
    }

    @Test fun roundtrip_images_v1() {
        roundtrip(BridgeBody.RequestGeneratedImage("/path/to/img.png"))
        roundtrip(BridgeBody.GeneratedImageSnapshot("/path/img.png", "BBB=", "image/png", null))
        roundtrip(BridgeBody.GeneratedImageSnapshot("/path/img.png", null, null, "denied"))
    }

    @Test fun roundtrip_bridge_state() {
        roundtrip(BridgeBody.BridgeStateFrame("ready", 12, null))
        roundtrip(BridgeBody.BridgeStateFrame("error", 0, "boot crashed"))
    }

    @Test fun pairing_payload_preserves_remote_route_fields() {
        val payload = PairingPayload.parse(
            """{"v":1,"host":"192.168.1.10","port":24080,"token":"tok","hostDisplayName":"Studio Mac","tailscaleHost":"100.64.1.2","shortCode":"ABC-234-XYZ","coordinatorUrl":"https://relay.example.com","irohNodeId":"node-1"}"""
        )
        assertNotNull(payload)
        assertEquals("https://relay.example.com", payload?.coordinatorUrl)
        assertEquals("node-1", payload?.irohNodeId)

        val credentials = Credentials.fromPairingPayload(payload!!)
        assertEquals("https://relay.example.com", credentials.coordinatorUrl)
        assertEquals("node-1", credentials.irohNodeId)
    }

    @Test fun roundtrip_timeline_and_work_summary() {
        val item = WireWorkItem(
            id = "w-1",
            kind = "command",
            status = WireWorkItemStatus.completed,
            commandText = "ls -la",
            commandActions = listOf("read"),
        )
        val timeline = listOf<WireTimelineEntry>(
            WireTimelineEntry.Reasoning("r-1", "thinking..."),
            WireTimelineEntry.Tools("t-1", listOf(item)),
            WireTimelineEntry.Message("m-1", "answer"),
        )
        val msg = WireMessage(
            id = "m-x",
            role = WireRole.assistant,
            content = "answer",
            timestamp = Instant.parse("2026-05-01T12:00:00Z"),
            timeline = timeline,
        )
        roundtrip(BridgeBody.MessageAppended("c-1", msg))
    }

    @Test fun unknown_frame_type_decodes_as_unknown() {
        val raw = """{"schemaVersion":1,"type":"futureFrame","extraField":42}"""
        val decoded = BridgeCoder.decode(raw)
        assertTrue(decoded.body is BridgeBody.Unknown)
        val unk = decoded.body as BridgeBody.Unknown
        assertEquals("futureFrame", unk.type)
    }

    @Test fun unknown_fields_in_known_type_are_ignored() {
        val raw = """{"schemaVersion":1,"type":"openSession","sessionId":"c-1","limit":60,"thisIsFromTheFuture":true}"""
        val decoded = BridgeCoder.decode(raw)
        assertEquals(BridgeBody.OpenSession("c-1", 60), decoded.body)
    }

    @Test fun open_session_omits_limit_when_null() {
        val raw = BridgeCoder.encode(BridgeFrame(body = BridgeBody.OpenSession("c-1", null)))
        assertTrue("expected no limit field, got $raw", !raw.contains("\"limit\""))
    }

    @Test fun sessions_snapshot_decodes_with_missing_optional_fields() {
        val raw = """
            {"schemaVersion":1,"type":"sessionsSnapshot",
             "sessions":[{"id":"c-1","title":"t","createdAt":"2026-05-01T12:00:00Z"}]}
        """.trimIndent()
        val decoded = BridgeCoder.decode(raw)
        val chats = (decoded.body as BridgeBody.SessionsSnapshot).sessions
        assertEquals(1, chats.size)
        val c = chats.first()
        assertEquals(false, c.isPinned)
        assertEquals(false, c.isArchived)
        assertEquals(false, c.lastTurnInterrupted)
    }
}
