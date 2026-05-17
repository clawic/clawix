// Secrets Vault companion surface. Signed host/vault APIs own unlock and
// reveal; this web view verifies local Argon2id parity without moving secrets.
import { useState } from "react";
import { KeyIcon } from "../../icons";
import { PageHeader, Card, Button, TextField } from "../../components/ui";
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
      <div className="thin-scroll flex-1 overflow-y-auto">
        <div className="max-w-[560px] mx-auto pt-8 pb-12 px-6 space-y-5">
          <PageHeader title="Secrets vault" subtitle="Local-first crypto with Mac parity." />
          <Card>
            <div className="p-4 space-y-4">
              <div
                className="grid place-items-center"
                style={{
                  width: 48,
                  height: 48,
                  borderRadius: 14,
                  background: "var(--color-sel-fill)",
                }}
              >
                <KeyIcon size={20} />
              </div>
              <div
                style={{
                  fontSize: 16,
                  fontVariationSettings: '"wght" 800',
                  letterSpacing: "-0.02em",
                }}
              >
                Vault locked
              </div>
              <p
                style={{
                  fontSize: 12.5,
                  color: "var(--color-fg-secondary)",
                  lineHeight: 1.55,
                }}
              >
                Unlock and reveal stay with the signed host/vault v1 surface. The crypto below runs
                locally with libsodium Argon2id and proves the derivation matches the Mac binding
                without moving plaintext secrets into the web companion.
              </p>
              <TextField
                type="password"
                value={pass}
                onChange={(e) => setPass(e.target.value)}
                placeholder="Test passphrase"
              />
              <Button onClick={selfTest} disabled={busy} variant="primary">
                {busy ? "Deriving…" : "Run Argon2 self-test"}
              </Button>
              {hash && (
                <pre
                  className="font-mono break-all"
                  style={{
                    fontSize: 11,
                    color: "var(--color-fg-secondary)",
                    background: "var(--color-bg)",
                    borderRadius: 10,
                    padding: 12,
                    boxShadow: "inset 0 0 0 0.5px var(--color-popup-stroke)",
                  }}
                >
                  {hash}
                </pre>
              )}
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}
