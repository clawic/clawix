/**
 * Wire parity check between Swift `BridgeModels.swift` / `BridgeProtocol.swift`
 * and the TypeScript Zod schemas in `src/bridge/wire.ts` / `src/bridge/frames.ts`.
 *
 * Strategy: parse the Swift sources for top-level public structs/enums and
 * extract their member names. Then parse the Zod sources to extract the
 * keys of each `z.object({ ... })` and compare. We don't try to be a full
 * Swift parser; we only care about matching field names. Mismatches are
 * reported and the script exits non-zero on any divergence.
 *
 * Run via: `pnpm check:wire`
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const ROOT = path.resolve(__dirname, "..");
const REPO = path.resolve(ROOT, "..");
const SWIFT_MODELS = path.join(REPO, "packages/ClawixCore/Sources/ClawixCore/BridgeModels.swift");
const SWIFT_PROTOCOL = path.join(REPO, "packages/ClawixCore/Sources/ClawixCore/BridgeProtocol.swift");
const TS_WIRE = path.join(ROOT, "src/bridge/wire.ts");
const TS_FRAMES = path.join(ROOT, "src/bridge/frames.ts");

interface SwiftStruct {
  name: string;
  fields: string[];
}

function readFile(p: string): string {
  return fs.readFileSync(p, "utf8");
}

/** Pull `public struct Name: ... { let/var fieldName: ... }` blocks. */
function parseSwiftStructs(src: string): SwiftStruct[] {
  const out: SwiftStruct[] = [];
  const structRe = /public struct (\w+)[^{]*\{([\s\S]*?)\n\}/g;
  let m: RegExpExecArray | null;
  while ((m = structRe.exec(src)) !== null) {
    const [, name, body] = m;
    if (!name || !body) continue;
    const fields: string[] = [];
    const fieldRe = /^\s*public (?:let|var) (\w+):/gm;
    let fm: RegExpExecArray | null;
    while ((fm = fieldRe.exec(body)) !== null) {
      const fieldName = fm[1];
      if (fieldName) fields.push(fieldName);
    }
    out.push({ name, fields: dedupe(fields) });
  }
  return out;
}

function parseSwiftEnums(src: string): { name: string; cases: string[] }[] {
  const out: { name: string; cases: string[] }[] = [];
  const enumRe = /public enum (\w+)[^{]*\{([\s\S]*?)\n\}/g;
  let m: RegExpExecArray | null;
  while ((m = enumRe.exec(src)) !== null) {
    const [, name, body] = m;
    if (!name || !body) continue;
    const cases: string[] = [];
    const caseRe = /^\s*case (\w+)/gm;
    let cm: RegExpExecArray | null;
    while ((cm = caseRe.exec(body)) !== null) {
      const caseName = cm[1];
      if (caseName) cases.push(caseName);
    }
    out.push({ name, cases });
  }
  return out;
}

interface ZodObject {
  name: string;
  fields: string[];
}

/** Pull `export const ZName = z.object({ a: ..., b: ... })` blocks. */
function parseZodObjects(src: string): ZodObject[] {
  const out: ZodObject[] = [];
  const re = /export const (Z\w+) = z\.object\(\{([\s\S]*?)\}\);?/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    const [, name, body] = m;
    if (!name || !body) continue;
    const fields: string[] = [];
    const fieldRe = /^\s*(?:\.\.\.base,|\.\.\.)?(\w+):/gm;
    let fm: RegExpExecArray | null;
    while ((fm = fieldRe.exec(body)) !== null) {
      const fieldName = fm[1];
      if (fieldName && fieldName !== "protocolVersion" && fieldName !== "type") {
        fields.push(fieldName);
      }
    }
    out.push({ name, fields: dedupe(fields) });
  }
  return out;
}

function dedupe<T>(arr: T[]): T[] {
  return [...new Set(arr)];
}

function diff(a: string[], b: string[]): { onlyA: string[]; onlyB: string[] } {
  const sa = new Set(a);
  const sb = new Set(b);
  return {
    onlyA: a.filter((x) => !sb.has(x)),
    onlyB: b.filter((x) => !sa.has(x)),
  };
}

function main() {
  const swiftModels = parseSwiftStructs(readFile(SWIFT_MODELS));
  const swiftEnums = parseSwiftEnums(readFile(SWIFT_MODELS));
  const swiftProtocol = parseSwiftStructs(readFile(SWIFT_PROTOCOL));
  const zodWire = parseZodObjects(readFile(TS_WIRE));
  const zodFrames = parseZodObjects(readFile(TS_FRAMES));

  let failed = 0;

  // Match struct -> Z<Struct>
  const allSwift = [...swiftModels, ...swiftProtocol];
  const allZod = [...zodWire, ...zodFrames];

  for (const sw of allSwift) {
    const expected = `Z${sw.name}`;
    const zod = allZod.find((z) => z.name === expected);
    if (!zod) {
      console.warn(`  · Swift struct ${sw.name} has no matching ${expected} in TS (skipping for now)`);
      continue;
    }
    const { onlyA, onlyB } = diff(sw.fields, zod.fields);
    if (onlyA.length || onlyB.length) {
      failed++;
      console.error(`✗ ${sw.name} <-> ${expected} field mismatch`);
      if (onlyA.length) console.error(`  only in Swift: ${onlyA.join(", ")}`);
      if (onlyB.length) console.error(`  only in TS:    ${onlyB.join(", ")}`);
    } else {
      console.log(`✓ ${sw.name} <-> ${expected} (${sw.fields.length} fields)`);
    }
  }

  // Enum sanity: presence only
  for (const en of swiftEnums) {
    if (en.cases.length === 0) continue;
    const tsHas = readFile(TS_WIRE).includes(`Z${en.name}`) || readFile(TS_FRAMES).includes(`Z${en.name}`);
    if (!tsHas) {
      console.warn(`  · Swift enum ${en.name} has no matching Z${en.name} in TS (skipping)`);
    }
  }

  if (failed > 0) {
    console.error(`\n${failed} mismatch(es). Update src/bridge/wire.ts or frames.ts to match Swift.`);
    process.exit(1);
  }
  console.log("\nWire parity: OK.");
}

main();
