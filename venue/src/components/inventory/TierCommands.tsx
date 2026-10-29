"use client";

import { useActionState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import type { CommandFormState } from "@/lib/db/command-forms";
import { createInventoryBatchForm, createTicketTypeForm, setBatchCapacityForm, setTicketTypePriceForm, setTicketTypeRankForm, setTicketTypeSaleWindowForm, setTicketTypeVisibilityForm } from "@/lib/db/command-forms";
import { RELEASE_LABEL, capacityFloor } from "@/lib/inventory";
import { usd } from "@/lib/format";
import type { InventoryBatch, TicketType } from "@/lib/types";

/**
 * The tier and capacity commands (S1), rendered only when the page decided the command gate is open and
 * the role may edit. Every form carries the command key the server page minted for it; a retry re-sends
 * the same key. The server's answer is shown as what it is: a receipt, a refusal naming the field, or
 * "not enabled". Nothing is marked saved without a receipt.
 */
export type TierCommandKeys = { create: string; price: Record<string, string>; visibility: Record<string, string>; rank: Record<string, string>; capacity: Record<string, string>; release: Record<string, string>; saleWindow: Record<string, string> };
export type TierCommandIds = { orgId: string; venueId: string; eventId: string };

const INITIAL: CommandFormState = { result: null };

function Outcome({ state }: { state: CommandFormState }) {
  const r = state.result;
  if (!r) return null;
  if (r.kind === "ok") {
    const replay = r.result.status === "noop_replay" || r.result.status === "noop";
    return (
      <p className="mt-2 text-sm text-success" role="status">
        {replay ? "Already applied (the server replayed this command as a no-op)." : "Saved. The server recorded the change."}
      </p>
    );
  }
  if (r.kind === "refused")
    return (
      <p className="mt-2 text-sm text-danger" role="alert">
        {r.field ? `${r.field}: ` : ""}
        {r.message}
      </p>
    );
  return (
    <p className="mt-2 text-sm text-warning" role="alert">
      {r.message}
    </p>
  );
}

function Hidden({ ids, commandKey, extra }: { ids: TierCommandIds; commandKey: string; extra?: Record<string, string> }) {
  return (
    <>
      <input type="hidden" name="orgId" value={ids.orgId} />
      <input type="hidden" name="venueId" value={ids.venueId} />
      <input type="hidden" name="eventId" value={ids.eventId} />
      <input type="hidden" name="commandKey" value={commandKey} />
      {extra ? Object.entries(extra).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />) : null}
    </>
  );
}

function CommandForm({ action, ids, commandKey, extra, label, children }: { action: (prev: CommandFormState, fd: FormData) => Promise<CommandFormState>; ids: TierCommandIds; commandKey: string; extra?: Record<string, string>; label: string; children: ReactNode }) {
  const router = useRouter();
  const [state, formAction, pending] = useActionState<CommandFormState, FormData>(
    async (prev, fd) => {
      const next = await action(prev, fd);
      if (next.result?.kind === "ok") router.refresh();
      return next;
    },
    INITIAL,
  );
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" aria-label={label}>
      <Hidden ids={ids} commandKey={commandKey} extra={extra} />
      {children}
      <button type="submit" disabled={pending} className="btn btn-soft btn-sm min-h-11">
        {pending ? "Sending…" : label}
      </button>
      <div className="basis-full">
        <Outcome state={state} />
      </div>
    </form>
  );
}

const Reason = () => (
  <label className="block text-xs">
    Reason
    <input name="reasonCode" required maxLength={80} className="field mt-1" placeholder="opening_ga" />
  </label>
);

