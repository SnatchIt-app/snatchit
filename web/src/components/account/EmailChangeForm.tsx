"use client";

import { useActionState } from "react";
import { updateEmailAction } from "@/lib/auth/actions";
import type { ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";

const initialState: ActionState = {};

export function EmailChangeForm({ currentEmail }: { currentEmail: string | null }) {
  const [state, formAction, isPending] = useActionState(updateEmailAction, initialState);

  if (state.success) {
    return <Alert tone="success">{state.message}</Alert>;
  }

  return (
    <form action={formAction} noValidate className="max-w-[380px] space-y-4">
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}
      <Field label="Current email" htmlFor="currentEmail">
        <Input id="currentEmail" value={currentEmail ?? ""} disabled readOnly />
      </Field>
      <Field label="New email" htmlFor="newEmail" error={state.fieldErrors?.newEmail}>
        <Input id="newEmail" name="newEmail" type="email" autoComplete="email" required />
      </Field>
      <Button type="submit" variant="secondary" disabled={isPending}>
        {isPending ? "Sending…" : "Change email"}
      </Button>
    </form>
  );
}
