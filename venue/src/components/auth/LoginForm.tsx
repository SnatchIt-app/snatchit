"use client";

import { useActionState } from "react";
import { signInAction, type LoginState } from "@/lib/auth/actions";

export function LoginForm({ next }: { next: string }) {
  const [state, formAction, isPending] = useActionState<LoginState, FormData>(signInAction, {});
  return (
    <form action={formAction} noValidate className="space-y-4">
      <input type="hidden" name="next" value={next} />
      {state.error ? (
        <p className="border border-danger/50 bg-primary-soft px-3 py-2 text-sm" role="alert">
          {state.error}
        </p>
      ) : null}
      <label className="block text-sm">
        <span className="eyebrow block text-dim">Email</span>
        <input name="email" type="email" autoComplete="username" required defaultValue={state.values?.email ?? ""} className="field mt-1" />
      </label>
      <label className="block text-sm">
        <span className="eyebrow block text-dim">Password</span>
        <input name="password" type="password" autoComplete="current-password" required className="field mt-1" />
      </label>
      <button type="submit" disabled={isPending} className="btn btn-primary w-full">
        {isPending ? "Signing in…" : "Continue"}
      </button>
    </form>
  );
}
