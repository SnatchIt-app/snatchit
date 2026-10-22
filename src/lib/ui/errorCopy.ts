/**
 * src/lib/ui/errorCopy.ts — what a dialog says when an action fails and the server has no sentence
 * for the person (CFT-703). These failures are RLS, network or constraint strings, which were shown
 * verbatim. The raw text goes to the log; the person gets one calm line. Server refusals that DO
 * carry a reason keep their own catalogue (src/lib/moderation/serverRefusal.ts).
 */
export const ACTION_FAILED_COPY = {
  block: { title: 'Could not block', body: "We couldn't block this account. Please try again." },
  unblock: { title: 'Could not unblock', body: "We couldn't unblock this account. Please try again." },
  photo: { title: 'Save failed', body: "Your new photo wasn't saved. Please try again." },
  delivery: { title: "Couldn't save your details", body: "Your delivery details weren't saved. Please try again." },
} as const;
