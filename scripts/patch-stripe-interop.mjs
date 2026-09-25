#!/usr/bin/env node
/**
 * scripts/patch-stripe-interop.mjs — make @stripe/stripe-react-native compile under Xcode 26.6.
 *
 * THE FAULT, and it is the package's own, not ours. `StripeSwiftInterop.h` hand-declares a type the
 * generated Swift header omits:
 *
 *     typedef NS_ENUM(NSUInteger, STPPaymentStatus);
 *
 * The SDK defines that enum in Swift as `@objc public enum STPPaymentStatus: Int`
 * (StripePayments/Source/Helpers/STPBlocks.swift:13), and Swift's `Int` is `NSInteger`. Xcode 26.6's
 * generated `stripe_react_native-Swift.h` now emits `SWIFT_ENUM_FWD_DECL(NSInteger, ...)`, which
 * clashes with the unsigned forward declaration above and fails the build with
 * "enumeration redeclared with different underlying type". So the shim is simply wrong about its own
 * SDK, and was wrong before this toolchain started saying so.
 *
 * UPSTREAM MADE EXACTLY THIS CHANGE: stripe-react-native `b613850f`, "fix: use NSInteger for
 * STPPaymentStatus interop (#2355)", +1/-1 on this line. Its first release is v0.61.0, eleven minors
 * ahead of our pinned 0.50.3 — which is why this is a narrow compatibility patch and not an SDK
 * upgrade (owner ruling 2026-09-25, A concurring).
 *
 * WHY A SCRIPT AND NOT A PODFILE EDIT: `/ios` is gitignored and regenerated at prebuild, so nothing
 * placed there survives. The fix has to land at install time, which is what `postinstall` is.
 *
 * WHY NOT patch-package: this needs to FAIL THE INSTALL rather than warn if the package version or
 * the target line is not exactly what is expected, and it needs no new dependency or lockfile entry
 * to do that. patch-package warns on a version mismatch and carries its own supply-chain surface.
 *
 * ON PAYMENT BEHAVIOUR — deliberately not claimed here. This file changes one declaration, and
 * "small edit" is not an argument. What can be said is narrow and checkable: no compiled code reads
 * a value through the changed declaration (the type appears in this header and in the Swift Apple
 * Pay completion callback; the nine `.mm` files that include the header never use its values, and
 * the Swift side does not read the ObjC typedef). The case values are unchanged, and both types are
 * 64-bit. What is NOT established: any runtime Apple Pay or PaymentSheet behaviour, because no
 * payment run was authorised — and separately, Xcode 26.6 is itself a change from the toolchain the
 * shipped builds were made with. A owns that assessment.
 */

import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';

const PKG = '@stripe/stripe-react-native';
const EXPECTED_VERSION = '0.50.3';
const REL = join('ios', 'StripeSwiftInterop.h');
const BEFORE = 'typedef NS_ENUM(NSUInteger, STPPaymentStatus);';
const AFTER = 'typedef NS_ENUM(NSInteger, STPPaymentStatus);';

/*
 * WHOLE-FILE PINS, and their provenance matters more than their presence.
 *
 * These are not hashes of whatever happened to be installed here — that would only prove this
 * machine agrees with itself. They come from UPSTREAM (A, 2026-09-25): the file at tag v0.50.3 and
 * at the fix's parent `b613850f^` is SHA_PRISTINE, and the file after the fix at `b613850f` is
 * SHA_PATCHED. So the post-condition below asserts that this script reproduces stripe's own commit
 * byte for byte, rather than that it produced something self-consistent.
 *
 * Verified: a fresh install here hashes to SHA_PRISTINE, and the result of this patch hashes to
 * SHA_PATCHED.
 *
 * `npm ci` already authenticates the tarball via the lockfile's integrity hash, so the pre-condition
 * is redundant on that path. It earns its place on the paths that have no such guarantee: plain
 * `npm install`, a restored cache, or a tree somebody has edited by hand.
 */
