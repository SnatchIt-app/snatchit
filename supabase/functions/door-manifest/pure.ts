/**
 * supabase/functions/door-manifest/pure.ts
 * ═══════════════════════════════════════════════════════════════════════════
 * The PURE, import-free decisions of the `door-manifest` edge, unit-tested by
 * `tests/door-manifest.test.ts` (same discipline as `door-session/pure.ts`).
 *
 * WHY THIS FILE EXISTS (P1-M2-HEADER follow-up). The edge used to have ONE
 * shape check (`isDoorManifestOpen`) and treated every non-matching response
 * as "no open episode" — returning it 200 with `signature: null`. Against the
 * 086 RPC body (no `open`/`session_id`/`not_after`) that meant EVERY open
 * episode was mis-classified as closed and handed back UNSIGNED, silently,
 * without ever reaching KMS — a fail-OPEN in the sense that the caller got a
 * manifest it could not tell was unsigned-by-defect rather than unsigned-by-
 * closure. The classifier below distinguishes THREE outcomes and the edge acts
 * on each: `open` ⇒ sign; `closed` ⇒ 200 unsigned (legitimate); `malformed`
 * ⇒ 500 `manifest_malformed`, before any KMS call.
 * ═══════════════════════════════════════════════════════════════════════════
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** `venue.get_door_manifest`'s open-episode shape (RPC §20.6.1 reconciled;
 *  migration 112 supplies the header fields from the stored row). */
export interface DoorManifestOpen {
  open: true;
  status?: string;
  manifest_id: string;
  manifest_version: number;
  session_id: string;
  opened_at: string;
  not_after: string;
  manifest_digest: string;
  max_delta_seq: number;
  entries: unknown[];
  deltas: unknown[];
}

export type DoorManifestClassification =
  | { kind: 'open'; manifest: DoorManifestOpen }
  | { kind: 'closed'; manifest: Record<string, unknown> }
  | { kind: 'malformed'; reason: string };

const CLOSED_STATUSES = new Set(['no_open_episode', 'no_open_manifest']);

function isNonNegativeInt(v: unknown): v is number {
  return typeof v === 'number' && Number.isInteger(v) && v >= 0;
}
function isIsoTimestamp(v: unknown): v is string {
  return typeof v === 'string' && v.length > 0 && Number.isFinite(Date.parse(v));
}

/**
 * Classify the RPC result. Rules (stable, tested):
 *   closed    — `open === false`, OR `open` absent with a closed `status`
 *               (the legacy 086 no-episode shape `{status:'no_open_episode'}`);
 *               `entries`/`deltas`, if present, must be arrays.
 *   open      — `open === true` AND every header field present and well-formed:
 *               manifest_id (uuid), manifest_version (int ≥ 1), session_id
 *               (uuid), opened_at / not_after (parseable ISO-8601 strings),
 *               manifest_digest (non-empty string), max_delta_seq (int ≥ 0),
 *               entries/deltas arrays.
 *   malformed — anything else, with a stable machine-readable reason:
 *               `not_an_object`, `missing_open` (the 086 open-episode shape
 *               without `open`/`session_id`/`not_after` lands HERE, never in
 *               `closed`), `invalid:<field>`, `open_not_boolean`.
 */
export function classifyDoorManifestResponse(v: unknown): DoorManifestClassification {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return { kind: 'malformed', reason: 'not_an_object' };
  const r = v as Record<string, unknown>;
  const arraysOk = (r.entries === undefined || Array.isArray(r.entries)) && (r.deltas === undefined || Array.isArray(r.deltas));

  if (r.open === false) {
    if (!arraysOk) return { kind: 'malformed', reason: 'invalid:entries_or_deltas' };
    return { kind: 'closed', manifest: r };
  }
  if (r.open === undefined) {
    if (typeof r.status === 'string' && CLOSED_STATUSES.has(r.status) && arraysOk) return { kind: 'closed', manifest: r };
    return { kind: 'malformed', reason: 'missing_open' };
  }
  if (r.open !== true) return { kind: 'malformed', reason: 'open_not_boolean' };

  if (typeof r.manifest_id !== 'string' || !UUID_RE.test(r.manifest_id)) return { kind: 'malformed', reason: 'invalid:manifest_id' };
  if (!isNonNegativeInt(r.manifest_version) || r.manifest_version < 1) return { kind: 'malformed', reason: 'invalid:manifest_version' };
  if (typeof r.session_id !== 'string' || !UUID_RE.test(r.session_id)) return { kind: 'malformed', reason: 'invalid:session_id' };
  if (!isIsoTimestamp(r.opened_at)) return { kind: 'malformed', reason: 'invalid:opened_at' };
  if (!isIsoTimestamp(r.not_after)) return { kind: 'malformed', reason: 'invalid:not_after' };
  if (typeof r.manifest_digest !== 'string' || r.manifest_digest.length === 0) return { kind: 'malformed', reason: 'invalid:manifest_digest' };
  if (!isNonNegativeInt(r.max_delta_seq)) return { kind: 'malformed', reason: 'invalid:max_delta_seq' };
  if (!Array.isArray(r.entries)) return { kind: 'malformed', reason: 'invalid:entries' };
  if (!Array.isArray(r.deltas)) return { kind: 'malformed', reason: 'invalid:deltas' };

  return { kind: 'open', manifest: r as unknown as DoorManifestOpen };
}

