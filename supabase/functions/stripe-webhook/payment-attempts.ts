// Sibling binding for the shared, fail-closed attempt-mark client. The edge VM
// resolves this real module; no duplicate implementation and no test stub.
export { markPaymentAttemptByPi, PaymentAttemptNotFound } from '../primary-checkout/payment-attempts.ts';
export type { RpcCaller } from '../primary-checkout/payment-attempts.ts';