const SHA_PRISTINE = 'ba0d6791745a5b6500b50694acd41039a056fb8d6eda4c0a48ed6cbeee3d894f';
const SHA_PATCHED = 'b3b5c85659e26cb4b61455ad55b8e194b3a5f5ecd282ba873d3d1a1abbd469db';
const sha256 = (text) => createHash('sha256').update(text).digest('hex');

const die = (msg) => {
  console.error(`\n[patch-stripe-interop] REFUSING TO CONTINUE\n  ${msg}\n`);
  console.error(
    '  This patch exists so the iOS build compiles under Xcode 26.6. It deliberately fails the\n' +
    '  install rather than skipping quietly, because a silent skip would surface much later as an\n' +
    '  unexplained Stripe compile error. See the header of this file.\n',
  );
  process.exit(1);
};

const require = createRequire(import.meta.url);

let pkgJsonPath;
try {
  pkgJsonPath = require.resolve(`${PKG}/package.json`);
} catch {
  die(`${PKG} is not installed, so there is nothing to patch and the iOS build cannot succeed.`);
}

const version = JSON.parse(readFileSync(pkgJsonPath, 'utf8')).version;
if (version !== EXPECTED_VERSION) {
  die(
    `${PKG} is ${version}, but this patch was written against ${EXPECTED_VERSION}.\n` +
    `  Upstream fixed this in v0.61.0, so if the dependency has been raised to 0.61.0 or later the\n` +
    '  patch is no longer needed: delete this script and its postinstall entry. If it moved to some\n' +
    '  other version, re-verify the declaration by hand before changing this check.',
  );
}

const target = join(dirname(pkgJsonPath), REL);
let source;
try {
  source = readFileSync(target, 'utf8');
} catch {
  die(`${PKG}@${version} has no ${REL}. The package layout is not what this patch expects.`);
}

if (source.includes(AFTER)) {
  // Idempotent: a re-run, or an install that reused an already-patched tree. Still hashed, so an
  // "already applied" file that is not the file we expect is caught rather than trusted.
  const already = sha256(source);
  if (already !== SHA_PATCHED) {
    die(
      `${REL} already carries the patched declaration, but the file hashes ${already}\n` +
      `  and upstream's post-fix file is ${SHA_PATCHED}. Something else has changed this file.`,
    );
  }
  console.log(`[patch-stripe-interop] already applied (${PKG}@${version}), sha256 ${already}`);
  process.exit(0);
}

const pristine = sha256(source);
if (pristine !== SHA_PRISTINE) {
  die(
    `${REL} hashes ${pristine}, but upstream's v0.50.3 file is ${SHA_PRISTINE}.\n` +
    '  The file is not the one this patch was written against, so it will not be edited.',
  );
}

const hits = source.split(BEFORE).length - 1;
if (hits !== 1) {
  die(
    `expected exactly one occurrence of\n    ${BEFORE}\n  in ${REL}, found ${hits}.\n` +
    '  Neither the original nor the patched declaration is present as expected, so this script will\n' +
    '  not guess. Inspect the file and update this patch deliberately.',
  );
}

const patched = source.replace(BEFORE, AFTER);
const result = sha256(patched);
if (result !== SHA_PATCHED) {
  // A post-condition, not a formality: it is the assertion that this script reproduces upstream's
  // commit exactly, and it must hold before anything is written.
  die(
    `the patched file would hash ${result}, but upstream's post-fix file is ${SHA_PATCHED}.\n` +
    '  Nothing was written.',
  );
}
writeFileSync(target, patched);
console.log(
  `[patch-stripe-interop] applied to ${PKG}@${version}: NSUInteger -> NSInteger (STPPaymentStatus)\n` +
  `[patch-stripe-interop] sha256 ${SHA_PRISTINE} -> ${result} (matches upstream b613850f)`,
);
