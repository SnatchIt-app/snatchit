#!/usr/bin/env bash
# ============================================================================
# scripts/rehearsal_138_a6_concurrency.sh — LOCAL-ONLY two-session proof for
# migration 138's A6 (PFA-34 proposed): "accepting an invite must never
# overwrite or demote an existing organization owner" (owner, 2026-09-17).
#
# pgTAP 206 runs inside ONE transaction and cannot show two sessions, a lock
# wait, or a committed invariant breach. This runs OUTSIDE pg_prove, against a
# loopback rehearsal database that already has 138 applied, and prints PASS/FAIL
# per scenario. Its evidence is this output, not the pgTAP count.
#
#   usage: scripts/rehearsal_138_a6_concurrency.sh [dbname]   (default snatchit_rehears_138)
#
# Scenarios:
#   S1 FORWARD: session 1 opens a transaction and accepts an org_owner invite
#      (holding the organisation row lock, uncommitted). Session 2, an existing
#      owner, accepts a LOWER-role invite: it must BLOCK on that row — shown by
#      pg_blocking_pids, not by timing — and then be refused (owner_role_change)
#      once session 1 commits.
#   S2 REVERSE: session 1 holds the organisation row (select … for update) and
#      session 2 accepts an org_owner invite: it blocks, then SUCCEEDS. The lock
#      serialises; it does not refuse legitimate acceptance.
#   S3 RACE: two owners of the same organisation accept lower-role invites at the
#      same time. Both are refused and the roster still has both owners.
#   C1 CONTROL (A6 removed): the same S3 race against 077's acceptance body.
#      BOTH succeed and the organisation is left with ZERO owners — the breach
#      A6 closes, committed, on the same fixture.
#   C2 CONTROL (rollback RED): after supabase/rollbacks/138_…_rollback.sql, the
#      sole-owner lower-role acceptance succeeds and the owner count drops to 0.
# Fixture rows use fixed ids under 13800000-… and are removed at the end.
# SAFETY: loopback only; scrubs remote connection variables; bash 3.2.
# ============================================================================
set -uo pipefail
unset SUPABASE_DB_URL DATABASE_URL PGSERVICE PGPASSWORD PGURL PGDATABASE 2>/dev/null
export PGHOST="${REHEARSAL_PGHOST:-127.0.0.1}" PGPORT="${REHEARSAL_PGPORT:-5432}" PGUSER="${REHEARSAL_PGUSER:-postgres}" PGCONNECT_TIMEOUT=5
case "$PGHOST" in 127.0.0.1|localhost|::1) ;; *) echo "refusing non-loopback host $PGHOST" >&2; exit 1 ;; esac
DB="${1:-snatchit_rehears_138}"
case "$DB" in *rehears*) ;; *) echo "refusing database '$DB': name must contain 'rehears'" >&2; exit 1 ;; esac
ROLLBACK_SQL="$(cd "$(dirname "$0")/.." && pwd)/supabase/rollbacks/138_ops_operator_onboarding_rollback.sql"
MIGRATION_SQL="$(cd "$(dirname "$0")/.." && pwd)/supabase/migrations/138_ops_operator_onboarding.sql"
q() { psql -X -At -v ON_ERROR_STOP=1 -d "$DB" -c "$1"; }
qq() { psql -X -At -d "$DB" -c "$1" 2>&1; }
[ "$(q "select to_regprocedure('kernel.accept_org_invite(uuid,text)') is not null")" = "t" ] || { echo "kernel.accept_org_invite missing in $DB" >&2; exit 1; }
a6_present() { q "select position('owner_role_change' in prosrc) > 0 from pg_proc where oid='kernel.accept_org_invite(uuid,text)'::regprocedure"; }
[ "$(a6_present)" = "t" ] || { echo "138's A6 is not applied to $DB" >&2; exit 1; }

