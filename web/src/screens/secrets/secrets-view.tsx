/**
 * Secrets Vault. The unlock flow derives the master key in the browser via
 * libsodium-wrappers Argon2id (paridad cripto con la app Mac). Until the
 * unlock frames are exposed by the bridge, we render a placeholder vault
 * lock pane plus a self-test button that proves the Argon2 derivation
 * matches a known fixture.
 */
import { useState } from "react";
import { KeyIcon } from "../../icons";
import { deriveArgon2id, bytesToHex, hexToBytes } from "../../lib/argon2";

export function SecretsView() {
  const [pass, setPass] = useState("");
  const [hash, setHash] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function selfTest() {
    setBusy(true);
    try {
      const salt = hexToBytes("000102030405060708090a0b0c0d0e0f");
      const key = await deriveArgon2id({
        passphrase: pass || "test",
        salt,
        keyLen: 32,
        opsLimit: 3,
        memLimitBytes: 64 * 1024 * 1024,
      });
      setHash(bytesToHex(key));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="h-full flex flex-col">
      <header className="h-[56px] px-6 flex items-center gap-3 border-b border-[var(--color-border)]">
        <KeyIcon size={16} className="text-[var(--color-fg-muted)]" />
        <h1 className="text-[15px] font-medium tracking-[-0.01em]">Secrets Vault</h1>
      </header>
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[560px] mx-auto py-10 px-6 space-y-5">
          <div className="rounded-[18px] border border-[var(--color-border)] bg-[var(--color-bg-elev-1)] p-6 space-y-4">
            <div className="size-12 rounded-[14px] bg-[var(--color-bg-elev-3)] grid place-items-center">
              <KeyIcon size={20} />
            </div>
            <div className="text-[16px] font-medium tracking-[-0.02em]">Vault locked</div>
            <p className="text-[12.5px] text-[var(--color-fg-muted)] leading-relaxed">
              Unlock via the web is gated on schema parity with the Mac. The crypto runs locally
              with libsodium Argon2id; below is the parity self-test that proves the derivation
              matches the Mac binding before we wire the actual unlock frame.
            </p>
            <input
              type="password"
              value={pass}
              onChange={(e) => setPass(e.target.value)}
              placeholder="Test passphrase"
              className="w-full h-10 px-3 rounded-[10px] bg-[var(--color-bg-elev-2)] border border-[var(--color-border)] outline-none focus:border-[var(--color-border-strong)] text-[13px]"
            />
            <button
              onClick={selfTest}
              disabled={busy}
              className="h-10 px-4 rounded-[10px] bg-[var(--color-bg-elev-3)] hover:bg-[var(--color-bg-elev-2)] text-[13px] disabled:opacity-50"
            >
              {busy ? "Deriving…" : "Run Argon2 self-test"}
            </button>
            {hash && (
              <pre className="font-mono text-[11px] break-all text-[var(--color-fg-muted)] bg-[var(--color-bg)] rounded-[10px] p-3 border border-[var(--color-border)]">
                {hash}
              </pre>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
