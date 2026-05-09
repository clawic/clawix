/**
 * Pairing screen. Two paths:
 *  - Loopback (page served by the daemon): hit `/pairing/qr.json` to
 *    self-configure. The daemon responds only to loopback IPs.
 *  - Remote (Tailscale, mDNS): user pastes the short code (XXX-XXX-XXX)
 *    visible on their Mac.
 */
import { useEffect, useState } from "react";
import { motion } from "framer-motion";
import { useBridgeStore } from "../../bridge/store";
import { ZQrPayload, normaliseShortCode } from "../../bridge/frames";
import { storage, StorageKeys } from "../../lib/storage";
import { GlassPill } from "../../components/glass-pill";
import { ChevronRightIcon, BotIcon } from "../../icons";

export function PairingScreen() {
  const attach = useBridgeStore((s) => s.attach);
  const conn = useBridgeStore((s) => s.connection);
  const [code, setCode] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [autoTried, setAutoTried] = useState(false);

  // Auto-pair on loopback: request the QR JSON once on mount.
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
    if (conn.kind === "auth-failed") {
      setError(conn.reason);
    }
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

  return (
    <div className="min-h-full flex items-center justify-center px-6 py-16">
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
        className="w-full max-w-[440px]"
      >
        <div className="flex items-center gap-3 mb-7">
          <div className="size-10 rounded-[12px] bg-[var(--color-bg-elev-2)] grid place-items-center text-[var(--color-fg)]">
            <BotIcon size={22} />
          </div>
          <div>
            <div className="text-[18px] font-medium tracking-[-0.02em]">Clawix Web</div>
            <div className="text-[12px] text-[var(--color-fg-muted)]">Pair with your Mac to start</div>
          </div>
        </div>

        <p className="text-[13px] text-[var(--color-fg-muted)] mb-6 leading-relaxed">
          Open Clawix on your Mac, enable the background bridge in Settings, and copy the short
          code. Or just open this page from <code className="font-mono text-[12px] text-[var(--color-fg)]">localhost:7778</code> and
          we will pair automatically.
        </p>

        <form onSubmit={submit} className="space-y-3">
          <label className="block">
            <span className="text-[12px] text-[var(--color-fg-muted)]">Short code</span>
            <input
              autoFocus
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              placeholder="XXX-XXX-XXX"
              spellCheck={false}
              autoComplete="off"
              className="mt-1.5 w-full h-11 px-3.5 rounded-[12px] bg-[var(--color-bg-elev-1)] border border-[var(--color-border)] outline-none focus:border-[var(--color-border-strong)] font-mono text-[15px] tracking-[0.04em]"
            />
          </label>

          {error && (
            <div className="text-[12px] text-[var(--color-danger)]">
              {error}
            </div>
          )}

          <div className="flex justify-end pt-2">
            <GlassPill type="submit" size="md" disabled={conn.kind === "connecting" || conn.kind === "authenticating"}>
              {conn.kind === "connecting" || conn.kind === "authenticating" ? "Connecting…" : "Connect"}
              <ChevronRightIcon size={14} />
            </GlassPill>
          </div>
        </form>
      </motion.div>
    </div>
  );
}