ORG=13800000-0000-0000-0000-0000000000a6
X=13800000-0000-0000-0000-00000000000x; X=13800000-0000-0000-0000-000000000001
Y=13800000-0000-0000-0000-000000000002
Z=13800000-0000-0000-0000-000000000003
fail=0
report() { if [ "$2" = "PASS" ]; then echo "  PASS $1 — $3"; else echo "  FAIL $1 — $3"; fail=1; fi; }
T=$(mktemp -d)
cleanup() {   # org rows only: the three auth.users rows are reused (other tables reference them) and are harmless
  qq "delete from kernel.org_invite where org_id='$ORG';
      delete from kernel.org_member where org_id='$ORG';
      delete from kernel.admin_audit where subject_id='$ORG';
      delete from kernel.organization where org_id='$ORG';" >/dev/null 2>&1
  rm -rf "$T"
}
# the status line of an acceptance: psql prints the tap.login() row, then the status, then CONTEXT/ERROR text
status() { grep -aoE '(^|: )(ok|noop_replay)$|owner_role_change|not_found: invite|insufficient_privilege: [a-z_]+|precondition_failed: [a-z_]+' "$1" | tail -1; }
trap cleanup EXIT
fixture() {   # two owners X and Y, a pending lower-role invite for each, and one org_owner invite for Z
  cleanup; mkdir -p "$T"
  q "insert into auth.users (id, email, aud, role, created_at) values
       ('$X','a6.x@test.local','authenticated','authenticated',now()),
       ('$Y','a6.y@test.local','authenticated','authenticated',now()),
       ('$Z','a6.z@test.local','authenticated','authenticated',now())
     on conflict (id) do nothing;
     insert into kernel.organization (org_id, legal_name, display_name, status) values ('$ORG','A6 Concurrency LLC','A6 Concurrency','active');
     insert into kernel.org_member (org_id, identity_id, role, granted_by, granted_at) values
       ('$ORG','$X','org_owner','$X', now() - interval '30 days'),
       ('$ORG','$Y','org_owner','$X', now() - interval '30 days');
     insert into kernel.org_invite (invite_id, org_id, invitee_ref, invitee_identity_id, role, status, invited_by, expires_at, command_idempotency_key) values
       ('13800000-0000-0000-0000-0000000000f1','$ORG','a6.x@test.local','$X','org_member','pending','$Y', now() + interval '7 days','a6-k1'),
       ('13800000-0000-0000-0000-0000000000f2','$ORG','a6.y@test.local','$Y','org_member','pending','$X', now() + interval '7 days','a6-k2'),
       ('13800000-0000-0000-0000-0000000000f3','$ORG','a6.z@test.local','$Z','org_owner','pending','$X', now() + interval '7 days','a6-k3');" >/dev/null
}
owners() { q "select count(*) from kernel.org_member where org_id='$ORG' and role='org_owner'"; }
accept() { echo "select tap.login('$1'::uuid); select coalesce((kernel.accept_org_invite('$2','$3'))->>'status','(null)');"; }
blocked_on_org() {   # $1 = application_name; true only when the backend is waiting on a LOCK held by someone else
  q "select count(*) > 0 from pg_stat_activity a where a.application_name='$1' and a.wait_event_type='Lock' and cardinality(pg_blocking_pids(a.pid)) > 0"
}

echo "138 A6 two-session proof on $DB (outside pg_prove)"

# S1 FORWARD — the owner-invite acceptance holds the org row; the lower-role acceptance must wait, then refuse
fixture
( psql -X -At -d "$DB" -c "begin; $(accept "$Z" 13800000-0000-0000-0000-0000000000f3 a6-c1) select pg_sleep(4); commit;" > "$T/s1a" 2>&1 ) &
sleep 1
( PGAPPNAME=a6_s1_second psql -X -At -d "$DB" -c "$(accept "$X" 13800000-0000-0000-0000-0000000000f1 a6-c2)" > "$T/s1b" 2>&1 ) &
sleep 1.5; blocked=$(blocked_on_org a6_s1_second); wait
s1a=$(status "$T/s1a"); s1b=$(status "$T/s1b")
case "$s1b" in *owner_role_change*) refused=yes;; *) refused=no;; esac
[ "$blocked" = "t" ] && [ "$s1a" = "ok" ] && [ "$refused" = yes ] && [ "$(owners)" = "3" ] \
  && report S1 PASS "session2 was blocked on the org row (pg_blocking_pids non-empty) while session1's owner acceptance was open; session1=$s1a; session2 refused after the commit; owners=3" \
  || report S1 FAIL "blocked=$blocked session1=$s1a session2=$s1b owners=$(owners)"

# S2 REVERSE — the org row is held first; a legitimate owner acceptance waits, then succeeds
fixture
( psql -X -At -d "$DB" -c "begin; select 1 from kernel.organization where org_id='$ORG' for update; select pg_sleep(4); commit;" > "$T/s2a" 2>&1 ) &
sleep 1
( PGAPPNAME=a6_s2_second psql -X -At -d "$DB" -c "$(accept "$Z" 13800000-0000-0000-0000-0000000000f3 a6-c3)" > "$T/s2b" 2>&1 ) &
sleep 1.5; blocked=$(blocked_on_org a6_s2_second); wait
s2b=$(status "$T/s2b")
[ "$blocked" = "t" ] && [ "$s2b" = "ok" ] && [ "$(owners)" = "3" ] \
  && report S2 PASS "with the org row held, the org_owner acceptance blocked (pg_blocking_pids non-empty) and then succeeded: owners=3 — A6 serialises, it does not refuse legitimate acceptance" \
  || report S2 FAIL "blocked=$blocked session2=$s2b owners=$(owners)"

