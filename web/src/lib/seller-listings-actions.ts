"use server";

import { revalidatePath } from "next/cache";
import { getAuthedUser } from "@/lib/auth/session";
import {
  cancelSellerListing,
  deleteSellerListing,
  updateSellerListing,
  type EditableListingFields,
  type MutationResult,
} from "@/lib/seller-listings";

export async function updateListingAction(
  listingId: string,
  fields: EditableListingFields,
): Promise<MutationResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  const result = await updateSellerListing(user.id, listingId, fields);
  if (result.ok) {
    revalidatePath("/account/listings");
    revalidatePath(`/listing/${listingId}`);
  }
  return result;
}

export async function cancelListingAction(listingId: string): Promise<MutationResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  const result = await cancelSellerListing(user.id, listingId);
  if (result.ok) {
    revalidatePath("/account/listings");
    revalidatePath(`/listing/${listingId}`);
  }
  return result;
}

export async function deleteListingAction(listingId: string): Promise<MutationResult> {
  const user = await getAuthedUser();
  if (!user) return { error: "AUTH_REQUIRED" };
  const result = await deleteSellerListing(user.id, listingId);
  if (result.ok) revalidatePath("/account/listings");
  return result;
}
