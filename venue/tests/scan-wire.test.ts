import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import vm from "node:vm";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { decodeCredentialWire, MAX_WIRE_TOKEN_LENGTH } from "@/lib/scan/wire";
import { ATOM, KID, makeWire, seg, SESS, SIG64 } from "./helpers/credential-wire";

/**
 * The venue app carries a copy of the reference decoder (SCANNER-CONTRACT-v1
 * step 0-wire, supabase/functions/_shared/offline-verify.ts) because its build
 * root cannot import across venue/. This file is what keeps the copy honest:
 * both decoders are run on every golden token the contract ships and on a
 * set of deliberately broken tokens, and must agree exactly.
 */
const ROOT = resolve(__dirname, "../..");
const REF = resolve(ROOT, "supabase/functions/_shared/offline-verify.ts");
const FIXTURE = resolve(ROOT, "tests/fixtures/scanner-contract-v1.json");
type Ref = { decodeOfflineToken: (wire: unknown) => null | { keyId: string; typ: string; algorithm: string; sessionId: string; atomId: string; credentialVersion: number; exp: number } };
/**
 * The reference is a Deno-side module with no imports. It is transpiled here
 * with the TypeScript compiler and evaluated in a bare sandbox, rather than
 * imported through vite, so the venue app's own tsconfig and bundler never
 * see it (vite would resolve the repo-root tsconfig, which extends an Expo
 * base the venue app does not install).
 */
function loadReference(): Ref {
  const js = ts.transpileModule(readFileSync(REF, "utf8"), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  const mod = { exports: {} as Record<string, unknown> };
  vm.runInNewContext(js, { module: mod, exports: mod.exports, TextDecoder, TextEncoder, require: () => { throw new Error("the reference must not import anything"); } }, { filename: REF });
  return mod.exports as unknown as Ref;
}
const ref = loadReference();
const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { contract: string; tokens: { name: string; wire: string; expected: { admit: boolean; atomId?: string; reason?: string } }[] };

function agree(wire: unknown) {
  const a = ref.decodeOfflineToken(wire);
  const b = decodeCredentialWire(wire);
  if (a === null || b === null) {
    expect(a, `reference and copy disagree on nullness for ${String(wire).slice(0, 40)}`).toBe(b);
    return null;
  }
  expect({ keyId: b.keyId, typ: b.typ, algorithm: b.algorithm, sessionId: b.sessionId, atomId: b.atomId, credentialVersion: b.credentialVersion, exp: b.exp }).toEqual({
    keyId: a.keyId,
    typ: a.typ,
    algorithm: a.algorithm,
    sessionId: a.sessionId,
    atomId: a.atomId,
    credentialVersion: a.credentialVersion,
    exp: a.exp,
  });
  return b;
}

describe("the vendored decoder is the reference decoder", () => {
  it("the golden fixture is SCANNER-CONTRACT-v1 and has tokens", () => {
    expect(fixture.contract).toBe("SCANNER-CONTRACT-v1");
    expect(fixture.tokens.length).toBeGreaterThanOrEqual(10);
  });
  it("agrees with the reference on every golden token, and the admit vectors decode to their expected atom", () => {
    let decoded = 0;
    for (const t of fixture.tokens) {
      const b = agree(t.wire);
      if (b) decoded += 1;
      if (t.expected.admit) expect(b?.atomId, t.name).toBe(t.expected.atomId);
      if (t.expected.reason === "malformed_token") expect(b, t.name).toBeNull();
    }
    expect(decoded).toBeGreaterThan(0);
  });
  it("agrees with the reference on broken tokens: both refuse every one", () => {
    const good = makeWire();
    expect(agree(good)?.atomId).toBe(ATOM);
    const broken: unknown[] = [
      "",
      null,
      42,
      good.replace(/\./, ""),
      `${good}.extra`,
      good.split(".").slice(0, 2).join("."),
      `${good}=`,
      `${good.slice(0, 3)}+${good.slice(4)}`, // a standard-base64 character where only the url-safe alphabet is allowed
      `${good.slice(0, 3)}/${good.slice(4)}`,
      ` ${good}`,
      makeWire({ header: { alg: "ES256", kid: KID, typ: "SNATCHIT-TICKET-CRED-V1", extra: 1 } }),
      makeWire({ payload: { atom: ATOM, exp: 1, iat: 0, sess: SESS, ver: 1, atom_id: ATOM } }),
      makeWire({ iat: 10, exp: 9 }),
      makeWire({ atom: "not-a-uuid" }),
      makeWire({ sess: SESS.toUpperCase() }),
      makeWire({ kid: "x" }),
      makeWire({ ver: -1 }),
      makeWire({ exp: 1.5 }),
      makeWire({ sig: seg("short") }),
      `${seg("not an object")}.${seg({ atom: ATOM, exp: 1, iat: 0, sess: SESS, ver: 1 })}.${SIG64}`,
      "a".repeat(MAX_WIRE_TOKEN_LENGTH + 1),
    ];
    for (const w of broken) expect(agree(w), String(w).slice(0, 40)).toBeNull();
  });
  it("an unknown alg is decodable (the verifier refuses it later), with any signature length — same as the reference", () => {
    const w = makeWire({ alg: "HS256", sig: seg("x") });
    expect(agree(w)?.algorithm).toBe("HS256");
  });
});
