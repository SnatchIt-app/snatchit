"use client";

import { useActionState, useEffect, useRef, type FormEvent } from "react";
import { signInAction, type LoginState } from "@/lib/auth/actions";
import { Alert } from "@/components/ui/Alert";

export function LoginForm({ next }: { next: string }) {
  const [state, formAction, isPending] = useActionState<LoginState, FormData>(signInAction, {});
  // While a sign-in is pending a second submit is cancelled (the ref also holds a
  // same-tick double press); the button stays focusable so focus is not lost.
  const inFlight = useRef(false);
  useEffect(() => {
    if (!isPending) inFlight.current = false;
  }, [isPending, state]);
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    if (isPending || inFlight.current) {
      e.preventDefault();
      return;
    }
    inFlight.current = true;
  };
  return (
    <form action={formAction} onSubmit={onSubmit} noValidate className="space-y-4">
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
      <button type="submit" aria-disabled={isPending} aria-busy={isPending} onClick={(e) => isPending && e.preventDefault()} className="btn btn-primary btn-lg w-full">
        {isPending ? "Signing in…" : "Continue"}
      </button>
    </form>
  );
}
