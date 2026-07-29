"use client";

import { useActionState } from "react";
import Link from "next/link";
import { signUpAction, type ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";

const initialState: ActionState = {};

export function SignUpForm({ next }: { next: string }) {
  const [state, formAction, isPending] = useActionState(signUpAction, initialState);

  if (state.success) {
    return (
      <Alert tone="success">
        <span aria-live="polite">{state.message}</span>
      </Alert>
    );
  }

  return (
    // Keyed on the error payload so a failed round-trip remounts the form —
    // uncontrolled inputs only pick up a new defaultValue on mount, and we
    // want the user's non-password input preserved after a validation error.
    <form
      key={state.fieldErrors || state.error ? JSON.stringify(state.values) : "initial"}
      action={formAction}
      noValidate
      className="space-y-5"
    >
      <input type="hidden" name="next" value={next} />
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}

      <div className="grid grid-cols-2 gap-4">
        <Field label="First name" htmlFor="firstName" error={state.fieldErrors?.firstName}>
          <Input
            id="firstName"
            name="firstName"
            autoComplete="given-name"
            defaultValue={state.values?.firstName ?? ""}
            aria-invalid={Boolean(state.fieldErrors?.firstName)}
            aria-describedby={state.fieldErrors?.firstName ? "firstName-error" : undefined}
            required
          />
        </Field>
        <Field label="Last name" htmlFor="lastName" error={state.fieldErrors?.lastName}>
          <Input
            id="lastName"
            name="lastName"
            autoComplete="family-name"
            defaultValue={state.values?.lastName ?? ""}
            aria-invalid={Boolean(state.fieldErrors?.lastName)}
            aria-describedby={state.fieldErrors?.lastName ? "lastName-error" : undefined}
            required
          />
        </Field>
      </div>

      <Field label="Email" htmlFor="email" error={state.fieldErrors?.email}>
        <Input
          id="email"
          name="email"
          type="email"
          autoComplete="email"
          defaultValue={state.values?.email ?? ""}
          aria-invalid={Boolean(state.fieldErrors?.email)}
          aria-describedby={state.fieldErrors?.email ? "email-error" : undefined}
          required
        />
      </Field>

      <Field label="Password" htmlFor="password" error={state.fieldErrors?.password} hint="At least 8 characters.">
        <Input
          id="password"
          name="password"
          type="password"
          autoComplete="new-password"
          aria-invalid={Boolean(state.fieldErrors?.password)}
          aria-describedby={state.fieldErrors?.password ? "password-error" : "password-hint"}
          required
        />
      </Field>

      <Field label="Confirm password" htmlFor="confirmPassword" error={state.fieldErrors?.confirmPassword}>
        <Input
          id="confirmPassword"
          name="confirmPassword"
          type="password"
          autoComplete="new-password"
          aria-invalid={Boolean(state.fieldErrors?.confirmPassword)}
          aria-describedby={state.fieldErrors?.confirmPassword ? "confirmPassword-error" : undefined}
          required
        />
      </Field>

      <div>
        <label htmlFor="acceptedTerms" className="flex items-start gap-3 py-1 text-[13px] leading-relaxed text-white/70">
          <input
            id="acceptedTerms"
            name="acceptedTerms"
            type="checkbox"
            className="mt-0.5 size-[18px] shrink-0 accent-[#ff1a1a]"
            aria-invalid={Boolean(state.fieldErrors?.acceptedTerms)}
            aria-describedby={state.fieldErrors?.acceptedTerms ? "acceptedTerms-error" : undefined}
          />
          <span>
            I agree to the{" "}
            <a href="https://snatchitapp.com/terms" target="_blank" rel="noopener noreferrer" className="text-primary underline underline-offset-2 hover:text-[#ff5f5f]">
              Terms
            </a>{" "}
            and{" "}
            <a href="https://snatchitapp.com/privacy" target="_blank" rel="noopener noreferrer" className="text-primary underline underline-offset-2 hover:text-[#ff5f5f]">
              Privacy Policy
            </a>
            .
          </span>
        </label>
        {state.fieldErrors?.acceptedTerms ? (
          <p id="acceptedTerms-error" role="alert" className="mt-2 text-[12.5px] font-medium text-primary">
            {state.fieldErrors.acceptedTerms}
          </p>
        ) : null}
      </div>

      <Button type="submit" size="lg" className="w-full" disabled={isPending}>
        {isPending ? "Creating account…" : "Create account"}
      </Button>

      <p className="text-center text-[13px] text-white/50">
        Already have an account?{" "}
        <Link href={`/login?next=${encodeURIComponent(next)}`} className="font-semibold text-primary hover:text-[#ff5f5f]">
          Log in
        </Link>
      </p>
    </form>
  );
}
