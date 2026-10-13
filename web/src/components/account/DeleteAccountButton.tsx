"use client";

import { useState } from "react";
import { deleteAccountAction } from "@/lib/account-deletion-actions";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";

export function DeleteAccountButton() {
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  async function handleClick() {
    const firstConfirm = window.confirm(
      "Delete account\n\nThis will permanently delete your account, profile, and all associated data. Active listings will be cancelled. This cannot be undone.\n\nAre you sure?",
    );
    if (!firstConfirm) return;

    const finalConfirm = window.confirm(
      "Final confirmation\n\nThis action is irreversible. Your account and data will be permanently deleted.\n\nProceed with deletion?",
    );
    if (!finalConfirm) return;

    setDeleting(true);
    setError(null);
    const result = await deleteAccountAction();
    // deleteAccountAction redirects on success, so reaching here means it failed.
    if (result?.error) setError(result.error);
    setDeleting(false);
  }

  return (
    <div className="space-y-3">
      {error ? <Alert tone="error">{error}</Alert> : null}
      <Button
        type="button"
        variant="destructive"
        onClick={handleClick}
        disabled={deleting}
        pending={deleting}
        pendingLabel="Deleting…"
      >
        Delete account
      </Button>
    </div>
  );
}
