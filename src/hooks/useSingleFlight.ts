/**
 * src/hooks/useSingleFlight.ts — a per-screen single-flight lock.
 *
 * One instance for the life of the component, so a double tap on Place bid,
 * Buy now or Confirm receipt can never run the handler twice (CFT-205).
 */

import { useRef } from 'react';

import { createSingleFlight, type SingleFlight } from '@/src/lib/async/singleFlight';

export function useSingleFlight(): SingleFlight {
  const ref = useRef<SingleFlight | null>(null);
  if (!ref.current) ref.current = createSingleFlight();
  return ref.current;
}
