/**
 * src/lib/checkout/paymentErrors.ts — customer-facing copy for a failed sheet.
 *
 * The payment sheet returns native SDK errors whose messages are developer text,
 * e.g. "The operation couldn't be completed. (kCFErrorDomainCFNetwork error
 * -1001.)". That was being put straight into an Alert. The raw error stays in the
 * logs; the customer gets one short line in the existing product voice.
 */

export interface PaymentSheetErrorLike {
  code?: string | null;
  message?: string | null;
}

/** A transport failure (timeout / offline / DNS), not a declined card. */
export function isNetworkPaymentError(e: PaymentSheetErrorLike | null | undefined): boolean {
  const hay = `${e?.code ?? ''} ${e?.message ?? ''}`;
  return /CFErrorDomainCFNetwork|NSURLError|timed? ?out|network|offline|internet|connection/i.test(hay);
}

/** The user tapped Cancel — never an error state. */
export function isCancelledPaymentError(e: PaymentSheetErrorLike | null | undefined): boolean {
  return (e?.code ?? '') === 'Canceled';
}

/**
 * One short line, existing vocabulary, no system codes and no AI phrasing.
 */
export function paymentSheetErrorCopy(e: PaymentSheetErrorLike | null | undefined): string {
  if (isNetworkPaymentError(e)) return 'Payment connection timed out. Try again.';
  return "We couldn't complete payment. Please try again.";
}
