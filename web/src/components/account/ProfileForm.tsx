"use client";

import { useActionState } from "react";
import { updateProfileAction } from "@/lib/profile-actions";
import type { ActionState } from "@/lib/auth/actions";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { Alert } from "@/components/ui/Alert";
import { Button } from "@/components/ui/Button";
import type { MyProfile } from "@/lib/profile";

const initialState: ActionState = {};

export function ProfileForm({ profile }: { profile: MyProfile }) {
  const [state, formAction, isPending] = useActionState(updateProfileAction, initialState);

  return (
    <form action={formAction} noValidate className="max-w-[440px] space-y-5">
      {state.error ? <Alert tone="error">{state.error}</Alert> : null}
      {state.success ? <Alert tone="success">{state.message}</Alert> : null}

      <Field label="Display name" htmlFor="displayName" error={state.fieldErrors?.displayName} hint="Shown to other users.">
        <Input id="displayName" name="displayName" defaultValue={profile.display_name ?? ""} required />
      </Field>

      <Field label="Full name" htmlFor="fullName" error={state.fieldErrors?.fullName}>
        <Input id="fullName" name="fullName" defaultValue={profile.full_name ?? ""} />
      </Field>

      <Field label="Phone number" htmlFor="phoneNumber" error={state.fieldErrors?.phoneNumber} hint="Not used to sign in.">
        <Input id="phoneNumber" name="phoneNumber" type="tel" defaultValue={profile.phone_number ?? ""} autoComplete="tel" />
      </Field>

      <Field label="Email" htmlFor="email" hint="Change your email from Settings.">
        <Input id="email" value={profile.email ?? ""} disabled readOnly />
      </Field>

      <Button type="submit" disabled={isPending}>
        {isPending ? "Saving…" : "Save changes"}
      </Button>
    </form>
  );
}
