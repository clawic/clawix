/**
 * App shell. Decides between the pairing onboarding and the main UI based
 * on the connection state, and self-restores any persisted bearer token
 * on first load.
 */
import { useEffect } from "react";
import { useBridgeStore } from "./bridge/store";
import { storage, StorageKeys } from "./lib/storage";
import { PairingScreen } from "./screens/pairing/pairing-screen";
import { MainShell } from "./screens/shell/main-shell";
import { ToastHost } from "./components/ui/toast-center";

export function App() {
  const conn = useBridgeStore((s) => s.connection);
  const attach = useBridgeStore((s) => s.attach);

  useEffect(() => {
    if (conn.kind !== "idle") return;
    const token = storage.get<string>(StorageKeys.bearer);
    if (token) attach(token);
  }, [conn.kind, attach]);

  const showShell =
    conn.kind === "ready" || conn.kind === "offline" || conn.kind === "version-mismatch";

  return (
    <div className="h-full">
      {showShell ? <MainShell /> : <PairingScreen />}
      <ToastHost />
    </div>
  );
}