export function TierCommands({ ids, types, batches, keys, sessionId, timeZone }: { ids: TierCommandIds; types: TicketType[]; batches: InventoryBatch[]; keys: TierCommandKeys; sessionId: string | null; timeZone: string | null }) {
  return (
    <section className="panel space-y-6 px-5 py-5" aria-labelledby="tier-commands-title">
      <div>
        <h2 id="tier-commands-title" className="text-base font-semibold text-ink">Change tiers and capacity</h2>
        <p className="mt-1 text-sm text-dim">Each change is a command the server audits under your name; a refusal says why. Capacity never goes below what is already held or sold.</p>
      </div>
      {types.map((t) => (
        <div key={t.ticketTypeId} className="space-y-3 border-t border-line pt-4">
          <p className="font-semibold">
            {t.name} <span className="text-dim">· {usd(t.priceMinor)} · {t.visibility.replace("_", " ")}</span>
          </p>
          <CommandForm action={setTicketTypePriceForm} ids={ids} commandKey={keys.price[t.ticketTypeId] ?? ""} extra={{ ticketTypeId: t.ticketTypeId }} label="Set price">
            <label className="block text-xs">
              Price (USD)
              <input name="price" type="number" step="0.01" min="0.01" required defaultValue={(t.priceMinor / 100).toFixed(2)} className="field mt-1 w-28" />
            </label>
            <Reason />
          </CommandForm>
          <CommandForm action={setTicketTypeVisibilityForm} ids={ids} commandKey={keys.visibility[t.ticketTypeId] ?? ""} extra={{ ticketTypeId: t.ticketTypeId }} label="Set visibility">
            <label className="block text-xs">
              Visibility
              <select name="visibility" defaultValue={t.visibility} className="field mt-1">
                <option value="hidden">Hidden</option>
                <option value="public">Public</option>
                <option value="door_only">Door only</option>
              </select>
            </label>
            <Reason />
          </CommandForm>
          <CommandForm action={setTicketTypeRankForm} ids={ids} commandKey={keys.rank[t.ticketTypeId] ?? ""} extra={{ ticketTypeId: t.ticketTypeId }} label="Set rank">
            <label className="block text-xs">
              Display rank (0 first)
              <input name="displayRank" type="number" min="0" max="999" step="1" required className="field mt-1 w-24" />
            </label>
          </CommandForm>
          {/* The first inventory release for this tier on this session. Without one, publish_event refuses
              empty_inventory — the gap D found. No shard control: 081:355 refuses any shard count above 0
              (sharding_deferred), so the only legal value is the one the action sends. */}
          {sessionId ? (
            <CommandForm action={createInventoryBatchForm} ids={ids} commandKey={keys.release[t.ticketTypeId] ?? ""} extra={{ ticketTypeId: t.ticketTypeId, sessionId }} label="Release inventory">
              <label className="block text-xs">
                Release
                <select name="releaseKind" defaultValue="public_sale" className="field mt-1">
                  {(Object.keys(RELEASE_LABEL) as Array<keyof typeof RELEASE_LABEL>).map((k) => (
                    <option key={k} value={k}>{RELEASE_LABEL[k]}</option>
                  ))}
                </select>
              </label>
              <label className="block text-xs">
                Capacity
                <input name="capacity" type="number" min={1} step="1" required className="field mt-1 w-28" />
              </label>
              <p className="text-[0.6875rem] text-dim">Releasing twice releases the inventory twice, and sending it again does not undo it. If no answer arrives, reload and look before trying again.</p>
            </CommandForm>
          ) : null}
          {/* 162's sale window. The organizer types the venue's local wall clock; the server is given an offset. */}
          <CommandForm action={setTicketTypeSaleWindowForm} ids={ids} commandKey={keys.saleWindow[t.ticketTypeId] ?? ""} extra={{ ticketTypeId: t.ticketTypeId, timeZone: timeZone ?? "" }} label="Set the sale window">
            <label className="block text-xs">
              On sale from{timeZone ? ` (${timeZone})` : ""}
              <input name="saleStartsLocal" type="datetime-local" className="field mt-1" />
            </label>
            <label className="block text-xs">
              Until (exclusive)
              <input name="saleEndsLocal" type="datetime-local" className="field mt-1" />
            </label>
            <Reason />
            <p className="text-[0.6875rem] text-dim">Leave a side empty to leave it open; empty both to clear the window.</p>
          </CommandForm>
          {batches
            .filter((b) => b.ticketTypeId === t.ticketTypeId && (!sessionId || b.sessionId === sessionId))
            .map((b) => (
              <CommandForm key={b.batchId} action={setBatchCapacityForm} ids={ids} commandKey={keys.capacity[b.batchId] ?? ""} extra={{ batchId: b.batchId }} label={`Set capacity · ${RELEASE_LABEL[b.releaseKind]}`}>
                <label className="block text-xs">
                  Capacity ({RELEASE_LABEL[b.releaseKind]}){b.countersKnown === false ? "" : `, floor ${capacityFloor(b)}`}
                  <input name="newCapacity" type="number" min={b.countersKnown === false ? 0 : capacityFloor(b)} step="1" required defaultValue={b.countersKnown === false ? "" : b.capacity} className="field mt-1 w-28" />
                </label>
                <Reason />
              </CommandForm>
            ))}
        </div>
      ))}
      <div className="border-t border-line pt-4">
        <p className="font-semibold">Add a ticket type</p>
        <CommandForm action={createTicketTypeForm} ids={ids} commandKey={keys.create} label="Add ticket type">
          <label className="block text-xs">
            Kind
            <select name="kind" defaultValue="admission" className="field mt-1">
              <option value="admission">Admission</option>
              <option value="table">Table (deposit)</option>
            </select>
          </label>
          <label className="block text-xs">
            Name
            <input name="name" required maxLength={80} className="field mt-1" placeholder="General admission" />
          </label>
          <label className="block text-xs">
            Price (USD)
            <input name="price" type="number" step="0.01" min="0.01" required className="field mt-1 w-28" placeholder="25.00" />
          </label>
          <label className="block text-xs">
            Visibility
            <select name="visibility" defaultValue="hidden" className="field mt-1">
              <option value="hidden">Hidden</option>
              <option value="public">Public</option>
              <option value="door_only">Door only</option>
            </select>
          </label>
        </CommandForm>
      </div>
    </section>
  );
}
