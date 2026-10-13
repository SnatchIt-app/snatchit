"use client";

import { useActionState } from "react";
import Link from "next/link";
import { requestPasswordResetAction, type ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";
import { authFootnoteCls, authInlineLinkCls } from "@/components/auth/styles";

const initialState: ActionState = {};

export function ForgotPasswordForm() {
  const [state, formAction, isPending] = useActionState(requestPasswordResetAction, initialState);

  if (state.success) {
    return (
      <Alert tone="success">
        <span aria-live="polite">{state.message}</span>
      </Alert>
    );
  }

  return (
    <form action={formAction} noValidate className="space-y-6">
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}

      <Field label="Email" htmlFor="email">
        <Input id="email" name="email" type="email" autoComplete="email" required />
      </Field>

      <Button type="submit" size="lg" className="w-full" disabled={isPending} pending={isPending} pendingLabel="Sending…">
        Send reset link
      </Button>

      <p className={authFootnoteCls}>
        <Link href="/login" className={authInlineLinkCls}>
          Back to log in
        </Link>
      </p>
    </form>
  );
}
