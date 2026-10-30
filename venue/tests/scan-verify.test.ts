import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { keyringFromRows, normalizeSpkiPublicKey, trustedKeyFromRow } from "@/lib/scan/keys";
import { keyInScope, verifyCredential, webcryptoVerify, type VerifyReason } from "@/lib/scan/verify";
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

/**
 * The route this door is scanning for. Every fixture key is `global`, so scope changes no golden vector's
 * outcome; the scoped cases are their own describe below (E-F10).
 */
const VENUE = "b3d1fa47-9c20-4e8b-ad6f-5c71e0a94bd2";
const EVENT = "c7e2ab19-4f83-4d0e-bf51-2a9c6de31f08";
const OTHER_VENUE = "d4f8ce23-7b15-4a9c-8e6d-3b0f17ac92de";
const OTHER_EVENT = "e9a1bd56-2c74-4f38-9d0b-6e5a83cf14b7";
const AT = { scanVenueId: VENUE, scanEventId: EVENT };

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
      const r = await verifyCredential(t.wire, { keyring, boundSessionId: t.bound_session, ...AT, nowSeconds: t.now_seconds, verify: webcryptoVerify });
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
    const fake = await verifyCredential(makeWire({ kid }), { keyring, boundSessionId: SESS, ...AT, nowSeconds: 1_800_000_000, verify: webcryptoVerify });
    expect(fake).toMatchObject({ ok: false, reason: "signature_invalid" });
    expect(await verifyCredential(makeWire(), { keyring, boundSessionId: SESS, ...AT, nowSeconds: 1, verify: webcryptoVerify })).toMatchObject({ ok: false, reason: "unknown_key" });
    let called = 0;
    const spy = async () => {
      called += 1;
      return true;
    };
    expect(await verifyCredential(makeWire({ kid, typ: "SNATCHIT-DOOR-MANIFEST-V1" }), { keyring, boundSessionId: SESS, ...AT, nowSeconds: 1, verify: spy })).toMatchObject({ ok: false, reason: "wrong_typ" });
    expect(called).toBe(0);
  });
  it("the expiry tolerance is the reference's 2 × 30 s, applied after the signature and session checks", async () => {
    const admit = fixture.tokens.find((t) => t.name === "admit_es256_pem_key")!;
    const okNow = await verifyCredential(admit.wire, { keyring, boundSessionId: admit.bound_session, ...AT, nowSeconds: admit.now_seconds, verify: webcryptoVerify });
    expect(okNow.ok).toBe(true);
    const exp = okNow.ok ? okNow.claims.exp : 0;
    expect((await verifyCredential(admit.wire, { keyring, boundSessionId: admit.bound_session, ...AT, nowSeconds: exp + 60, verify: webcryptoVerify })).ok).toBe(true);
    expect(await verifyCredential(admit.wire, { keyring, boundSessionId: admit.bound_session, ...AT, nowSeconds: exp + 61, verify: webcryptoVerify })).toMatchObject({ ok: false, reason: "expired" });
    expect(await verifyCredential(admit.wire, { keyring, boundSessionId: "5e55e55e-0a0c-4b0d-8e0f-0000000000a2", ...AT, nowSeconds: admit.now_seconds, verify: webcryptoVerify })).toMatchObject({ ok: false, reason: "wrong_session" });
  });
});

/**
 * E-F10 — a key the keyring trusts is not thereby trusted for THIS door. RLS on `kernel.signing_key` is
 * row-universal (083:117-123, PFA-16), so every venue reads every venue's keys, and nothing downstream
 * re-checks scope: `record_scan` is told an atom and a session, never which key vouched for them.
 *
 * The negative control is the PAIR in each case: the same token, the same key, the same clock — only the
 * route differs. Delete the `keyInScope` call in verify.ts and the wrong-route half starts returning
 * `ok: true`, which is precisely the cross-venue admission this prevents.
 */
describe("key scope is enforced against the route, not just the keyring (E-F10)", () => {
  const rows = fixture.m1_wire as Record<string, unknown>[];
  const admit = fixture.tokens.find((t) => t.name === "admit_es256_pem_key")!;
  const at = (scanVenueId: string, scanEventId: string) => ({ boundSessionId: admit.bound_session, scanVenueId, scanEventId, nowSeconds: admit.now_seconds, verify: webcryptoVerify });

  it("a per_venue key verifies at its own venue and is refused at another", async () => {
    const keyring = keyringFromRows(rows.map((r) => ({ ...r, scope: "per_venue", venue_id: VENUE })))!;
    expect((await verifyCredential(admit.wire, { keyring, ...at(VENUE, EVENT) })).ok).toBe(true);
    expect(await verifyCredential(admit.wire, { keyring, ...at(OTHER_VENUE, EVENT) })).toMatchObject({ ok: false, reason: "key_scope" });
  });

  it("a per_event key verifies for its own event and is refused for another", async () => {
    const keyring = keyringFromRows(rows.map((r) => ({ ...r, scope: "per_event", event_id: EVENT })))!;
    expect((await verifyCredential(admit.wire, { keyring, ...at(VENUE, EVENT) })).ok).toBe(true);
    expect(await verifyCredential(admit.wire, { keyring, ...at(VENUE, OTHER_EVENT) })).toMatchObject({ ok: false, reason: "key_scope" });
  });

  it("a global key verifies wherever it is presented", async () => {
    expect((await verifyCredential(admit.wire, { keyring, ...at(OTHER_VENUE, OTHER_EVENT) })).ok).toBe(true);
  });

  it("scope is refused before the key's status and window, so a scoped-out key never reaches them", async () => {
    const keyring = keyringFromRows(rows.map((r) => ({ ...r, scope: "per_venue", venue_id: VENUE, status: "revoked" })))!;
    expect(await verifyCredential(admit.wire, { keyring, ...at(OTHER_VENUE, EVENT) })).toMatchObject({ ok: false, reason: "key_scope" });
  });

  it("keyInScope fails closed on a NULL id, an empty route id, an unknown scope, and matches case-insensitively", () => {
    const base = { key_id: "k", public_key: "p", algorithm: "ES256", not_before: 0, not_after: Number.POSITIVE_INFINITY, status: "active" };
    const perVenue = (venue_id: string | null) => ({ ...base, scope: "per_venue" as const, venue_id, event_id: null });
    expect(keyInScope(perVenue(VENUE), VENUE, EVENT)).toBe(true);
    expect(keyInScope(perVenue(VENUE.toUpperCase()), VENUE, EVENT)).toBe(true);
    expect(keyInScope(perVenue(null), VENUE, EVENT)).toBe(false);
    expect(keyInScope(perVenue(VENUE), "", EVENT)).toBe(false);
    expect(keyInScope({ ...base, scope: "per_event" as const, event_id: null, venue_id: null }, VENUE, EVENT)).toBe(false);
    expect(keyInScope({ ...base, scope: "sideways" as unknown as "global", event_id: null, venue_id: null }, VENUE, EVENT)).toBe(false);
  });
});
