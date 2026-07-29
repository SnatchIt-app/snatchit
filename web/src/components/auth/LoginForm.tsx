"use client";

import { useActionState } from "react";
import Link from "next/link";
import { signInAction, type ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";

const initialState: ActionState = {};

export function LoginForm({ next, banner }: { next: string; banner?: string }) {
  const [state, formAction, isPending] = useActionState(signInAction, initialState);

  return (
    <form
      key={state.error ? state.values?.email ?? "error" : "initial"}
      action={formAction}
      noValidate
      className="space-y-5"
    >
      <input type="hidden" name="next" value={next} />
      {banner && !state.error ? <Alert tone="success">{banner}</Alert> : null}
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}

      <Field label="Email" htmlFor="email">
        <Input id="email" name="email" type="email" autoComplete="email" defaultValue={state.values?.email ?? ""} required />
      </Field>

      <Field label="Password" htmlFor="password">
        <Input id="password" name="password" type="password" autoComplete="current-password" required />
      </Field>

      <div className="flex justify-end">
        <Link href="/forgot-password" className="text-[12.5px] font-medium text-white/50 hover:text-primary">
          Forgot password?
        </Link>
      </div>

      <Button type="submit" size="lg" className="w-full" disabled={isPending}>
        {isPending ? "Logging in…" : "Log in"}
      </Button>

      <p className="text-center text-[13px] text-white/50">
        New to Snatch It?{" "}
        <Link href={`/signup?next=${encodeURIComponent(next)}`} className="font-semibold text-primary hover:text-[#ff5f5f]">
          Create an account
        </Link>
      </p>
    </form>
  );
}
