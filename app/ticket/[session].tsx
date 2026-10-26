/**
 * app/ticket/[session].tsx — the buyer's tickets for one event session, with an entry code per
 * admission entitlement (Q02–Q05; 2026-10-26 sprint, lane C).
 *
 * Reads (all owner-scoped on the server):
 *   - public.get_my_tickets()                      the event facts and the quantity the person was told
 *   - public.get_my_ticket_atoms(session)          one row per entitlement            (registry 182, PENDING)
 *   - public.get_my_primary_orders(session)        paid-but-unissued → "Issuance pending" (registry 182, PENDING)
 *   - edge credential-sign { ticket_atom_id }      the code, minted for the owner, held in memory only
 *
 * Rules the route enforces (entitlement.ts / entitlementStore.ts carry the tests):
 *   - the cache is bound to the signed-in account and emptied on sign-out or an account change; a
 *     result that lands after the account changed is dropped (generation check);
 *   - a code is minted on arrival for each ready atom, again on focus when the server TTL has
 *     elapsed on a MONOTONIC clock, and whenever the atom's credential_version moved on; a wall-clock
 *     comparison against `not_after` is never made on the device;
 *   - a failed re-read keeps what is on screen (refreshPolicy); a first failure is the failure screen,
 *     never "no tickets";
 *   - nothing is written to disk.
 */
import { useFocusEffect } from '@react-navigation/native';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useRef, useState } from 'react';

import { useAuth } from '@/src/hooks/useAuth';
import { useNetworkStatus } from '@/src/hooks/useNetworkStatus';
import { supabase } from '@/src/lib/supabase';
import {
  credentialStale,
  detailState,
  entitlementDisplay,
  type AtomsLoad,
  type CredentialState,
  type IssuanceHint,
  type MyTicketAtom,
} from '@/src/lib/tickets/entitlement';
import {
  atomsRpc,
  issuanceHint,
  mintCredential,
  ordersRpc,
  readMyAtoms,
  readMyPrimaryOrders,
  supabaseInvoker,
  watchEntitlementSignOut,
} from '@/src/lib/tickets/entitlementReads';
import {
  bindEntitlementOwner,
  entitlementGeneration,
  readAtoms,
  readCredential,
  storeAtoms,
  storeCredential,
} from '@/src/lib/tickets/entitlementStore';
import { classifyTicketsError } from '@/src/lib/tickets/ticketState';
import type { MyTicketGroup } from '@/src/lib/tickets/types';
import { TicketDetailView } from '@/src/screens/tickets/TicketDetailView';

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
/** Monotonic milliseconds: the TTL check must not move with the wall clock. */
const monotonicMs = (): number =>
  typeof performance !== 'undefined' && typeof performance.now === 'function' ? performance.now() : Date.now();
const TTL_SWEEP_MS = 15_000;

type Credentials = Record<string, CredentialState>;

