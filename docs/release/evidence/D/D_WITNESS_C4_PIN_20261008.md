# D witness — console C4 (pin set), pre-C5

Witness: Claude D. Date: 2026-10-08. All values below are from **D's own reads**
in this session, not relayed from A. A's report is quoted only where marked.

## 1. The merge commit M

Fresh `git fetch origin admin/operating-console`, then:

| Claim | A reported | D measured | Verdict |
|---|---|---|---|
| tip of `admin/operating-console` | `f7e7e85f` | `f7e7e85f38c3d14e6ce38bb2fa1131fb66ec74bb` | MATCH |
| parent 1 | `562fda9a` | `562fda9aba261d7929ee772a4fd1ce50485c4294` | MATCH |
| parent 2 | `efe03fca` | `efe03fca5a88b074b2a675fb24fe718b53a9f4a3` | MATCH |
| `tree(M)` == `tree(efe03fca)` | yes | both `16957fffb9862e650c7cf4d0f412273a87c52bd5` | MATCH |
| `admin/src` == `1058c882` | yes | both `f297dab4e7c8` | SAME |
| `admin/tests` == `1058c882` | yes | both `6b76588f5732` | SAME |

**Negative control** (required — a comparison that returns SAME for everything
proves nothing): `docs` differs between M and `1058c882`
(`e217687e867a` vs `3ec55822cf88`). The comparison can return DIFF, so the
six SAME/MATCH results above are discriminating.

So M carries the reviewed console source byte-for-byte and nothing else in
`admin/`.

## 2. The pin (C4)

Raw read, `vercel api /v9/projects/snatchit-admin` under the owner's CLI login:

```
commandForIgnoringBuildStep = 'test "$VERCEL_GIT_COMMIT_SHA" != "f7e7e85f38c3d14e6ce38bb2fa1131fb66ec74bb"'
```

Checked properties, not just the string:

- exactly **one** 40-char hex sha in the guard, and it **equals** the measured
  tip of `admin/operating-console` (§1). Not typed from memory; compared
  programmatically.
- operator is `!=`, and no `==` appears.
- the variable is `VERCEL_GIT_COMMIT_SHA`.
- **Polarity** (exit 0 = skip): for the pinned sha the test is **false** →
  exit 1 → **build proceeds**. For any other sha the test is true → exit 0 →
  build skipped. This is the intended direction.

`project.updatedAt = 2026-10-08T03:35:28.219Z`. A reported reading the pin back
at 03:35:32Z — 4s later, consistent.

### Only the pin moved

Prior baseline is the committed `docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md`:

| Setting | 09-08 baseline | now | |
|---|---|---|---|
| guard | `… != "ab3e17f1a36e8c78c9fce31ee0b4fafdb6934d64"` | `… != "f7e7e85f…74bb"` | sha changed, shape identical |
| `rootDirectory` | `admin` | `admin` | unchanged |
| `nodeVersion` | `22.x` | `22.x` | unchanged |
| `link.productionBranch` | `admin/operating-console` | `admin/operating-console` | unchanged |
| `buildCommand` | (not recorded) | `null` | no baseline |

**Evidence limit:** the "prior" column is a record written 2026-09-08, not a
read D took immediately before A's PATCH. What this establishes is that the
configuration now differs from the 09-08 baseline **only in the pinned sha**.
It does not exclude some other change made and reverted between those dates.

## 3. Nothing was deployed

- Production aliases `snatchit-admin.vercel.app` and
  `snatchit-admin-gnvprod-5449s-projects.vercel.app` both resolve to
  **`dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr`**, `alias.updatedAt = 1788829038671`
  (2026-09-08). Unmoved.
- `latestDeployment` is still `dpl_74DoDNf53NLEmGuNHVwZx4pAqWiY` (CANCELED,
  created 02:15:26Z) — i.e. **no deployment was created by the 03:35 pin
  PATCH**. A settings change does not rebuild; measured, not assumed.

**Read trap worth recording:** `get_deployment(dpl_74DoDN).alias` *lists* both
production aliases. That field is the alias assignment the deployment would
take, **not** what it currently serves. The authoritative read is
`list_aliases`, which resolves both to `dpl_J5Kr`. Reading the deployment
object alone would have produced a false "it is already serving" conclusion.

## 4. Why dpl_74DoDN is CANCELED — established, not assumed

The plan depends on that deployment having been stopped by the **old guard**
rather than by a build failure. Confirmed:

