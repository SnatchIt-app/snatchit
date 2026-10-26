import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { keyringFromRows, normalizeSpkiPublicKey, trustedKeyFromRow } from "@/lib/scan/keys";
import { verifyCredential, webcryptoVerify, type VerifyReason } from "@/lib/scan/verify";
import { makeWire, SESS } from "./helpers/credential-wire";

/**
 * Every golden vector of SCANNER-CONTRACT-v1 (tests/fixtures/scanner-contract-v1.json) through the staff-path
 * verifier with the fixture's real public keys and WebCrypto. Vectors the offline reference refuses on a
 * manifest (M2) or an admitted-set ground are the SERVER's on the online path, so here they must pass
 * verification; every signature/key/session/expiry refusal must be the same reason the reference gives.
 */
const FIXTURE = resolve(__dirname, "../../tests/fixtures/scanner-contract-v1.json");
type Token = { name: string; wire: string; now_seconds: number; bound_session: string; expected: { admit: boolean; atomId?: string; reason?: string } };
const fixture = JSON.parse(readFileSync(FIXTURE, "utf8")) as { m1_wire: unknown[]; tokens: Token[] };
const keyring = keyringFromRows(fixture.m1_wire)!;

/** Reasons the ONLINE verifier shares with the reference; everything else the reference refuses is M2/admitted-set territory. */
const ONLINE_REASONS = new Set<string>(["malformed_token", "wrong_typ", "unsupported_alg", "unknown_key", "key_revoked", "key_window", "alg_mismatch", "malformed_public_key", "signature_invalid", "wrong_session", "expired"]);

describe("the trusted keyring adapter", () => {
  it("loads the fixture's four keys (active, rotating with a window, revoked, EdDSA); a malformed or duplicate row voids the keyring", () => {
    expect(Object.keys(keyring)).toHaveLength(4);
    expect(keyringFromRows([...fixture.m1_wire, fixture.m1_wire[0]])).toBeNull();
    expect(keyringFromRows([{ ...(fixture.m1_wire[0] as object), key_id: "nope" }])).toBeNull();
    expect(keyringFromRows("x")).toBeNull();
    const k = trustedKeyFromRow({ ...(fixture.m1_wire[0] as object), not_after: null })!;
    expect(k.not_after).toBe(Number.POSITIVE_INFINITY);
    expect(trustedKeyFromRow({ ...(fixture.m1_wire[0] as object), not_before: "not a date" })).toBeNull();
  });
  it("normalizes PEM and bare keys to the pinned algorithm's exact SPKI shape and refuses everything else", () => {
    const pem = (fixture.m1_wire[0] as { public_key: string }).public_key;
    const canonical = normalizeSpkiPublicKey(pem, "ES256")!;
    expect(canonical).toMatch(/^[A-Za-z0-9+/]+=*$/);
    expect(normalizeSpkiPublicKey(canonical, "ES256")).toBe(canonical);
    expect(normalizeSpkiPublicKey(pem, "EdDSA")).toBeNull();
    expect(normalizeSpkiPublicKey(pem.replace("PUBLIC", "PRIVATE"), "ES256")).toBeNull();
    expect(normalizeSpkiPublicKey("", "ES256")).toBeNull();
  });
});

describe("verifyCredential — every golden vector, real keys, WebCrypto", () => {
  it("matches the reference on every signature, key, session and expiry refusal, and passes what only a manifest could refuse", async () => {
    const seen = new Set<string>();
    for (const t of fixture.tokens) {
      const r = await verifyCredential(t.wire, { keyring, boundSessionId: t.bound_session, nowSeconds: t.now_seconds, verify: webcryptoVerify });
      const exp = t.expected;
      if (exp.admit) {
        expect(r.ok, t.name).toBe(true);
        if (r.ok) expect(r.claims.atomId).toBe(exp.atomId);
      } else if (ONLINE_REASONS.has(exp.reason!)) {
        expect(r.ok, t.name).toBe(false);
        if (!r.ok) expect(r.reason, t.name).toBe(exp.reason as VerifyReason);
        seen.add(exp.reason!);
      } else {
        // M2 / admitted-set refusals (stale_version, atom_*, manifest_*, listed_locked, not_active, wrong_signing_key …) are the server's online
        expect(r.ok, `${t.name} (reference refuses on ${exp.reason}, the server does that online)`).toBe(true);
      }
    }
    // the fixture exercises the whole online refusal set we claim to share, minus two it has no vector for
    for (const reason of ["wrong_session", "expired", "key_revoked", "key_window", "alg_mismatch", "signature_invalid", "malformed_token"]) expect(seen.has(reason), reason).toBe(true);
  });
  it("a fabricated token with a known kid but a made-up signature is signature_invalid; an unknown kid is unknown_key; a wrong typ is refused before any key work", async () => {
    const kid = Object.keys(keyring)[0];
    const fake = await verifyCredential(makeWire({ kid }), { keyring, boundSessionId: SESS, nowSeconds: 1_800_000_000, verify: webcryptoVerify });
    expect(fake).toMatchObject({ ok: false, reason: "signature_invalid" });
    expect(await verifyCredential(makeWire(), { keyring, boundSessionId: SESS, nowSeconds: 1, verify: webcryptoVerify })).toMatchObject({ ok: false, reason: "unknown_key" });
    let called = 0;
    const spy = async () => {
      called += 1;
      return true;
    };
    expect(await verifyCredential(makeWire({ kid, typ: "SNATCHIT-DOOR-MANIFEST-V1" }), { keyring, boundSessionId: SESS, nowSeconds: 1, verify: spy })).toMatchObject({ ok: false, reason: "wrong_typ" });
    expect(called).toBe(0);
  });
  it("the expiry tolerance is the reference's 2 × 30 s, applied after the signature and session checks", async () => {
    const admit = fixture.tokens.find((t) => t.name === "admit_es256_pem_key")!;
    const okNow = await verifyCredential(admit.wire, { keyring, boundSessionId: admit.bound_session, nowSeconds: admit.now_seconds, verify: webcryptoVerify });
    expect(okNow.ok).toBe(true);
    const exp = okNow.ok ? okNow.claims.exp : 0;
    expect((await verifyCredential(admit.wire, { keyring, boundSessionId: admit.bound_session, nowSeconds: exp + 60, verify: webcryptoVerify })).ok).toBe(true);
    expect(await verifyCredential(admit.wire, { keyring, boundSessionId: admit.bound_session, nowSeconds: exp + 61, verify: webcryptoVerify })).toMatchObject({ ok: false, reason: "expired" });
    expect(await verifyCredential(admit.wire, { keyring, boundSessionId: "5e55e55e-0000-4000-8000-000000000002", nowSeconds: admit.now_seconds, verify: webcryptoVerify })).toMatchObject({ ok: false, reason: "wrong_session" });
  });
});
