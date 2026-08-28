"use client";

import { useState } from "react";
import { deleteAccountAction } from "@/lib/account-deletion-actions";
import { Alert } from "@/components/ui/Alert";

export function DeleteAccountButton() {
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  // Kept in step with app/settings/index.tsx. See the note there: the previous
  // copy claimed erasure the platform does not perform, and broke the corpus
  // rule against "permanently deleted" / "all associated data" before provable
  // erasure exists.
  async function handleClick() {
    const firstConfirm = window.confirm(
      "Delete account\n\n" +
        "We'll remove your sign-in, your profile and your photos, and cancel any active listings. " +
        "You won't be able to sign in again.\n\n" +
        "We keep a record of past sales and purchases, because they're financial records — " +
        "but they'll no longer be linked to your name.\n\nContinue?",
    );
    if (!firstConfirm) return;

    const finalConfirm = window.confirm(
      "Are you sure?\n\n" +
        "This can't be undone, and you won't be able to get the account back.\n\n" +
        "Delete my account?",
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
      <button
        type="button"
        onClick={handleClick}
        disabled={deleting}
        className="text-[13px] font-semibold text-primary/70 underline decoration-primary/30 hover:text-primary disabled:opacity-50"
      >
        {deleting ? "Deleting…" : "Delete account"}
      </button>
    </div>
  );
}