export default function TicketDetailRoute() {
  const { session } = useLocalSearchParams<{ session?: string }>();
  const sessionId = typeof session === 'string' && UUID_RE.test(session) ? session : null;
  const { user, loading: authLoading } = useAuth();
  const userId = user?.id ?? null;
  const { isOffline } = useNetworkStatus();
  const offlineRef = useRef(isOffline);
  useEffect(() => { offlineRef.current = isOffline; }, [isOffline]);

  const [group, setGroup] = useState<MyTicketGroup | null>(null);
  const [expected, setExpected] = useState(0);
  const [load, setLoad] = useState<AtomsLoad>({ kind: 'loading' });
  const [hint, setHint] = useState<IssuanceHint>('unknown');
  const [credentials, setCredentials] = useState<Credentials>({});
  const [refreshing, setRefreshing] = useState(false);
  // Only the newest read may write the screen.
  const requestRef = useRef(0);
  // Atoms with a mint in flight, so arrival + focus cannot ask twice for the same atom.
  const mintingRef = useRef(new Set<string>());

  useEffect(() => { watchEntitlementSignOut(); }, []);
  useEffect(() => { if (!authLoading) bindEntitlementOwner(userId); }, [authLoading, userId]);

  const mint = useCallback(async (atomId: string) => {
    if (!userId || mintingRef.current.has(atomId)) return;
    mintingRef.current.add(atomId);
    const gen = entitlementGeneration();
    setCredentials((prev) => ({ ...prev, [atomId]: { kind: 'minting' } }));
    const r = await mintCredential(supabaseInvoker, atomId);
    mintingRef.current.delete(atomId);
    // The account changed while the edge answered: the answer belongs to nobody on screen.
    if (gen !== entitlementGeneration()) return;
    if (r.ok) {
      const receivedAtMs = monotonicMs();
      storeCredential(userId, atomId, r.credential, receivedAtMs);
      setCredentials((prev) => ({ ...prev, [atomId]: { kind: 'ready', credential: r.credential, receivedAtMs } }));
    } else {
      setCredentials((prev) => ({ ...prev, [atomId]: { kind: 'refused', reason: r.reason } }));
    }
  }, [userId]);

  /** Drops credentials the TTL or a version change has made stale; the arrival effect re-mints. */
  const sweepStale = useCallback((atoms: MyTicketAtom[]) => {
    const now = monotonicMs();
    setCredentials((prev) => {
      let changed = false;
      const next: Credentials = { ...prev };
      for (const a of atoms) {
        const c = next[a.ticket_atom_id];
        if (c && credentialStale(c, now, a.credential_version)) { delete next[a.ticket_atom_id]; changed = true; }
      }
      return changed ? next : prev;
    });
  }, []);

  const readAll = useCallback(async () => {
    if (!userId || !sessionId) return;
    const request = ++requestRef.current;
    const gen = entitlementGeneration();
    const [groups, atomsLoad, orders] = await Promise.all([
      supabase.rpc('get_my_tickets'),
      readMyAtoms(atomsRpc, sessionId, offlineRef.current),
      readMyPrimaryOrders(ordersRpc, sessionId),
    ]);
    if (request !== requestRef.current || gen !== entitlementGeneration()) return;

    if (groups.error) {
      if (classifyTicketsError(groups.error) === 'auth') {
        setLoad({ kind: 'failed', failure: 'signed_out' });
        return;
      }
      // The facts read failed but the atoms read may have answered: keep whatever facts are shown.
    } else {
      const mine = ((groups.data ?? []) as MyTicketGroup[]).filter((r) => r.event_session_id === sessionId);
      setGroup(mine[0] ?? null);
      setExpected(mine.reduce((n, r) => n + (r.quantity ?? 0), 0));
    }
    setHint(issuanceHint(orders));
    if (atomsLoad.kind === 'ready') {
      storeAtoms(userId, sessionId, atomsLoad.atoms);
      sweepStale(atomsLoad.atoms);
      setLoad(atomsLoad);
    } else {
      // A failed re-read keeps the rows on screen; only a first read becomes the failure screen.
      setLoad((prev) => (prev.kind === 'ready' ? prev : atomsLoad));
    }
  }, [userId, sessionId, sweepStale]);

  // First read per account: paint from this account's in-memory cache first, then read.
  useEffect(() => {
    if (authLoading) return;
    setCredentials({});
    mintingRef.current.clear();
    if (!userId) { setLoad({ kind: 'failed', failure: 'signed_out' }); return; }
    if (!sessionId) { setLoad({ kind: 'failed', failure: 'unavailable' }); return; }
    const cached = readAtoms(userId, sessionId);
    if (cached) {
      const primed: Credentials = {};
      for (const a of cached) {
        const c = readCredential(userId, a.ticket_atom_id);
        if (c) primed[a.ticket_atom_id] = { kind: 'ready', credential: c.credential, receivedAtMs: c.receivedAtMs };
      }
      setCredentials(primed);
      setLoad({ kind: 'ready', atoms: cached });
      sweepStale(cached);
    } else {
      setLoad({ kind: 'loading' });
    }
    void readAll();
  }, [authLoading, userId, sessionId, readAll, sweepStale]);

  // Back on this screen: re-read quietly and let the TTL sweep drop anything stale.
  useFocusEffect(
    useCallback(() => {
      if (!userId || !sessionId) return;
      if (load.kind === 'ready') sweepStale(load.atoms);
      void readAll();
      const timer = setInterval(() => { if (load.kind === 'ready') sweepStale(load.atoms); }, TTL_SWEEP_MS);
      return () => clearInterval(timer);
    }, [userId, sessionId, load, readAll, sweepStale]),
  );

  // Arrival: every ready atom without a credential state asks the server for its code, once.
  useEffect(() => {
    if (load.kind !== 'ready') return;
    for (const a of load.atoms) {
      if (entitlementDisplay(a) === 'ready' && !credentials[a.ticket_atom_id]) void mint(a.ticket_atom_id);
    }
  }, [load, credentials, mint]);

  async function onRefresh() {
    setRefreshing(true);
    await readAll();
    setRefreshing(false);
  }

  return (
    <TicketDetailView
      group={group}
      facts={null}
      state={detailState(load, hint, expected)}
      credentials={credentials}
      refreshing={refreshing}
      onRefresh={onRefresh}
      onShowCode={(atomId) => { void mint(atomId); }}
      onEncodeFailure={(atomId) => setCredentials((prev) => ({ ...prev, [atomId]: { kind: 'refused', reason: 'unavailable' } }))}
      onSignIn={() => router.replace('/(auth)/login')}
      onBack={() => router.back()}
    />
  );
}