/** The bytes the edge signs (§3.9b) — `JSON.stringify` of the five header
 *  fields in THIS key order, UTF-8. Byte-identical to
 *  `_shared/offline-verify.ts`'s `canonicalDoorManifestSignedBytes`
 *  (DOOR-MANIFEST-SIG-v1); the verifier rebuilds exactly these bytes. */
export function canonicalManifestDigestBytes(open: DoorManifestOpen): Uint8Array {
  const canonical = {
    manifest_id: open.manifest_id,
    manifest_version: open.manifest_version,
    session_id: open.session_id,
    not_after: open.not_after,
    manifest_digest: open.manifest_digest,
  };
  return new TextEncoder().encode(JSON.stringify(canonical));
}

// ── Manifest-signing key identity (114 `venue.get_manifest_signing_context`).
// The edge names `signature.key_id` from THIS — the single active GLOBAL
// `kernel.signing_key` row — and signs with the SAME row's `kms_handle_ref`.
// No env-only identifier is trusted. Everything the DB decided is re-checked
// here (ES256 pin, status, window) so a stale/foreign row still fails closed
// BEFORE any KMS call. ───────────────────────────────────────────────────────

export interface ManifestSigningContext {
  key_id: string;
  kms_handle_ref: string;
  algorithm: 'ES256';
  public_key: string;
  not_before: string;
  not_after: string | null;
}

export type ManifestSigningContextClassification =
  | { kind: 'ok'; context: ManifestSigningContext }
  | { kind: 'unavailable'; code: string }
  | { kind: 'malformed'; code: string };

const STABLE_CODE_RE = /^[a-z0-9_]{1,64}$/;

export function classifyManifestSigningContext(v: unknown, nowSeconds: number): ManifestSigningContextClassification {
  if (!v || typeof v !== 'object' || Array.isArray(v)) return { kind: 'malformed', code: 'not_an_object' };
  const r = v as Record<string, unknown>;
  if (r.status === 'unavailable') {
    const code = typeof r.code === 'string' && STABLE_CODE_RE.test(r.code) ? r.code : 'unspecified';
    return { kind: 'unavailable', code };
  }
  if (r.status !== 'ok') return { kind: 'malformed', code: 'unknown_status' };
  if (typeof r.key_id !== 'string' || !UUID_RE.test(r.key_id)) return { kind: 'malformed', code: 'invalid:key_id' };
  if (typeof r.kms_handle_ref !== 'string' || r.kms_handle_ref.length === 0) return { kind: 'malformed', code: 'invalid:kms_handle_ref' };
  if (typeof r.public_key !== 'string' || r.public_key.length === 0) return { kind: 'malformed', code: 'invalid:public_key' };
  if (r.algorithm !== 'ES256') return { kind: 'unavailable', code: 'algorithm_not_es256' };
  if (r.key_status !== 'active') return { kind: 'unavailable', code: 'key_not_active' };
  if (!isIsoTimestamp(r.not_before)) return { kind: 'malformed', code: 'invalid:not_before' };
  if (r.not_after !== null && r.not_after !== undefined && !isIsoTimestamp(r.not_after)) return { kind: 'malformed', code: 'invalid:not_after' };
  const nb = Date.parse(r.not_before) / 1000;
  const na = typeof r.not_after === 'string' ? Date.parse(r.not_after) / 1000 : null;
  if (nowSeconds < nb || (na !== null && nowSeconds >= na)) return { kind: 'unavailable', code: 'key_window' };
  return {
    kind: 'ok',
    context: {
      key_id: r.key_id,
      kms_handle_ref: r.kms_handle_ref,
      algorithm: 'ES256',
      public_key: r.public_key,
      not_before: r.not_before,
      not_after: na === null ? null : (r.not_after as string),
    },
  };
}

/** DOOR-MANIFEST-SIG-v1 envelope — EXACTLY `{ value, algorithm, key_id }`.
 *  Built from primitives (never from the context object) so a KMS handle or
 *  public key can never ride along into the response. */
export function buildSignatureEnvelope(valueB64: string, keyId: string): { value: string; algorithm: 'ES256'; key_id: string } {
  return { value: valueB64, algorithm: 'ES256', key_id: keyId };
}
