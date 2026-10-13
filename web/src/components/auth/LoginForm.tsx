"use client";

import { useActionState } from "react";
import Link from "next/link";
import { signInAction, type ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";
import { authFootnoteCls, authInlineLinkCls } from "@/components/auth/styles";

const initialState: ActionState = {};

export function LoginForm({ next, banner }: { next: string; banner?: string }) {
  const [state, formAction, isPending] = useActionState(signInAction, initialState);

  return (
    <form
      key={state.error ? state.values?.email ?? "error" : "initial"}
      action={formAction}
      noValidate
      className="space-y-6"
    >
      <input type="hidden" name="next" value={next} />
      {banner && !state.error ? <Alert tone="success">{banner}</Alert> : null}
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}

      <Field label="Email" htmlFor="email">
        <Input id="email" name="email" type="email" autoComplete="email" defaultValue={state.values?.email ?? ""} required />
      </Field>

      <div>
        <Field label="Password" htmlFor="password">
          <Input id="password" name="password" type="password" autoComplete="current-password" required />
        </Field>
        <div className="mt-1 flex justify-end">
          <Link
            href="/forgot-password"
            className="-mr-1 inline-flex min-h-11 items-center px-1 text-[14px] font-semibold text-muted underline-offset-4 hover:text-ink hover:underline"
          >
            Forgot password?
          </Link>
        </div>
      </div>

      <Button type="submit" size="lg" className="w-full" disabled={isPending} pending={isPending} pendingLabel="Logging in…">
        Log in
      </Button>

      <p className={authFootnoteCls}>
        New to Snatch It?{" "}
        <Link href={`/signup?next=${encodeURIComponent(next)}`} className={authInlineLinkCls}>
          Create an account
        </Link>
      </p>
    </form>
  );
}
