/**
 * src/lib/tickets/entitlementStore.ts — the one in-memory cache of the signed-in account's
 * entitlements (per-atom rows per event session) and minted credentials (per atom).
 *
 * PER ACCOUNT, MEMORY ONLY (Q04). Mirrors src/lib/saved/savedStore.ts: the store records its
 * owner, answers only for that owner, and empties on ANY owner change — sign-out included
 * (`bindEntitlementOwner(null)`). A write for an account that is not the bound owner is dropped,
 * so a late result from a previous account can neither land in the new account's view nor be read
 * back after a switch. Nothing here touches disk: a token never outlives the process, and the
 * screen re-mints on open anyway (entitlement.ts `credentialStale`).
 *
 * Dependency-free: the auth wiring that calls `bindEntitlementOwner` lives in entitlementReads.ts.
 */
import type { Credential, MyTicketAtom } from './entitlement';

let owner: string | null = null;
let generation = 0;
const atomsBySession = new Map<string, MyTicketAtom[]>();
const credentials = new Map<string, { credential: Credential; receivedAtMs: number }>();
const listeners = new Set<() => void>();

function emit(): void {
  for (const l of [...listeners]) l();
}

/** The account whose entitlements this store holds. A different id (or null: signed out) empties it. */
export function bindEntitlementOwner(userId: string | null | undefined): void {
  const next = userId || null;
  if (next === owner) return;
  owner = next;
  generation += 1;
  atomsBySession.clear();
  credentials.clear();
  emit();
}

/** Bumped on every owner change, so a read sent under an earlier owner can tell it is stale. */
export function entitlementGeneration(): number {
  return generation;
}

export function storeAtoms(userId: string, eventSessionId: string, atoms: MyTicketAtom[]): void {
  if (!owner || userId !== owner) return;
  atomsBySession.set(eventSessionId, atoms);
  emit();
}

export function readAtoms(userId: string, eventSessionId: string): MyTicketAtom[] | null {
  if (!owner || userId !== owner) return null;
  return atomsBySession.get(eventSessionId) ?? null;
}

export function storeCredential(userId: string, atomId: string, credential: Credential, receivedAtMs: number): void {
  if (!owner || userId !== owner) return;
  credentials.set(atomId, { credential, receivedAtMs });
  emit();
}

export function readCredential(userId: string, atomId: string): { credential: Credential; receivedAtMs: number } | null {
  if (!owner || userId !== owner) return null;
  return credentials.get(atomId) ?? null;
}

export function dropCredential(userId: string, atomId: string): void {
  if (!owner || userId !== owner) return;
  if (credentials.delete(atomId)) emit();
}

export function subscribeEntitlements(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}
