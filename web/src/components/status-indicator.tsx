/**
 * Persistent connection status, replaces the macOS menu-bar item. Sits in
 * the chrome and reacts to the BridgeClient state.
 */
import { useEffect, useState } from "react";
import { useBridgeStore } from "../bridge/store";

const labels = {
  idle: "Idle",
  connecting: "Connecting",
  authenticating: "Authenticating",
  ready: "Connected",
  "auth-failed": "Auth failed",
  "version-mismatch": "Update required",
  offline: "Reconnecting",
} as const;

export function StatusIndicator() {
  const conn = useBridgeStore((s) => s.connection);
  const hostDisplayName = useBridgeStore((s) => s.hostDisplayName);
  const bridge = useBridgeStore((s) => s.bridge);
  const [now, setNow] = useState(Date.now());

  useEffect(() => {
    if (conn.kind !== "offline") return;
    const id = setInterval(() => setNow(Date.now()), 500);
    return () => clearInterval(id);
  }, [conn.kind]);

  const ready = conn.kind === "ready";
  const dotColor =
    conn.kind === "ready"
      ? "bg-[var(--color-banner-ok-fg)]"
      : conn.kind === "auth-failed" || conn.kind === "version-mismatch"
        ? "bg-[var(--color-destructive)]"
        : "bg-[var(--color-banner-danger-fg)]";

  let detail = "";
  if (conn.kind === "ready" && hostDisplayName) detail = ` ${hostDisplayName}`;
  if (conn.kind === "offline") {
    const remaining = Math.max(0, conn.retryAt - now);
    detail = ` in ${Math.ceil(remaining / 1000)}s`;
  }
  if (conn.kind === "version-mismatch") detail = ` (server v${conn.serverVersion})`;

  return (
    <div className="flex items-center gap-2 text-[12px] text-[var(--color-fg-secondary)] select-none">
      <span className={`inline-block size-2 rounded-full ${dotColor} ${ready ? "" : "animate-pulse"}`} />
      <span>
        {labels[conn.kind]}
        {detail}
      </span>
      {ready && bridge.state !== "ready" && (
        <span className="text-[11px] text-[var(--color-fg-tertiary)]">· {bridge.state}</span>
      )}
    </div>
  );
}
