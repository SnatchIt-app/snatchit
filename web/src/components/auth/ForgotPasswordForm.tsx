"use client";

import { useActionState } from "react";
import Link from "next/link";
import { requestPasswordResetAction, type ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";

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
    <form action={formAction} noValidate className="space-y-5">
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}

      <Field label="Email" htmlFor="email">
        <Input id="email" name="email" type="email" autoComplete="email" required />
      </Field>

      <Button type="submit" size="lg" className="w-full" disabled={isPending}>
        {isPending ? "Sending…" : "Send reset link"}
      </Button>

      <p className="text-center text-[13px] text-white/50">
        <Link href="/login" className="font-semibold text-primary hover:text-[#ff5f5f]">
          Back to log in
        </Link>
      </p>
    </form>
  );
}
