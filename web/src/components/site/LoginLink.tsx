"use client";

import Link from "next/link";
import { usePathname, useSearchParams } from "next/navigation";
import { loginHrefFor } from "@/lib/auth/login-href";

/** The header's "Log in": comes back to this page (and its filters) after signing in. */
export function LoginLink({ className }: { className: string }) {
  const pathname = usePathname();
  const searchParams = useSearchParams();
  return (
    <Link href={loginHrefFor(pathname, searchParams.toString())} className={className}>
      Log in
    </Link>
  );
}
