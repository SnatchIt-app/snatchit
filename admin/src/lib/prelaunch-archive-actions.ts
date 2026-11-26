"use server";
import { revalidatePath } from "next/cache";
import { requireOperator } from "@/lib/auth/session";
import { callOps } from "@/lib/ops";
import { buildArchiveArgs, isArchiveReceipt } from "@/lib/prelaunch-archive";
export type ArchiveState = { error?: string; completed?: boolean };
export async function archivePrelaunchTests(_previous: ArchiveState, form: FormData): Promise<ArchiveState> {
  const operator = await requireOperator();
  if (operator.role !== "platform_admin") return { error: "Only a platform admin can run this cleanup." };
  const args = buildArchiveArgs(form);
  if (!args) return { error: "Enter the exact confirmation and a reason of 15–2,000 characters. Refresh if the preview changed." };
  const result = await callOps<unknown>("prelaunch_archive_execute", args);
  if (!result.ok) return { error: "Cleanup was not confirmed. Refresh this page to check the current batch; no success is assumed." };
  if (!isArchiveReceipt(result.data, args)) return { error: "The server did not return the exact archive receipt. Refresh to check the batch before trying again." };
  for (const path of ["/system/prelaunch-archive", "/orders", "/cases", "/money", "/system", "/"]) revalidatePath(path);
  return { completed: true };
}
