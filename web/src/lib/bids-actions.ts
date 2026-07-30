"use server";

import { getAuthedUser } from "@/lib/auth/session";
import { placeBid, type PlaceBidResult } from "@/lib/bids";

export async function placeBidAction(listingId: string, amountDollars: number): Promise<PlaceBidResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  return placeBid(listingId, user.id, amountDollars);
}
