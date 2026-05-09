/**
 * Argon2id key derivation. Used by the Secrets Vault unlock flow to derive
 * the master key from the user's passphrase + salt. The Mac app uses the
 * same algorithm (ClawixArgon2); a parity test pins identical inputs to
 * identical outputs before the unlock flow accepts the derived key.
 *
 * Backed by `hash-wasm` because libsodium-wrappers' bundled .mjs has a
 * known broken self-import that does not survive Rollup. hash-wasm is
 * audited, ships a single WASM blob, and has a clean Argon2id API.
 */

import { argon2id } from "hash-wasm";

export interface Argon2Params {
  passphrase: string;
  /** 16+ random bytes. */
  salt: Uint8Array;
  /** Output key length in bytes (32 = 256 bits). */
  keyLen: number;
  /** Iterations (>=2 by spec, vault uses 3). */
  opsLimit: number;
  /** Memory in bytes; vault uses 64 MiB (67108864). */
  memLimitBytes: number;
}

const KIB = 1024;

export async function deriveArgon2id(params: Argon2Params): Promise<Uint8Array> {
  const result = await argon2id({
    password: params.passphrase,
    salt: params.salt,
    iterations: params.opsLimit,
    memorySize: Math.max(8, Math.floor(params.memLimitBytes / KIB)),
    parallelism: 1,
    hashLength: params.keyLen,
    outputType: "binary",
  });
  return result;
}

export function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

export function hexToBytes(hex: string): Uint8Array {
  const clean = hex.replace(/^0x/, "");
  if (clean.length % 2 !== 0) throw new Error("hex string with odd length");
  const out = new Uint8Array(clean.length / 2);
  for (let i = 0; i < out.length; i++) {
    out[i] = parseInt(clean.slice(i * 2, i * 2 + 2), 16);
  }
  return out;
}
