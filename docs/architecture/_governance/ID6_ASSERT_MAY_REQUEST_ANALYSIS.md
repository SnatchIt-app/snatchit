# `ID-6` — `venue.assert_may_request`: the grant-class contradiction, analyzed (Phase D6, 2026-08-29)

**Verdict: OWNER DECISION REQUIRED — one bit. This is NOT `record_money_denial`'s class, and `X-8`
remains RESOLVED and untouched by this file.**

## The contradiction, quoted from one Authority line

RPC §20.7.8's heading and Authority line say **`EXEC: DEF`**; the *same* Authority line says *"`REVOKE
EXECUTE FROM anon`; `EXECUTE` to `authenticated`"*; §0.1a defines `EXEC: DEF` as `service_role` **only**.
`R-29`'s proposed RLS row restates the contradiction verbatim. `T-RPC-GLOBAL-02` fails on it.

## Why this is NOT the `ID-5` class — three material differences

1. **`record_money_denial` had one side PROVEN UNBUILDABLE** (`C93`: on `service_role`, `auth.uid()` is
   NULL and the `NOT NULL FK` cannot be satisfied — fails on every call). **Both of this function's
   configurations are buildable.** It writes nothing, grants nothing, and returns a boolean.
2. **`record_money_denial`'s repair was RATIFIED TWICE** (`C93`, `C106`) before the labels were deleted.
   `C108`/`R1-4` ratified this function's **return shape** (one function, `p_raise DEFAULT true`) and
   `C66`/`K-15` its **equality property** — neither ratifies a grant class.
3. **The stated justification for the `authenticated` grant is technically false, but falsity of a reason
   is not ratification of the opposite.** *"It is called inside definers that run as the caller's
   `auth.uid()`"* — inside a `SECURITY DEFINER` function, `auth.uid()` is indeed preserved, but the
   `EXECUTE` privilege check runs as the **owner** (`postgres`), so definer-internal calls need **no**
   grant. All three contracted callers (`request_export`, `authorize_export_download`,
   `list_export_jobs`) are definers (`T-RPC-GLOBAL-01`); *"by `list_export_jobs` on the caller's own
   client"* describes how the OUTER function is invoked, not a direct client call to this one. **No RLS
   policy references it** (checked: its RLS citations are in-body predicates, §16.11's matrix, and
   `T-RLS-CRM-05`). **No product spec calls it from a client.**

## The one bit

| option | consequence |
|---|---|
| **(a) true `EXEC: DEF`** — `REVOKE` all, `service_role` only per §0.1a (or no grant at all) | least privilege; matches every live call path; `T-RPC-GLOBAL-02` passes; `R-29`'s RLS row is corrected to `DEF`. Risk: none identified — no caller loses a working path |
| **(b) caller-authorized** — keep the `authenticated` grant, delete the `EXEC: DEF` labels | matches the letter of the current Authority line; harmless by the contract's own leak argument ("a leaked `true` discloses nothing"); but grants a privilege NO live path uses, and the grant's stated justification is false |

**Recommendation: (a)** — least privilege, zero functional loss, and the corpus's own standing rule
(*"a control that depends on callers remembering IS a convention"*) is unaffected because the raising
default lives in the function either way. **Not ruled here**: unlike `ID-5`, no ratified row picks a side,
and removing OR keeping a grant is a security-posture choice — the mechanical-repair rule's limb 3 fails.

**Until ruled, `T-RPC-GLOBAL-02` continues to fail corpus-wide on this one function.** That failure is
recorded, expected, and not `X-8`'s.
