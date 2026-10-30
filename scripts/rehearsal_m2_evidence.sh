#!/usr/bin/env bash
# scripts/rehearsal_m2_evidence.sh — LOCAL REHEARSAL ONLY.
# Captures REAL `venue.get_door_manifest` / `get_door_manifest_door` /
# `get_signing_keys_door` / `get_manifest_signing_context` output from the local
# rehearsal database into tests/fixtures/m2-rehearsal-evidence.json (the
# capture transaction is ROLLED BACK; the database is left untouched), then
# produces a DOOR-MANIFEST-SIG-v1 artifact over the captured open manifest.
#
# Key material: a THROWAWAY P-256 key pair is generated in a private temp dir
# for this capture only. Its PUBLIC half is inserted (inside the rolled-back
# transaction) as the active global `kernel.signing_key` row, so the captured
# M1 carries a real SPKI PEM; its PRIVATE half signs the artifact's canonical
# bytes ONCE and is then deleted. No private material, handle, or secret is
# ever written into the fixture (the vitest asserts this).
#
# Never points at production: the DSN must be a localhost URL.
set -euo pipefail
DBNAME="${1:-snatchit_rehearsal}"
DSN="${REHEARSAL_DSN:-postgresql://postgres@127.0.0.1:5432/${DBNAME}}"
case "$DSN" in *127.0.0.1*|*localhost*) ;; *) echo "refusing non-local DSN" >&2; exit 2;; esac
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/tests/fixtures/m2-rehearsal-evidence.json"

KEYDIR="$(mktemp -d)"
trap 'rm -rf "$KEYDIR"' EXIT
openssl ecparam -name prime256v1 -genkey -noout -out "$KEYDIR/priv.pem" 2>/dev/null
openssl ec -in "$KEYDIR/priv.pem" -pubout -out "$KEYDIR/pub.pem" 2>/dev/null
PUB_PEM="$(cat "$KEYDIR/pub.pem")"

psql -v ON_ERROR_STOP=1 -q "$DSN" -f "$ROOT/supabase/tests/000_helpers.sql" >/dev/null
psql -v ON_ERROR_STOP=1 -q -At -v M1_PUBLIC_PEM="$PUB_PEM" "$DSN" -f "$ROOT/scripts/rehearsal_m2_evidence.sql" > "$OUT"

# Sign the captured open manifest's canonical header (DOOR-MANIFEST-SIG-v1:
# JSON.stringify of {manifest_id, manifest_version, session_id, not_after,
# manifest_digest} in that key order, UTF-8; ES256 raw R||S, standard base64)
# with the throwaway private key, naming the captured context's key_id.
python3 - "$OUT" "$KEYDIR/priv.pem" <<'PY'
import base64, json, subprocess, sys
out, priv = sys.argv[1], sys.argv[2]
d = json.load(open(out))
m = d['door_full']
ctx = d['manifest_signing_context']
assert ctx.get('status') == 'ok', ctx
header = {'manifest_id': m['manifest_id'], 'manifest_version': m['manifest_version'], 'session_id': m['session_id'],
          'not_after': m['not_after'], 'manifest_digest': m['manifest_digest']}
canonical = json.dumps(header, separators=(',', ':'), ensure_ascii=False).encode('utf-8')
der = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', priv], input=canonical, check=True, capture_output=True).stdout
# DER ECDSA-Sig-Value -> raw R||S (32+32)
assert der[0] == 0x30
i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7f)
def read_int(buf, i):
    assert buf[i] == 0x02
    ln = buf[i + 1]; val = buf[i + 2:i + 2 + ln]
    return int.from_bytes(val, 'big'), i + 2 + ln
r, i = read_int(der, i); s, i = read_int(der, i)
raw = r.to_bytes(32, 'big') + s.to_bytes(32, 'big')
d['door_manifest_artifact'] = {'manifest': m, 'signature': {'value': base64.b64encode(raw).decode(), 'algorithm': 'ES256', 'key_id': ctx['key_id']}}
d['door_manifest_artifact_note'] = 'signed at capture with a throwaway P-256 key whose PUBLIC half is the captured active global kernel.signing_key row; private half discarded'
json.dump(d, open(out, 'w'), indent=1, sort_keys=True)
print('captured keys:', sorted(d))
PY
echo "wrote $OUT"
