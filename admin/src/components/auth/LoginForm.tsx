"use client";

import { useActionState } from "react";
import { signInAction, type LoginState } from "@/lib/auth/actions";
import { Alert } from "@/components/ui/Alert";

export function LoginForm({ next }: { next: string }) {
  const [state, formAction, isPending] = useActionState<LoginState, FormData>(signInAction, {});
  return (
    <form action={formAction} noValidate className="space-y-4">
      <input type="hidden" name="next" value={next} />
      {state.error ? <Alert state="failed" title={state.error} compact /> : null}
      <div>
        <label htmlFor="email" className="eyebrow block text-dim">
          Email
        </label>
        <input id="email" name="email" type="email" autoComplete="username" required defaultValue={state.values?.email ?? ""} className="field mt-1" />
      </div>
      <div>
        <label htmlFor="password" className="eyebrow block text-dim">
          Password
        </label>
        <input id="password" name="password" type="password" autoComplete="current-password" required className="field mt-1" />
      </div>
      <button type="submit" disabled={isPending} className="btn btn-primary w-full">
        {isPending ? "Signing in…" : "Continue"}
      </button>
    </form>
  );
}
