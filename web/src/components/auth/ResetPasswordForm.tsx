"use client";

import { useActionState } from "react";
import { updatePasswordAction, type ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";

const initialState: ActionState = {};

export function ResetPasswordForm() {
  const [state, formAction, isPending] = useActionState(updatePasswordAction, initialState);

  return (
    <form action={formAction} noValidate className="space-y-5">
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}

      <Field label="New password" htmlFor="password" error={state.fieldErrors?.password} hint="At least 8 characters.">
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          aria-invalid={Boolean(state.fieldErrors?.password)}
          required
        />
      </Field>

      <Field label="Confirm new password" htmlFor="confirmPassword" error={state.fieldErrors?.confirmPassword}>
        <Input
          id="confirmPassword"
          name="confirmPassword"
          type="password"
          autoComplete="new-password"
          aria-invalid={Boolean(state.fieldErrors?.confirmPassword)}
          required
        />
      </Field>

      <Button type="submit" size="lg" className="w-full" disabled={isPending}>
        {isPending ? "Saving…" : "Set new password"}
      </Button>
    </form>
  );
}