- `errorLink = https://vercel.com/docs/platform/projects#ignored-build-step`
- `buildingAt 1791425727872` → `ready 1791425731078` = **3.2 s** (no Next.js
  build completes in 3.2s)

Its sha `f7e7e85f` did not match the then-current pin `ab3e17f1`, so the guard
returned exit 0. Exactly the designed behaviour: the merge landed and deployed
nothing.

## 5. C5 — what is and is not established

Established: the pin now admits `f7e7e85f` and only `f7e7e85f`; the commit
carries the reviewed source; nothing is deployed; the rollback target
`dpl_J5Kr` is live and serving.

**Not established — flagged before the owner's session:**

1. **Whether the dashboard offers "Redeploy" on a CANCELED deployment.** Still
   unread. `isRollbackCandidate: false` on `dpl_74DoDN`.
2. **That Redeploy re-evaluates the Ignored Build Step against the *current*
   project setting.** A CANCELED deployment has no build output to reuse, so it
   must rebuild and must re-read the guard — but that is reasoning from the
   mechanism, **not a measurement**. It is the one assumption C5 rests on.
3. If Redeploy is not offered, the remaining in-policy route is a CLI redeploy
   of that deployment id (preserves the sha, so the guard passes). Untested —
   and per the owner's correction, one cancelled CLI attempt does **not**
   establish that CLI deployment cannot pass a pin.

Per the owner: if the approved exact-commit routes fail, **stop** with the
measured result. No protection removal, no re-trigger commits.

## 6. Vercel SSO — relevant to "console access confirmed"

`ssoProtection.enabled = true`, `deploymentType = all_except_custom_domains`.
The console's `*.vercel.app` hosts sit behind Vercel SSO, which is **separate
from** the console's own MFA/`aal2`. Reaching the console needs both. Recorded
because "console access is confirmed" is an O-R2 precondition and this is a
second gate on it.

## 7. G3 (Stripe endpoint) — not witnessed by D

A's G3 is the **owner's screenshot**, relayed. D has not read the Stripe
endpoint and cannot verify it. Two load-bearing points:

- **11 of 13 events are visible; two are below the cut.** The O-R2 precondition
  was the *full* event list. On the evidence in hand it is **not satisfied** —
  11/13 is not 13/13, and the two unseen entries are unconstrained.
- **No change was made** — the three refund events were already subscribed, and
  **no earlier list exists**. So this is current configuration, not a
  before/after. Owner item 5 ("add refund.created/updated/failed") turns out to
  have been a no-op; that is a finding about the prior state, not a completed
  change.

A's inference that refund events arriving while v42 was live were "acknowledged
and discarded" is **not verified by D** — I have not read v42's handler. Note
also that "0 deliveries this week" says nothing about historical deliveries,
which is the period O-R4 is about.

---

## 8. Correction to §6 — the console is ONE gate, not two

**§6 is wrong and is withdrawn.** I inferred from
`ssoProtection.deploymentType = all_except_custom_domains` that the console's
`*.vercel.app` hosts sit behind Vercel SSO, and told A and the owner that
"console access confirmed" was two gates. A disputed it from the 09-08 record.
A is right. Measured with unauthenticated `curl` (no cookies, no redirect
following), 2026-10-08:

