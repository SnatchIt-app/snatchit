"use client";
import { useActionState } from "react";
import { Button } from "@astryxdesign/core";
import { archivePrelaunchTests, type ArchiveState } from "@/lib/prelaunch-archive-actions";
import { ARCHIVE_CONFIRMATION } from "@/lib/prelaunch-archive";
import { Alert } from "@/components/ui/Alert";

export function PrelaunchArchiveForm({ batchId, digest }: { batchId: string; digest: string }) {
  const [state, action, pending] = useActionState<ArchiveState, FormData>(archivePrelaunchTests, {});
  return <form action={action} className="mt-5 space-y-4">
    <input type="hidden" name="batch_id" value={batchId} /><input type="hidden" name="snapshot_sha256" value={digest} />
    <label className="block text-sm">Cleanup reason<textarea name="reason" required minLength={15} maxLength={2000} className="field mt-1" rows={3} disabled={pending || state.completed} /></label>
    <label className="block text-sm">Type <strong>{ARCHIVE_CONFIRMATION}</strong> to confirm<input name="confirmation" required autoComplete="off" className="field mt-1" disabled={pending || state.completed} /></label>
    <Button type="submit" isDisabled={pending || state.completed} isLoading={pending} label="Move reviewed tests to archive" />
    {state.error ? <Alert state="failed" title={state.error} /> : null}
    {state.completed ? <Alert state="success" title="The reviewed test records were archived." /> : null}
  </form>;
}
