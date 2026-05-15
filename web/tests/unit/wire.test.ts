/**
 * Vitest unit tests for the wire codec. Pins the JSON shape of every frame
 * so a Swift-side change (or a TS-side typo) shows up as a red dot here.
 */
import { describe, it, expect } from "vitest";
import { decodeFrame, encodeFrame, peekSchemaVersion, BRIDGE_SCHEMA_VERSION, type FrameBody } from "../../src/bridge/frames";

describe("frames", () => {
  it("roundtrips an auth frame", () => {
    const body: FrameBody = {
      type: "auth",
      token: "abc",
      deviceName: "Web",
      clientKind: "companion",
    };
    const raw = encodeFrame(body);
    const back = decodeFrame(raw);
    expect(back).toMatchObject({
      type: "auth",
      token: "abc",
      deviceName: "Web",
      clientKind: "companion",
      schemaVersion: BRIDGE_SCHEMA_VERSION,
    });
  });

  it("decodes an authOk frame from the daemon", () => {
    const raw = JSON.stringify({ schemaVersion: BRIDGE_SCHEMA_VERSION, type: "authOk", hostDisplayName: "Mac" });
    expect(decodeFrame(raw)).toMatchObject({ type: "authOk", hostDisplayName: "Mac" });
  });

  it("decodes a sessionsSnapshot with empty array", () => {
    const raw = JSON.stringify({ schemaVersion: BRIDGE_SCHEMA_VERSION, type: "sessionsSnapshot", sessions: [] });
    expect(decodeFrame(raw)).toMatchObject({ type: "sessionsSnapshot", sessions: [] });
  });

  it("decodes a messagesSnapshot with messages", () => {
    const raw = JSON.stringify({
      schemaVersion: BRIDGE_SCHEMA_VERSION,
      type: "messagesSnapshot",
      sessionId: "c1",
      messages: [
        {
          id: "m1",
          role: "user",
          content: "hi",
          timestamp: "2026-05-09T00:00:00.000Z",
        },
      ],
    });
    const back = decodeFrame(raw);
    expect(back?.type).toBe("messagesSnapshot");
    if (back?.type === "messagesSnapshot") {
      expect(back.messages.length).toBe(1);
      expect(back.messages[0]?.content).toBe("hi");
    }
  });

  it("returns null on unknown frame types (forward-compat)", () => {
    const raw = JSON.stringify({ schemaVersion: 99, type: "futureFrame", foo: "bar" });
    expect(decodeFrame(raw)).toBeNull();
  });

  it("peeks the schema version without parsing", () => {
    const raw = JSON.stringify({ schemaVersion: 6, type: "ping" });
    expect(peekSchemaVersion(raw)).toBe(6);
  });
});