| Host | Result |
|---|---|
| `snatchit-admin.vercel.app/login` | **HTTP 200**, body `<title>Sign in · Console · production</title>` |
| `snatchit-admin.vercel.app/` | 307 → `/login?next=%2F` (the app's own redirect) |
| `…-git-admin-operatin-389230-….vercel.app/login` | **302 → `vercel.com/sso-api`** + `_vercel_sso_nonce` cookie |
| `…-jhe92fpqv-….vercel.app/login` (dpl_J5Kr's own URL) | **302 → `vercel.com/sso-api`** + `_vercel_sso_nonce` cookie |

**Positive control satisfied:** the last two rows show the probe *does* detect
Vercel SSO gating when it is present. So the 200 on the production alias is a
real negative, not a logged-in false negative — which is the failure mode that
would otherwise make the 09-08 observation untrustworthy.

**The mechanism I had wrong:** the exemption in
`all_except_custom_domains` is not about the `.vercel.app` suffix. Vercel treats
the project's **production alias** as exempt; preview aliases and the
deployment's own URL are not. `project.alias` is empty (0 entries), so there is
no custom domain — the exempt host is the production alias itself.

**Consequence, and it runs the other way from my §6 claim:** there is **no
Vercel-layer backstop** in front of the production console. Its own
authentication is the sole gate, so the console's MFA/`aal2` is load-bearing
alone. That is not a new exposure — the 09-08 record has both founders on real
MFA — but §6 stated a reassurance that does not exist, which is worse than
stating nothing.

C5 is unaffected: SSO was my own added concern, now withdrawn. Gaps 1 and 2
in §5 stand unchanged.

---

## 9. C5 attempt 1 — wrong deployment, nothing reached production

Owner clicked Redeploy ~23:39:33Z 2026-10-08 and stopped on the Error result.
D's own reads:

**The deployment created: `dpl_iAzLKA1UFtjD9qC2uc7fn8itcM8d`**

| Field | Value |
|---|---|
| `source` | **`redeploy`** |
| `target` | `null` → **Preview**, not production |
| `meta.githubCommitRef` | **`feature/venue-native-and-product-v2`** |
| `meta.githubCommitSha` | **`c4f562dad36ffcdcacb1fe3ba1387f7ab1bbf4cd`** |
| `state` / `readyState` | ERROR |
| `errorCode` | **`NOW_SANDBOX_WORKER_ROOTDIR_NOT_EXIST`** |
| `errorMessage` | `The specified Root Directory "admin" does not exist. Please update your Project Settings.` |
| `errorStep` | **`build-container-init`** |
| `buildingAt → ready` | 23:39:34.870 → 23:39:37.710 = **2.84 s** |
| `alias` | only the venue-branch preview alias |

Its `meta` is identical to `dpl_HYCvcS9Ssv1Xcw7KNA85cyvs8PCB` (Sep-8, ERROR,
preview, same ref and sha), which is what the owner's screenshot said
("Redeploy of HYCvcS9Ss"). So the Redeploy was applied to a **September preview
deployment of the venue branch**, not to `dpl_74DoDN`.

**Root cause — already documented, now reproduced.**
`docs/admin-console/DEPLOYMENT_RECORD_2026-09-08.md:113` records that Vercel
validates the Root Directory **right after cloning and before running the
Ignored Build Step**. `admin/` exists only on `admin/operating-console`. The
venue branch has no `admin/` tree, so the container init fails. That is why
this is ERROR (2.84s) and not CANCELED. Corroborated in the build log via CLI:
`23:39:37.635Z The specified Root Directory "admin" does not exist.`

### Three consequences

1. **Nothing reached production.** Target was Preview; the production alias was
   never a candidate.
2. **The pin was never exercised.** `errorStep = build-container-init` precedes
   the Ignored Build Step. So attempt 1 is **not** evidence about §5 gap 2
   (whether Redeploy re-evaluates the current guard). That gap is still open.
3. **The error message is a trap.** It says *"Please update your Project
   Settings."* Root Directory `admin` is **correct** and must not change —
   changing it would break the console build on the one branch that works. The
   owner stopped instead of following it, which was right.

### Post-attempt state re-read (D's own, after the failure)

| Check | Result |
|---|---|
| `commandForIgnoringBuildStep` | **UNCHANGED** — `… != "f7e7e85f…74bb"` |
| `rootDirectory` / `nodeVersion` | **UNCHANGED** — `admin` / `22.x` |
| `project.updatedAt` | **1791430528219, byte-identical to the 03:35 read** |
| `snatchit-admin.vercel.app` | `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr` |
| `snatchit-admin-gnvprod-5449s-projects.vercel.app` | `dpl_J5Kr4QSBmRjxmJbu2nT7KovSxmsr` |
| `dpl_74DoDN` | still CANCELED / production / `f7e7e85f` |

The identical `updatedAt` is the stronger check: any settings PATCH — including
a change made and reverted — would have bumped it. It did not move. No
settings changed.

A's independent re-read (717acde2) agrees on all four points.

**Evidence limit:** the MCP build-logs endpoint returned 403 (scope
`gnvprod-5449s-projects`). The structured `errorCode`/`errorMessage`/`errorStep`
on the deployment object, plus the CLI `inspect --logs` line above, are the
basis for the root-cause claim — not the MCP log stream.

### Open question attempt 2 should also answer

Why the owner landed on that row is unestablished. One live possibility is §5
gap 1 — that Redeploy is **not offered** on the CANCELED production deployment,
so the nearest row that offered it was used. Attempt 2 from the exact
deployment URL settles gap 1 as a by-product: either the action is present on
that page or it is not.