# S3 RACE — both owners accept lower-role invites at the same moment
fixture
( psql -X -At -d "$DB" -c "$(accept "$X" 13800000-0000-0000-0000-0000000000f1 a6-c4)" > "$T/s3a" 2>&1 ) &
( psql -X -At -d "$DB" -c "$(accept "$Y" 13800000-0000-0000-0000-0000000000f2 a6-c5)" > "$T/s3b" 2>&1 ) &
wait
s3a=$(status "$T/s3a"); s3b=$(status "$T/s3b"); own=$(owners)
case "$s3a$s3b" in *owner_role_change*owner_role_change*) both=yes;; *) both=no;; esac
[ "$both" = yes ] && [ "$own" = "2" ] \
  && report S3 PASS "both concurrent lower-role acceptances refused (owner_role_change); owners still $own" \
  || report S3 FAIL "session1=$s3a session2=$s3b owners=$own"

# C1 CONTROL — the same race with 077's acceptance body (A6 removed)
fixture
q "$(psql -X -At -d "$DB" -c "select prosrc from pg_proc where oid='kernel.accept_org_invite(uuid,text)'::regprocedure" > "$T/a6body"; echo "select 1")" >/dev/null
python3 - "$ROLLBACK_SQL" "$T/077accept.sql" <<'PY'
import sys
src = open(sys.argv[1]).read()
a = src.index('create or replace function kernel.accept_org_invite(')
b = src.index('\n$$;', a) + 4
open(sys.argv[2], 'w').write(src[a:b])   # 077's body, as the rollback file carries it
PY
psql -X -At -q -v ON_ERROR_STOP=1 -d "$DB" -f "$T/077accept.sql" >/dev/null 2>&1
[ "$(a6_present)" = "f" ] || { echo "  FAIL C1 — could not remove A6 for the control"; fail=1; }
( psql -X -At -d "$DB" -c "$(accept "$X" 13800000-0000-0000-0000-0000000000f1 a6-c6)" > "$T/c1a" 2>&1 ) &
( psql -X -At -d "$DB" -c "$(accept "$Y" 13800000-0000-0000-0000-0000000000f2 a6-c7)" > "$T/c1b" 2>&1 ) &
wait
c1a=$(status "$T/c1a"); c1b=$(status "$T/c1b"); own=$(owners)
[ "$c1a" = "ok" ] && [ "$c1b" = "ok" ] && [ "$own" = "0" ] \
  && report C1 PASS "without A6 both acceptances COMMIT and the organisation is left with $own owners — the breach A6 closes" \
  || report C1 FAIL "session1=$c1a session2=$c1b owners=$own (expected ok/ok/0)"
# restore 138 (and A6) before the last scenario
psql -X -At -q -v ON_ERROR_STOP=1 -d "$DB" -f "$MIGRATION_SQL" >/dev/null 2>&1
[ "$(a6_present)" = "t" ] || { echo "  FAIL C2 — 138 did not re-apply after the C1 control"; fail=1; }

# C2 CONTROL (rollback RED) — the SAME fixture the green case uses, before and after the rollback
fixture
qq "delete from kernel.org_member where org_id='$ORG' and identity_id='$Y'" >/dev/null   # X is now the SOLE owner
green=$(psql -X -At -d "$DB" -c "$(accept "$X" 13800000-0000-0000-0000-0000000000f1 a6-c8)" 2>&1); green=$(echo "$green" > "$T/c2a"; status "$T/c2a")
own_green=$(owners)
psql -X -At -q -v ON_ERROR_STOP=1 -d "$DB" -f "$ROLLBACK_SQL" > "$T/c2rb" 2>&1; rb=$?
red=$(psql -X -At -d "$DB" -c "$(accept "$X" 13800000-0000-0000-0000-0000000000f1 a6-c9)" 2>&1); red=$(echo "$red" > "$T/c2b"; status "$T/c2b")
own_red=$(owners)
case "$green" in *owner_role_change*) g=yes;; *) g=no;; esac
[ "$g" = yes ] && [ "$own_green" = "1" ] && [ "$rb" -eq 0 ] && [ "$(a6_present)" = "f" ] && [ "$red" = "ok" ] && [ "$own_red" = "0" ] \
  && report C2 PASS "same fixture: with 138 the sole owner's lower-role acceptance is refused and owners=1; after the rollback the identical call succeeds and owners=$own_red" \
  || report C2 FAIL "green=$green owners=$own_green rollback_exit=$rb a6_after=$(a6_present) red=$red owners=$own_red"

echo "  NOTE: C2 leaves $DB ROLLED BACK (138 removed). Re-apply 138 or restore the database before reusing it."
[ $fail -eq 0 ] && echo "ALL PASS" || echo "FAILURES"
exit $fail
