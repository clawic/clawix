import { describe, it, expect } from "vitest";
import { useBridgeStore } from "../../src/bridge/store";

describe("bridge store", () => {
  it("starts in idle state", () => {
    const s = useBridgeStore.getState();
    expect(s.connection.kind).toBe("idle");
    expect(s.chats).toEqual([]);
    expect(s.hostDisplayName).toBeNull();
  });
});
