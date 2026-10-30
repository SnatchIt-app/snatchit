/**
 * src/lib/tickets/api.ts — the one call into the Tickets ownership read.
 *
 * Wraps public.get_my_tickets() (Core @ 6dc3ee0). No arguments, owner-scoped by
 * construction on the server (binds to auth.uid()); the client passes nothing and
 * chains nothing. Typed locally via `.returns<MyTicketGroup[]>()` — the supabase
 * client is not parameterized with generated Database types (see src/types), so
 * no Core/schema type file is touched.
 */

import { supabase } from '@/src/lib/supabase';
import type { MyTicketGroup } from './types';

export interface TicketsResult {
  data: MyTicketGroup[] | null;
  error: { code?: string; message?: string } | null;
}

export async function fetchMyTickets(): Promise<TicketsResult> {
  // No .select(), no filters, no owner argument — the RPC returns the finished,
  // owner-scoped, event-first shape. `[]` is a successful empty result. The client
  // is not parameterized with generated Database types (see src/types), so the
  // SETOF result is cast locally to the contract shape.
  const { data, error } = await supabase.rpc('get_my_tickets');
  if (error) {
    return { data: null, error: { code: (error as { code?: string }).code, message: error.message } };
  }
  return { data: (data as unknown as MyTicketGroup[]) ?? [], error: null };
}
