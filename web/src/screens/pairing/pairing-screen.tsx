// Pairing screen. Loopback auto-pair, or user pastes the short code from
// the Mac. Uses the new design system: ClawixLogoIcon brand mark, Card,
// Button, TextField.
import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { useBridgeStore } from "../../bridge/store";
import { ZQrPayload, normaliseShortCode } from "../../bridge/frames";
import { storage, StorageKeys } from "../../lib/storage";
import { Button, TextField, Card } from "../../components/ui";
import { ClawixLogoIcon } from "../../icons";

export function PairingScreen() {
  const attach = useBridgeStore((s) => s.attach);
  const conn = useBridgeStore((s) => s.connection);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [autoTried, setAutoTried] = useState(false);

  useEffect(() => {
    if (autoTried) return;
    setAutoTried(true);
    fetch("/pairing/qr.json", { credentials: "omit" })
      .then(async (r) => {
        if (!r.ok) throw new Error(`status ${r.status}`);
        const data = await r.json();
        const parsed = ZQrPayload.safeParse(data);
        if (!parsed.success) throw new Error("malformed qr.json");
        const token = parsed.data.token;
        storage.set(StorageKeys.bearer, token);
        attach(token);
      })
      .catch(() => {
        // Remote host: user must paste the short code.
      });
  }, [attach, autoTried]);

  useEffect(() => {
    if (conn.kind === "auth-failed") setError(conn.reason);
    if (conn.kind === "ready") setError(null);
  }, [conn]);

  function submit(ev: React.FormEvent) {
    ev.preventDefault();
    const normalised = normaliseShortCode(code);
    if (normalised.replace(/-/g, "").length < 9) {
      setError("Short code must be 9 letters/digits");
      return;
    }
    setError(null);
    storage.set(StorageKeys.bearer, normalised);
    attach(normalised);
  }

  const connecting = conn.kind === "connecting" || conn.kind === "authenticating";

  return (
    <div className="min-h-full flex items-center justify-center px-6 py-16 sidebar-backdrop">
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.32, ease: [0, 0, 0.2, 1] }}
        className="w-full max-w-[440px]"
      >
        <div className="flex items-center gap-3 mb-7">
          <ClawixLogoIcon size={40} color="var(--color-fg)" />
          <div>
            <div
              style={{
                fontSize: 18,
                fontVariationSettings: '"wght" 800',
                letterSpacing: "-0.02em",
              }}
            >
              Clawix Web
            </div>
            <div style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>
              Pair with your Mac to start
            </div>
          </div>
        </div>

        <p
          className="mb-6"
          style={{ fontSize: 13, color: "var(--color-fg-secondary)", lineHeight: 1.55 }}
        >
          Open Clawix on your Mac, enable the background bridge in Settings, and copy the short
          code. Or just open this page from{" "}
          <code className="font-mono" style={{ fontSize: 12, color: "var(--color-fg)" }}>
            localhost:24080
          </code>{" "}
          and we will pair automatically.
        </p>

        <Card>
          <form onSubmit={submit} className="p-4 space-y-3">
            <label className="block">
              <span style={{ fontSize: 12, color: "var(--color-fg-secondary)" }}>Short code</span>
              <TextField
                autoFocus
                value={code}
                onChange={(e) => setCode(e.target.value.toUpperCase())}
                placeholder="XXX-XXX-XXX"
                spellCheck={false}
                autoComplete="off"
                className="mt-1.5 font-mono"
                style={{ letterSpacing: "0.04em", fontSize: 15 }}
              />
            </label>

            {error && (
              <div style={{ fontSize: 12, color: "var(--color-destructive)" }}>{error}</div>
            )}

            <div className="flex justify-end pt-2">
              <Button type="submit" variant="primary" disabled={connecting}>
                {connecting ? "Connecting…" : "Connect"}
              </Button>
            </div>
          </form>
        </Card>
      </motion.div>
    </div>
  );
}
