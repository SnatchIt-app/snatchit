import { isRecord } from "@/lib/types";
const UUID = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const SHA = /^[0-9a-f]{64}$/;
export const ARCHIVE_CONFIRMATION = "ARCHIVE 57 TEST ORDERS";
export type ArchivedPayment = { id: string; created_at: string; amount: number; total: number; status: string; mode: string };
export type ArchiveBatch = { state: "not_prepared" } | {
  state: "prepared" | "archived"; id: string; snapshot_sha256: string; backup_verified: boolean; execution_ready: boolean;
  prepared_at: string; expires_at: string; archived_at: string | null;
  counts: Record<string, number>; payments: ArchivedPayment[];
};
/** Unknown/malformed answers never unlock maintenance or turn into an empty archive. */
export function parseArchiveBatch(value: unknown): ArchiveBatch | null {
  if (!isRecord(value)) return null;
  if (value.state === "not_prepared") return { state: "not_prepared" };
  if (value.state !== "prepared" && value.state !== "archived") return null;
  if (typeof value.id !== "string" || !UUID.test(value.id) || typeof value.snapshot_sha256 !== "string" || !SHA.test(value.snapshot_sha256)) return null;
  if (typeof value.prepared_at !== "string" || !Number.isFinite(Date.parse(value.prepared_at)) || typeof value.expires_at !== "string" || !Number.isFinite(Date.parse(value.expires_at))) return null;
  if (value.archived_at !== null && (typeof value.archived_at !== "string" || !Number.isFinite(Date.parse(value.archived_at)))) return null;
  if ((value.state === "archived") !== (value.archived_at !== null)) return null;
  if (!isRecord(value.counts) || value.counts["public.payments"] !== 57 || !Array.isArray(value.payments) || value.payments.length !== 57) return null;
  const counts: Record<string, number> = {};
  for (const [key, count] of Object.entries(value.counts)) {
    if (typeof count !== "number" || !Number.isSafeInteger(count) || count < 0) return null;
    counts[key] = count;
  }
  const payments: ArchivedPayment[] = [];
  for (const p of value.payments) {
    if (!isRecord(p) || typeof p.id !== "string" || !UUID.test(p.id) || typeof p.created_at !== "string" || !Number.isFinite(Date.parse(p.created_at)) || typeof p.mode !== "string" || typeof p.status !== "string") return null;
    if (typeof p.amount !== "number" || !Number.isSafeInteger(p.amount) || p.amount < 0 || typeof p.total !== "number" || !Number.isSafeInteger(p.total) || p.total < p.amount) return null;
    if (["d0508a55-84de-40d8-b696-9e0ea4396bb3", "d44d0d3d-90e0-4e3b-a6bd-2769275ec741"].includes(p.id.toLowerCase()) || p.mode === "native_primary") return null;
    payments.push({ id: p.id, created_at: p.created_at, amount: p.amount, total: p.total, status: p.status, mode: p.mode });
  }
  if (new Set(payments.map(p => p.id.toLowerCase())).size !== 57) return null;
  return { state: value.state, id: value.id, snapshot_sha256: value.snapshot_sha256, backup_verified: value.backup_verified === true, execution_ready: value.state === "prepared" && value.backup_verified === true && value.execution_ready === true,
    prepared_at: value.prepared_at, expires_at: value.expires_at, archived_at: value.archived_at, counts, payments };
}
export function buildArchiveArgs(form: FormData): Record<string, string> | null {
  const get = (name: string) => typeof form.get(name) === "string" ? (form.get(name) as string) : "";
  const id = get("batch_id"), sha = get("snapshot_sha256"), reason = get("reason").trim(), confirmation = get("confirmation");
  if (!UUID.test(id) || !SHA.test(sha) || reason.length < 15 || reason.length > 2000 || confirmation !== ARCHIVE_CONFIRMATION) return null;
  return { p_batch: id, p_snapshot_sha256: sha, p_reason: reason, p_confirmation: confirmation };
}
export function isArchiveReceipt(value: unknown, args: Record<string, string>): boolean {
  return isRecord(value) && value.status === "archived" && value.batch_id === args.p_batch && value.snapshot_sha256 === args.p_snapshot_sha256 && isRecord(value.counts) && value.counts["public.payments"] === 57;
}
